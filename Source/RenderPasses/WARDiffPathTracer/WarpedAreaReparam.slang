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
    float B = no_diff computeBoundaryTerm(isect.normalW, auxDirection);

    // Computation of weight_i, see WAS paper Algorithm 2,
    /// Don't know why sampleVonMisesFisher() maps uv.v to 1-uv.v, but need consistency
    float sy = 1.f - auxSampleY;
    /*
        // full derivation
        /// step 0: compute dot(w, w') = cos(theta) locally = mu^T * x in Wikipedia notation
        float cosTheta = 1.f + log(exp(-2.f * kappa) * (1.f - sy) + sy) / kappa;
        /// step 1: compute exp(kappa * cos(theta)), used in 2 places below
        float expTerm = exp(kappa * cosTheta);
        /// step 2: compute pdf(w_i)
        /// see Definition, https://en.wikipedia.org/w/index.php?title=Von_Mises%E2%80%93Fisher_distribution
        float normC = kappa * M_1_2PI / (exp(kappa) - exp(-kappa));
    float pdfVMF = normC * expTerm;
    /// step 3: compute denominator exp(kappa - kappa * cos(theta)) - 1 + B
    float denom = exp(kappa) / expTerm - 1.f + B;
 */
    // concise version
    float expTerm = exp(kappa +
        log(exp(-2.f * kappa) * (1.f - sy) + sy)
    );
    float pdfVMF = kappa * M_1_2PI / (exp(kappa) - exp(-kappa)) * expTerm;
    float denom = exp(kappa) / expTerm - 1.f + B;

    return 1 / denom / pdfVMF;
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
    inout SampleGenerator sg       // usage no_diff sampleNext[1 or 2]D(sg)
)
{
    // init storage of W and W * totalWDir, both List[N]
    float totalW[N];
    float3 totalWDir[N];

    // Initialize.
    [ForceUnroll]
    for (int j = 0; j < N; j++)
    {
        totalW[j] = 0.f;
        totalWDir[j] = float3(0.f);
    }

    // prepare random numbers for antithetic sample:
    // normally, each auxRay calling sampleVonMisesFisher() takes float2,
    // but with antithetic sampling, each 2 rays share 2 numbers, (and we negate 1 later)
    float rndNums[AUX_SAMPLE_COUNT];
    for (uint i = 0; i < kAuxSampleCount; i++) {
        rndNums[i] = no_diff sampleNext1D(sg);
    }

    // Create a local ShadingFrame based on `baseDirection`; use no_diff perp_stark
    float3 t = no_diff perp_stark(baseDirection);
    ShadingFrame localDirFrame = ShadingFrame(baseDirection, float4(t, 1.f));

    // Loop over the number of auxiliary samples.
    [MaxIters(AUX_SAMPLE_COUNT)]
    for (uint i = 0; i < kAuxSampleCount; i++)
    {
        float2 rndXY;
        // whether to use antithetic sample
        if (kUseAntitheticSampling)
        {
            // auxRay_i and auxRay_(i+1) shares the same 2 rnd numbers
            // i.e. want i and i+1 to use rndNums[i] and rndNums[i+1]
            uint antitheticIdx = i / 2;
            rndXY = float2(rndNums[antitheticIdx * 2], rndNums[antitheticIdx * 2 + 1]);
        }
        else
        {
            // sample() function should also be no_diff
            rndXY = no_diff sampleNext2D(sg);
        }

        // sample local direction from VMF; no_diff
        float3 sampledDir = no_diff sampleVonMisesFisher(rndXY, kappa);

        // transform, normalize, detach to get auxDir in world
        float3 auxDir = detach(normalizeSafe(localDirFrame.fromLocal(sampledDir)));

        // flip those antithetic sample
        if (kUseAntitheticSampling && i % 2 == 1)
        {
            // Every other sample, no_diff reflect `auxDirection` about `baseDirection`.
            // use -auxDir since auxDir and baseDir has same direction
            auxDir = no_diff _reflect(-auxDir, baseDirection);
        }

        // Build a new RayAD with `auxDirection` and its IntersectionAD
        RayAD auxRay = RayAD(origin, auxDir, sceneQuery.gradInfo.pixel);
        IntersectionAD auxIsect = IntersectionAD();

        // create copy of auxDir
        float3 aDir = auxDir;
        // Trace the aux ray and intersect; mode is AttachToGeometry
        if (sceneQuery.traceRayInlineAD(auxRay, auxIsect, SceneQueryAD.DiffIntersectionMode.AttachToGeometry))
        {
            // update copy with normalized (hit - origin)
            aDir = normalizeSafe(auxIsect.posW - origin);
        }

        [ForceUnroll]
        for (int j = 0; j < N; j++)
        {
            // for each i, weight_ij are the same for all j, since direction[j] is for autodiff, not computation
            float w_i = computeHarmonicWeight(auxIsect, origin, auxDir, rndXY.y, kappa, direction[j]);
            totalW[j] += w_i;
            totalWDir[j] += aDir * w_i;  // should use normalized aDir here!
        }
    }

    [ForceUnroll]
    for (int j = 0; j < N; j++)
    {
        // Clamp the total weight from below to avoid NaNs.
        totalW[j] = max(totalW[j], 1e-9f);
        // Harmonic weighted mean.
        warpedDirection[j] = totalWDir[j] / totalW[j];
    }
    // Leaving gradient alone, for each j,
    //   totalW[j] = sum(weight_i for each auxRay_i)
    //   totalWDir[j] = sum(weight_i * warp_dir_i for each auxRay_i)

    // return successful or not: Weight > 0
    return totalW[0] > 0.f;
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
    float3 weightedDir[3];
    // trace aux rays
    if (traceAsymptoticWeightedMeanIntersection(sceneQuery, kappa, origin, baseDirection, direction, weightedDir, sg))
    {
        // do safe-normalize and store in output warpedDirection
        [ForceUnroll]
        for (int j = 0; j < 3; j++) {
            warpedDirection[j] = normalizeSafe(weightedDir[j]);
        }
    }
    else
    {
        // If the ray is missed, just return the original sample direction
        [ForceUnroll]
        for (int j = 0; j < 3; j++) {
            warpedDirection[j] = direction[j];
        }
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
    DifferentialPair<float3[3]> dpScene = DifferentialPair<float3[3]>(
        { ray.direction, ray.direction, ray.direction },
        { float3(1.f, 0.f, 0.f), float3(0.f, 1.f, 0.f), float3(0.f, 0.f, 1.f) }
    );

    // Zero out any gradients from/to the scene for this Jacobian computation.
    /// That is, init an empty SceneQueryAD.Differential; it will later be paired with sceneQuery
    SceneQueryAD.Differential dScene= {};
    // see static make() in Source\Falcor\DiffRendering\SceneGradientInfo.slang(41):
    //     Set (SceneQueryAD.Differential.gradInfo) dFlag = { GradientMode.None } to zero out gradients
    //     and make turn the enum GradientMode into SceneGradientFlag
    // but why can {sth} turn sth into a differential?
    dScene.gradInfo = { SceneGradientFlag.make(GradientMode.None) };

    // Use the same (copy of) SampleGenerator for correlated samples.
    SampleGenerator sgCopy = sg;

    // create output diffpair
    DifferentialPair<float3[3]> dpWarpedDirections;

    // restore kappa from kLog10vMFConcentrationScreen
    float kappa = pow(10.f, kLog10vMFConcentrationScreen);

    // Compute warped directions and differentials by calling fwd_diff on computeWarpedRay().
    // Need diffPair for
    // -sceneQuery
    // -ray.origin, but differential value should be trivial
    // -ray.direction, but differential value should be trivial
    // -direction (it's dpScene)
    fwd_diff(computeWarpedRay )(
        diffPair(sceneQuery, dScene),
        kappa,
        diffPair(ray.origin, float3(0.f)),
        diffPair(ray.direction, float3(0.f)),
        dpScene,
        dpWarpedDirections,
        sgCopy
    );


    // compute warped
    // -ray dir; Can use any of diffWarpDir.p[j].
    // -differential w.r.t. x, y, z
    // see infinitesimal<N>
    float3 warpedDir = infinitesimal<3>(dpWarpedDirections.p[0]);
    float3 diffX = infinitesimal<3>(dpWarpedDirections.d[0]);
    float3 diffY = infinitesimal<3>(dpWarpedDirections.d[1]);
    float3 diffZ = infinitesimal<3>(dpWarpedDirections.d[2]);

    // Compute Jacobian (3x3, I + <diffX, diffY, diffZ>) determinant.
    float3x3 jacobian = float3x3(1.f) + float3x3(diffX, diffY, diffZ);
    float detJ = determinant(jacobian);

    // Update the ray by accumulating warpDir; return Jacobian determinant.
    ray.direction += warpedDir;
    return detJ;
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
    float3 rayOrigin = sceneQuery.loadCameraPosition();
    // priRay dir is camera.pos to basePosS
    float3 rayDir = sceneQuery.computeCameraRayDirection(basePosS, frameDim);
    // ray dir differential: to posS[i]
    float3 dRayDir[2] = {
        sceneQuery.computeCameraRayDirection(posS[0], frameDim),
        sceneQuery.computeCameraRayDirection(posS[1], frameDim)
    };

    // trace aux rays
    float3 weightedDir[2];
    if (traceAsymptoticWeightedMeanIntersection(sceneQuery, kappa, rayOrigin, rayDir, dRayDir, weightedDir, sg))
    {
        // Project the warped direction onto screen space by sceneQuery.computeCameraRayScreenPos()
        [ForceUnroll]
        for (int j = 0; j < 2; j++)
        {
            // do safe-normalize and store in a temp output (in World Space)
            float3 warpedDir = normalizeSafe(weightedDir[j]);
            // World to Screen by .computeCameraRayScreenPos()
            warpedPosS[j] = sceneQuery.computeCameraRayScreenPos(warpedDir, frameDim);
        }
    }
    else
    {
        // If the ray is missed, just return the original sample.
        [ForceUnroll]
        for (int j = 0; j < 2; j++) {
            warpedPosS[j] = posS[j];
        }
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
    DifferentialPair<float2[2]> dpScreen = DifferentialPair<float2[2]>(
        { posS, posS },
        { float2(1.f, 0.f), float2(0.f, 1.f) }
    );

    // Zero out any gradients from/to the scene for this Jacobian computation.
    SceneQueryAD.Differential dScreen = {};
    // see static make() in Source\Falcor\DiffRendering\SceneGradientInfo.slang(41):
    //     Set (SceneQueryAD.Differential.gradInfo) dFlag = { GradientMode.None } to zero out gradients
    //     and make turn the enum GradientMode into SceneGradientFlag
    dScreen.gradInfo = { SceneGradientFlag.make(GradientMode.None) };

    // Use the same (copy of) SampleGenerator for correlated samples.
    SampleGenerator sgCopy = sg;

    // create output diffpair
    DifferentialPair<float2[2]> dpWarpedScreen;

    // restore kappa from kLog10vMFConcentrationScreen
    float kappa = pow(10.f, kLog10vMFConcentrationScreen);

    // Compute warped directions and differentials by calling fwd_diff on computeWarpedPrimarySample.
    // Need diffPair for
    // -sceneQuery
    // -basePosS, but differential value should be trivial
    // -posS (it's dpPosS)
    fwd_diff(computeWarpedPrimarySample )(
        diffPair(sceneQuery, dScreen),
        kappa,
        frameDim,
        diffPair(posS, float2(0.f)),
        dpScreen,
        dpWarpedScreen,
        sgCopy
    );

    // compute warped
    // -screen pos; Can use either dpWarpedPosS.p[0] or dpWarpedPosS.p[1].
    // -differential w.r.t. x
    // -differential w.r.t. y
    // see infinitesimal<N>
    float2 warpedScreen = infinitesimal<2>(dpWarpedScreen.p[0]);
    float2 diffX = infinitesimal<2>(dpWarpedScreen.d[0]);
    float2 diffY = infinitesimal<2>(dpWarpedScreen.d[1]);

    // Compute Jacobian (2x2, I + <diffX, diffY>) determinant.
    float2x2 jacobian = float2x2(1.f) + float2x2(diffX, diffY);
    float detJ = determinant(jacobian);

    // update posS with warped pos; return Jacobian determinant.
    posS += warpedScreen;
    return detJ;
}
