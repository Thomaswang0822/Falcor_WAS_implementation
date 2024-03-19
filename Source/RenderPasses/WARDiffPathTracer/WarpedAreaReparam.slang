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

import Scene.RaytracingInline;
import Utils.Sampling.SampleGenerator;
import Utils.Math.MathHelpers;
import Utils.Math.DiffMathHelpers;
import Utils.Math.MatrixUtils;
import Utils.Debug.PixelDebug;
import DiffRendering.SharedTypes;
import DiffRendering.DiffSceneIO;
import DiffRendering.DiffSceneQuery;
import StaticParams;
import Params;

[PreferRecompute]
float computeBoundaryTerm(float3 normalW, float3 direction)
{
    float dotND = dot(normalW, direction);
    return dotND * dotND;
}

[Differentiable]
[PreferRecompute]
// [ForwardDerivative(fwd_computeHarmonicWeight)]
float computeHarmonicWeight(
    no_diff IntersectionAD isect,
    no_diff float3 origin,
    no_diff float3 auxDirection,
    no_diff float auxSampleY,  // second rnd number
    no_diff float kappa,
    float3 direction  // ray dir (omega) differential w.r.t. this direction
)
{
    // find boundary Term B; no_diff



    // see WAS paper Algorithm 2, computation of weight_i

    return 1.f;
}


// Create a wrapper for reflect(). This isn't marked with [Differentiable].
// (For some reason, we're ignoring detach when differentiating things.)
[PreferRecompute]
float3 _reflect(float3 dir, float3 normal)
{
    return reflect(dir, normal);
}

// Compute the warped-area sampled intersection for a given input ray.
// This function has close match with Algorithm 2 in the paper
[Differentiable]
[PreferRecompute]
__generic<let N : int> bool traceAsymptoticWeightedMeanIntersection(
    SceneQueryAD sceneQuery,       // scene info, usage here sceneQuery.gradInfo.pixel & sceneQuery.traceRayInlineAD()
    no_diff float kappa,           // param of VonMisesFisher Distribution
    float3 origin,                 // base ray origin
    no_diff float3 baseDirection,  // base ray dir
    float3 direction[N],           // ray dir differential w.r.t. sth in N-dimension (e.g. N=3 to World and N=2 to Screen)
    out float3 warpedDirection[N], // output, warped-area direction
    inout SampleGenerator sg       // usage sampleNext[1 or 2]D(sg)
)
{
    // init storage of W and warpedDir, both List[N]


    // Initialize.
    [ForceUnroll]
    for (int j = 0; j < N; j++)
    {

    }

    // prepare random numbers for antithetic sample:
    // normally, each auxRay calling sampleVonMisesFisher() takes float2,
    // but with antithetic sampling, each 2 rays share 2 numbers, (and we negate 1 later)

    // Create a local frame based on `baseDirection`; use no_diff perp_stark


    // Loop over the number of auxiliary samples.
    [MaxIters(AUX_SAMPLE_COUNT)]
    for (uint i = 0; i < kAuxSampleCount; i++)
    {

        // whether to use antithetic sample
        if (true)
        {
            // auxRay_i and auxRay_(i+1) shares the same 2 rnd numbers

        }
        else
        {
            // sample() function should also be no_diff
        }

        // sample local direction from VMF; no_diff

        // transform, normalize, detach to get auxDir in world

        // flip those antithetic sample
        if (true)
        {
            // Every other sample, no_diff reflect `auxDirection` about `baseDirection`.

        }

        // Build a new RayAD with `auxDirection` and its IntersectionAD


        // create copy of auxDir

        // Trace the ray and intersect; mode is AttachToGeometry
        if (true)
        {
            // update copy with normalized (hit - origin)

        }

        [ForceUnroll]
        for (int j = 0; j < N; j++)
        {
            // for each i, weight_ij are the same for all j, since direction[j] is for autodiff, not computation

        }
    }

    [ForceUnroll]
    for (int j = 0; j < N; j++)
    {
        // Clamp the total weight from below to avoid NaNs.


        // Harmonic weighted mean.

    }
    // Leaving gradient alone, for each j,
    //   totalWeight[j] = sum(weight_i for each auxRay_i)
    //   warpedDirection[j] = sum(weight_i * warp_dir_i for each auxRay_i)

    // return successful or not: Weight > 0
    return false;
}

// Compute the warped-area reparameterization for (secondary) rays.
[Differentiable]
[PreferRecompute]
void computeWarpedRay(
    SceneQueryAD sceneQuery,
    no_diff float kappa,
    float3 origin,
    float3 baseDirection,
    float3 direction[3],
    out float3 warpedDirection[3],
    inout SampleGenerator sg
)
{
    // trace aux rays
    if (true)
    {
        // do safe-normalize and store in output warpedDireection
        [ForceUnroll]
        for (int j = 0; j < 3; j++) {}
    }
    else
    {
        // If the ray is missed, just return the original sample direction
        [ForceUnroll]
        for (int j = 0; j < 3; j++) {}

    }
}

// A wrapper around computeWarpedRay() that handles supporting operations
// return: determinant of Jacobian
[Differentiable]
[PreferRecompute]
float reparameterizeRay(SceneQueryAD sceneQuery, inout RayAD ray, inout SampleGenerator sg)
{
    // Build Forward-mode gradients w.r.t. 3D ray dir; type: DifferentialPair
    // all 3 primal are ray.dir
    // differential are unit x, y, z


    // Zero out any gradients from/to the scene for this Jacobian computation.

    // see static make() in Source\Falcor\DiffRendering\SceneGradientInfo.slang(41):
    //     Set (SceneQueryAD.Differential.gradInfo) dFlag = { GradientMode.None } to zero out gradients
    //     and make turn the enum GradientMode into SceneGradientFlag


    // Use the same (copy of) SampleGenerator for correlated samples.


    // create output diffpair


    // restore kappa from kLog10vMFConcentrationScreen

    // Compute warped directions and differentials by calling fwd_diff on computeWarpedPrimarySample.
    // Need diffPair for
    // -sceneQuery
    // -ray.origin, but differential value should be trivial
    // -ray.direction, but differential value should be trivial
    // -direction (it's dpDirections)
    // see infinitesimal<N>

    // compute warped
    // -ray dir; Can use any of diffWarpDir.p[j].
    // -differential w.r.t. x, y, z



    // Compute Jacobian (3x3, I + <diffX, diffY, diffZ>) determinant.


    // Update the ray by accumulating warpDir; return Jacobian determinant.

    return 1.f;
}

// Compute the warped-area reparameterization for (primary) screen samples.
[Differentiable]
[PreferRecompute]
void computeWarpedPrimarySample(
    SceneQueryAD sceneQuery,  // usage .loadCameraPosition() and .computeCameraRayDirection()
    no_diff float kappa,
    uint2 frameDim,  // e.g. 1920 x 1080
    float2 basePosS,  // screen-space position
    float2 posS[2],  // screen-space position differentials
    out float2 warpedPosS[2],
    inout SampleGenerator sg
)
{
    // priRay origin is camera

    // priRay dir is camera.pos to basePosS

    // ray dir differential: to posS[i]

    // trace aux rays
    if (true)
    {
        // Project the warped direction onto screen space by sceneQuery.computeCameraRayScreenPos()
        [ForceUnroll]
        for (int j = 0; j < 2; j++)
        {
            // do safe-normalize and store in output

        }
    }
    else
    {
        // If the ray is missed, just return the original sample.
        [ForceUnroll]
        for (int j = 0; j < 2; j++) {}
    }
}

// screen-space veresion of reparameterizeRay()
// A wrapper around computeWarpedPrimarySample() that handles supporting operations
// return: determinant of Jacobian
[Differentiable]
[PreferRecompute]
float reparameterizePrimarySample(SceneQueryAD sceneQuery, uint2 frameDim, SampleGenerator sg, inout float2 posS, )
{
    // Forward-mode gradients w.r.t. screen-space position.


    // Zero out any gradients from/to the scene for this Jacobian computation.

    // see static make() in Source\Falcor\DiffRendering\SceneGradientInfo.slang(41):
    //     Set (SceneQueryAD.Differential.gradInfo) dFlag = { GradientMode.None } to zero out gradients
    //     and make turn the enum GradientMode into SceneGradientFlag


    // Use the same (copy of) SampleGenerator for correlated samples.


    // create output diffpair


    // restore kappa from kLog10vMFConcentrationScreen


    // Compute warped directions and differentials by calling fwd_diff on computeWarpedPrimarySample.
    // Need diffPair for
    // -sceneQuery
    // -basePosS, but differential value should be trivial
    // -posS (it's dpPosS)

    // compute warped
    // -screen pos; Can use either dpWarpedPosS.p[0] or dpWarpedPosS.p[1].
    // -differential w.r.t. x
    // -differential w.r.t. y
    // see infinitesimal<N>


    // Compute Jacobian (2x2, I + <diffX, diffY>) determinant.


    // update posS with warped pos; return Jacobian determinant.

    return 1.f;
}
