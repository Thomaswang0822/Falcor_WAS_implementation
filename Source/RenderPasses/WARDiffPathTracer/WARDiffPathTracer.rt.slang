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
    return sqrt(-2.f * log(xy.x)) * float2(cos(M_2PI * xy.y), sin(M_2PI * xy.y)) * sigma;
}

// Evaluate pdf of Gaussian at xy, and correlation(x, y) = 0
[Differentiable]
[PreferRecompute]
float evalGaussian(float2 xy, no_diff float sigma)
{
    // see https://en.wikipedia.org/wiki/Multivariate_normal_distribution, Bivariate case
    const float alpha = (-1.f / (2.f * sigma * sigma));
    return exp(alpha * dot(xy, xy)) * (1.f / (M_2PI * sigma * sigma));
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
    PathData pathData = PathData();
    IntersectionAD isect = IntersectionAD();

    // Warped-area reparameterization for primary rays. Check kUseWAR
    if (kUseWAR)
    {
        // multiply path thruput with weight = det(Jacobian) returned from reparameterizePrimarySample
        // frameDim is from DiffPTData.params
        float weight = reparameterizePrimarySample(sceneQuery, gDiffPTData.params.frameDim, sg, pixel);
        pathData.thp *= weight;
    }

    // Use Gaussian pixel filter: find pdf and update thruput with pdf / detach(pdf)
    float pixelWeight = evalGaussian(pixel - pixelCenter, kPixelGaussianSigma);
    pathData.thp *= pixelWeight / detach(pixelWeight);

    // construct a differentiable RayAD; detach origin; get pixel from sceneQuery
    float3 primaryRayOrigin = sceneQuery.loadCameraPosition();
    float3 primaryRayDirection = sceneQuery.computeCameraRayDirection(pixel, gDiffPTData.params.frameDim);
    RayAD ray = RayAD(detach(primaryRayOrigin), primaryRayDirection, sceneQuery.gradInfo.pixel);

    // while (condition A and condition B)
    // A. not terminated
    // B. whether ray hits during differentiable PT; DiffIntersectionMode should be AttachToRay;
    [MaxIters(MAX_BOUNCES + 2)]
    while (
        !pathData.terminated &&
        sceneQuery.traceRayInlineAD(ray, isect, SceneQueryAD.DiffIntersectionMode.AttachToRay)
    )
    {
        // handleHit(): it will do computations and update terminated flag
        handleHit(sceneQuery, isect, gDiffPTData.emissiveSampler, pathData, ray, sg, kUseWAR);
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
    WARDiffPathTracerParams params = gDiffPTData.params;
    uint frameSeed = bool(params.useFixedSeed) ? params.fixedSeed : params.frameCount;

    // Create SampleGenerator
    // see Source\Falcor\Utils\Sampling\TinyUniformSampleGenerator.slang
    // use 0.5 * frameSeed
    SampleGenerator sg = SampleGenerator(pixel, frameSeed / 2);

    // Throw away some samples.
    // (Possibly) to make it truely random since first few depend on frame count or a fixed seed
    no_diff sampleNext2D(sg);
    no_diff sampleNext2D(sg);
    no_diff sampleNext2D(sg);

    // Use Gaussian pixel filter.
    float2 pixelf = pixel + float2(0.5f, 0.5f);
    float2 uniform2D = no_diff sampleNext2D(sg);
    float2 jitter2D = no_diff sampleGaussian(uniform2D, kPixelGaussianSigma);

    // Antithetic sampling for differentiable rendering (interior term).
    // check kUseAntitheticSampling and parity of frame seed: negate jitter
    if (kUseAntitheticSampling && frameSeed % 2 == 1)
        jitter2D = -jitter2D;

    // Trace an interior path and accumulate to radiance
    result += tracePath(sceneQuery, pixelf + jitter2D, pixelf, sg);

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
    DiffSceneIO diffSceneIO;
    SceneQueryAD sceneQuery = SceneQueryAD(diffSceneIO, SceneGradientInfo(SceneGradientFlag.make(GradientMode.Scene), pixel, pixelID));
    // later, use
    // DifferentialPair<SceneQueryAD> _xx_ = diffPair(sceneQuery, SceneQueryAD.Differential)
    // and pass it to fwd_diff or bwd_diff of tracePaths()

    // switch kDiffMode
    if (kDiffMode == DiffMode::Primal)
    {
        // Primal rendering.
        float3 color = tracePaths(sceneQuery, pixel);
        gOutputColor[pixel] = float4(color, 1.f);
    }
    else if (kDiffMode == DiffMode::BackwardDiff)
    {
        var params = gDiffPTData.params;
        float3 color = float3(0.f);
        // but if runBackward = 0, still do primal rendering
        if (params.runBackward == 0)
        {
            color = tracePaths(sceneQuery, pixel);
            gOutputColor[pixel] = float4(color, 1.f);
        }
        else
        {
            // Set differential query mode to `Scene` for visualizing gradient images.
            // Done in SceneQueryAD.Differential.gradInfo
            SceneQueryAD.Differential dQuery;
            dQuery.gradInfo = { SceneGradientFlag.make(GradientMode.Scene) };

            // create differentiable SceneQueryAD
            DifferentialPair<SceneQueryAD> dpQuery = diffPair(sceneQuery, dQuery);

            // bwd_diff on tracePaths(); last arg resultGradient should be dLdI indexed by pixel ID
            // uint pixelIdx = pixel.y * params.frameDim.x + pixel.x;
            bwd_diff(tracePaths)(dpQuery, pixel, dLdI[pixelID]);
        }
    }
    else if (kDiffMode == DiffMode::ForwardDiffDebug)
    {
        // Forward-mode differentiable rendering for visualizing gradients.

        // Set differential query mode to `ForwardDebug` for visualizing gradient images.
        // Done in SceneQueryAD.Differential.gradInfo
        SceneQueryAD.Differential dQuery;
        dQuery.gradInfo = { SceneGradientFlag.make(GradientMode.ForwardDebug) };

        // call fwd_diff on tracePaths() and store RGB in a DifferentialPair<float3>
        DifferentialPair<float3> dpColor = fwd_diff(tracePaths)(diffPair(sceneQuery, dQuery), pixel);
        // and use it to write to output gOutputColor
        gOutputColor[pixel] = float4(dpColor.p, 1.f);

        // Clamp gradient values (using gDiffPTData.params.assertThreshold)
        float maxValue = gDiffPTData.params.assertThreshold;
        bool resIsFinite = (dpColor.d[0] >= -maxValue && dpColor.d[0] <= maxValue) &&
                           (dpColor.d[1] >= -maxValue && dpColor.d[1] <= maxValue) &&
                           (dpColor.d[2] >= -maxValue && dpColor.d[2] <= maxValue);
        // and write to gOutputDColor; Only show the red channel.
        if (resIsFinite)
            gOutputDColor[pixel] = float4(dpColor.d[0], 0.f, 0.f, 1.f);
    }
    else if (kDiffMode == DiffMode::BackwardDiffDebug)
    {
        // Reverse-mode differentiable rendering for visualizing gradients.

        // Set differential query mode to `Scene` for visualizing gradient images.
        // Done in SceneQueryAD.Differential.gradInfo
        SceneQueryAD.Differential dQuery;
        dQuery.gradInfo = { SceneGradientFlag.make(GradientMode.Scene) };

        // create differentiable SceneQueryAD
        DifferentialPair<SceneQueryAD> dpQuery = diffPair(sceneQuery, dQuery);

        // bwd_diff on tracePaths(); last arg resultGradient should be float3(1,0,0)
        bwd_diff(tracePaths)(dpQuery, pixel, float3(1.f, 0.f, 0.f));
    }
}
