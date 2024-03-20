/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#include "Utils/Math/MathConstants.slangh"

import Rendering.Lights.EmissiveLightSampler;
import Scene.Raytracing;
import Scene.RaytracingInline;
import Utils.Sampling.SampleGenerator;
import Utils.Debug.PixelDebug;
import DiffRendering.SharedTypes;
import DiffRendering.DiffSceneIO;
import DiffRendering.DiffSceneQuery;
import DiffRendering.DiffDebugParams;
import DiffRendering.InverseOptimizationParams;

import PTUtils;
import WarpedAreaReparam;

static const float kPixelGaussianSigma = 0.5f;

struct DiffPTData
{
    WARDiffPathTracerParams params;
    EmissiveLightSampler emissiveSampler;
};

ParameterBlock<DiffPTData> gDiffPTData;

StructuredBuffer<float3> dLdI;

// Outputs
RWTexture2D<float4> gOutputColor;

// Convert square samples, two Unif(0,1), to Gaussian samples,
// for gittered 2D Gaussian filter with indep entry, mean 0, and variance float2(sigma^2)
float2 sampleGaussian(float2 xy, float sigma)
{
    // see https://en.wikipedia.org/wiki/Box%E2%80%93Muller_transform
    return sigma * sqrt(-2.0f * log(xy.x)) * float2(cos(M_2PI * xy.y), sin(M_2PI * xy.y));
}

// Evaluate pdf of Gaussian at xy, and correlation(x, y) = 0
[Differentiable]
[PreferRecompute]
float evalGaussian(float2 xy, no_diff float sigma)
{
    // see https://en.wikipedia.org/wiki/Multivariate_normal_distribution, Bivariate case
    // simplied to (1 / two_pi * sigma^2) * exp(-0.5 * x^2 + y^2 / sigma^2)
    // (1 / 2 * sigma^2) can be reused
    float temp = 0.5f / (sigma * sigma);
    return temp * M_1_PI * exp(temp * dot(xy, xy));
}

// Trace an interior path.
[Differentiable]
float3 tracePath(
    SceneQueryAD sceneQuery, // do differentiable path tracing by .traceRayInlineAD()
    float2 pixel, // pixel center + filter
    no_diff float2 pixelCenter,  // (i+0.5, j+0.5)
    inout SampleGenerator sg
)
{
    // create empty PathData and IntersectionAD
    PathData pathData;
    IntersectionAD isectAD;


    // Warped-area reparameterization for primary rays. Check kUseWAR
    if (kUseWAR)
    {
        // multiply path thruput with weight = det(Jacobian) returned from reparameterizePrimarySample
        // frameDim is from DiffPTData.params
        pathData.thp *= reparameterizePrimarySample(sceneQuery, gDiffPTData.params.frameDim, sg, pixel);
    }

    // Use Gaussian pixel filter: find pdf and update thruput with pdf / detach(pdf)
    float pdf = evalGaussian(pixel - pixelCenter, kPixelGaussianSigma);
    pathData.thp *= pdf / detach(pdf);

    // construct a differentiable RayAD; detach origin; get pixel from sceneQuery
    RayAD ray = RayAD(
        sceneQuery.loadCameraPosition(),
        sceneQuery.computeCameraRayDirection(pixel, gDiffPTData.params.frameDim),
        sceneQuery.gradInfo.pixel  // uint2 pixel index
    );


    // while (condition A and condition B)
    // A. not terminated
    // B. whether ray hits during differentiable PT; DiffIntersectionMode should be AttachToRay;
    [MaxIters(MAX_BOUNCES + 2)]
    while (
        !pathData.terminated &&
        sceneQuery.traceRayInlineAD(ray, isectAD, SceneQueryAD.DiffIntersectionMode.AttachToRay)
    )
    {
        // handleHit(): it will do computations and update terminated flag
        handleHit(sceneQuery, isectAD, gDiffPTData.emissiveSampler, pathData, ray, sg, kUseWAR);
    }

    // After break, return radiance
    return pathData.radiance;
}

// trace all interior paths of a pixel
// return RGB radiance of that pixel
[Differentiable]
float3 tracePaths(SceneQueryAD sceneQuery, uint2 pixel)
{
    float3 result = float3(0.f);

    // select frame seed depending on useFixedSeed; if not fixed, use frameCount
    uint frameSeed = select(
        bool(gDiffPTData.params.useFixedSeed),  // condition
        gDiffPTData.params.fixedSeed,  // if true
        gDiffPTData.params.frameCount  // if false
    );

    // Create SampleGenerator
    // see Source\Falcor\Utils\Sampling\TinyUniformSampleGenerator.slang
    // use 0.5 * frameSeed;
    // frameSeed is treated as initial given value, not actual seed of sg
    SampleGenerator sg = SampleGenerator(pixel, frameSeed / 2);

    // Throw away some samples.
    // (Possibly) to make it truely random since first few depend on frame count or a fixed seed
    no_diff sampleNext1D(sg);
    no_diff sampleNext2D(sg);
    no_diff sampleNext3D(sg);

    // Use Gaussian pixel filter.
    float2 pixelCenter = pixel + float2(0.5f);
    float2 rndXY = no_diff sampleNext2D(sg);
    float2 dpixel = no_diff sampleGaussian(rndXY, kPixelGaussianSigma);

    // Antithetic sampling for differentiable rendering (interior term).
    // check kUseAntitheticSampling and parity of frame seed: negate jitter
    if (kUseAntitheticSampling && frameSeed % 2 == 1) {
        dpixel = -dpixel;
    }

    // Trace an interior path and accumulate to radiance
    result += tracePath(sceneQuery, pixelCenter + dpixel, pixelCenter, sg);
    return result;
}

/**
 * top-level caller as a shader
 * @return is written to gOutputColor[pixel] and gOutputDColor[pixel], both float4(RGB, 1.f)
 */
[shader("raygeneration")]
void rayGen()
{
    // get pixel (x,y) from DispatchRaysIndex()
    uint2 pixel = DispatchRaysIndex().xy;

    // get (linear) pixel id = y * dimX + x
    uint pixelID = pixel.y * gDiffPTData.params.frameDim.x + pixel.x;

    // printSetPixel() s.t. we can do pixel debug
    printSetPixel(pixel);

    // create DiffSceneIO (no init) and SceneQueryAD
    // _gradInfo has SceneGradientFlag of GradientMode.Scene
    DiffSceneIO dSceneIO;
    SceneQueryAD sceneQuery = SceneQueryAD(dSceneIO, SceneGradientInfo({ GradientMode.Scene }, pixel, pixelID));

    // later, use
    // DifferentialPair<SceneQueryAD> _xx_ = diffPair(sceneQuery, SceneQueryAD.Differential)
    // and pass it to fwd_diff or bwd_diff of tracePaths()

    // switch kDiffMode
    if (kDiffMode == DiffMode::Primal)
    {
        // Primal rendering.
        float3 RGB = tracePaths(sceneQuery, pixel);
        gOutputColor[pixel] = float4(RGB, 1.f);
    }
    else if (kDiffMode == DiffMode::BackwardDiff)
    {

        // but if runBackward = 0, still do primal rendering
        if (gDiffPTData.params.runBackward == 0)
        {
            float3 RGB = tracePaths(sceneQuery, pixel);
            gOutputColor[pixel] = float4(RGB, 1.f);
        }
        else
        {
            // Set differential query mode to `Scene` for visualizing gradient images.
            // Done in SceneQueryAD.Differential.gradInfo
            SceneQueryAD.Differential dSceneQuery;
            dSceneQuery.gradInfo = { GradientMode.Scene };

            // create differentiable pair SceneQueryAD
            DifferentialPair<SceneQueryAD> dpScene = diffPair(sceneQuery, dSceneQuery);

            // bwd_diff on tracePaths(); last arg resultGradient should be dLdI indexed by pixel ID
            // uint pixelIdx = pixel.y * params.frameDim.x + pixel.x;
            bwd_diff(tracePaths)(dpScene, pixel, dLdI[pixelID]);
        }
    }
    else if (kDiffMode == DiffMode::ForwardDiffDebug)
    {
        // Forward-mode differentiable rendering for visualizing gradients.

        // Set differential query mode to `ForwardDebug` for visualizing gradient images.
        // Done in SceneQueryAD.Differential.gradInfo
        SceneQueryAD.Differential dSceneQuery;
        dSceneQuery.gradInfo = { GradientMode.ForwardDebug };

        // create differentiable pair SceneQueryAD
        DifferentialPair<SceneQueryAD> dpScene = diffPair(sceneQuery, dSceneQuery);

        // call fwd_diff on tracePaths() and store RGB in a DifferentialPair<float3>
        DifferentialPair<float3> dpColor = fwd_diff(tracePaths)(dpScene, pixel);

        // and use it to write to output gOutputColor
        gOutputColor[pixel] = float4(dpColor.p, 1.f);

        // CHECK gradient values (using gDiffPTData.params.assertThreshold)
        // only store values within the bound
        float absBound = gDiffPTData.params.assertThreshold;
        bool inBound = (
            max(dpColor.d.x, max(dpColor.d.y, dpColor.d.z)) < absBound &&
            min(dpColor.d.x, min(dpColor.d.y, dpColor.d.z)) > -absBound
        );

        // and write to gOutputDColor; Only show the red channel.
        if (inBound) {
            gOutputDColor[pixel] = float4(dpColor.d.x, 0.f, 0.f, 1.f);
        }

    }
    else if (kDiffMode == DiffMode::BackwardDiffDebug)
    {
        // Reverse-mode differentiable rendering for visualizing gradients.

        // Set differential query mode to `Scene` for visualizing gradient images.
        // Done in SceneQueryAD.Differential.gradInfo
        SceneQueryAD.Differential dSceneQuery;
        dSceneQuery.gradInfo = { GradientMode.Scene };

        // create differentiable SceneQueryAD
        DifferentialPair<SceneQueryAD> dpScene = diffPair(sceneQuery, dSceneQuery);

        // bwd_diff on tracePaths(); last arg resultGradient should be float3(1,0,0)
        bwd_diff(tracePaths)(dpScene, pixel, float3(1.f, 0.f, 0.f));
    }
}
