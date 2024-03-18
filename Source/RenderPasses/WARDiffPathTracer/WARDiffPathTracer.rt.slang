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

    return float2(0.f);
}

// Evaluate pdf of Gaussian at xy, and correlation(x, y) = 0
[Differentiable]
[PreferRecompute]
float evalGaussian(float2 xy, no_diff float sigma)
{
    // see https://en.wikipedia.org/wiki/Multivariate_normal_distribution, Bivariate case

    return 1.f;
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


    // Warped-area reparameterization for primary rays. Check kUseWAR
    if (kUseWAR)
    {
        // multiply path thruput with weight = det(Jacobian) returned from reparameterizePrimarySample
        // frameDim is from DiffPTData.params

    }

    // Use Gaussian pixel filter: find pdf and update thruput with pdf / detach(pdf)


    // construct a differentiable RayAD; detach origin; get pixel from sceneQuery


    // while (condition A and condition B)
    // A. not terminated
    // B. whether ray hits during differentiable PT; DiffIntersectionMode should be AttachToRay;
    [MaxIters(MAX_BOUNCES + 2)]
    while (
        true
    )
    {
        // handleHit(): it will do computations and update terminated flag

    }

    // After break, return radiance

    return float3(0.f);
}

// trace all interior paths of a pixel
// return RGB radiance of that pixel
[Differentiable]
float3 tracePaths(SceneQueryAD sceneQuery, uint2 pixel)
{
    float3 result = float3(0.f);

    // select frame seed depending on useFixedSeed; if not fixed, use frameCount


    // Create SampleGenerator
    // see Source\Falcor\Utils\Sampling\TinyUniformSampleGenerator.slang
    // use 0.5 * frameSeed


    // Throw away some samples.
    // (Possibly) to make it truely random since first few depend on frame count or a fixed seed


    // Use Gaussian pixel filter.


    // Antithetic sampling for differentiable rendering (interior term).
    // check kUseAntitheticSampling and parity of frame seed: negate jitter


    // Trace an interior path and accumulate to radiance


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

    // get (linear) pixel id = y * dimX + x

    // printSetPixel() s.t. we can do pixel debug


    // create DiffSceneIO (no init) and SceneQueryAD
    // _gradInfo has SceneGradientFlag of GradientMode.Scene

    // later, use
    // DifferentialPair<SceneQueryAD> _xx_ = diffPair(sceneQuery, SceneQueryAD.Differential)
    // and pass it to fwd_diff or bwd_diff of tracePaths()

    // switch kDiffMode
    if (kDiffMode == DiffMode::Primal)
    {
        // Primal rendering.

    }
    else if (kDiffMode == DiffMode::BackwardDiff)
    {

        // but if runBackward = 0, still do primal rendering
        if (true)
        {

        }
        else
        {
            // Set differential query mode to `Scene` for visualizing gradient images.
            // Done in SceneQueryAD.Differential.gradInfo


            // create differentiable SceneQueryAD


            // bwd_diff on tracePaths(); last arg resultGradient should be dLdI indexed by pixel ID
            // uint pixelIdx = pixel.y * params.frameDim.x + pixel.x;

        }
    }
    else if (kDiffMode == DiffMode::ForwardDiffDebug)
    {
        // Forward-mode differentiable rendering for visualizing gradients.

        // Set differential query mode to `ForwardDebug` for visualizing gradient images.
        // Done in SceneQueryAD.Differential.gradInfo


        // call fwd_diff on tracePaths() and store RGB in a DifferentialPair<float3>

        // and use it to write to output gOutputColor


        // Clamp gradient values (using gDiffPTData.params.assertThreshold)

        // and write to gOutputDColor; Only show the red channel.

    }
    else if (kDiffMode == DiffMode::BackwardDiffDebug)
    {
        // Reverse-mode differentiable rendering for visualizing gradients.

        // Set differential query mode to `Scene` for visualizing gradient images.
        // Done in SceneQueryAD.Differential.gradInfo


        // create differentiable SceneQueryAD


        // bwd_diff on tracePaths(); last arg resultGradient should be float3(1,0,0)

    }
}
