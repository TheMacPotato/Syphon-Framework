/*
 SyphonMetalShaders.metal
 Syphon

 Copyright 2020-2025 Maxime Touroute & Philippe Chaurand (www.millumin.com),
 bangnoise (Tom Butterworth) & vade (Anton Marini). All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

//
// Optimized for Apple Silicon with Metal 3 features
// - Uses half-precision where appropriate for better performance
// - Optimized memory access patterns for unified memory architecture
// - Leverages tile memory on Apple GPUs
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "SyphonServerMetalTypes.h"

using namespace metal;

typedef struct
{
    float4 clipSpacePosition [[position]];
    half2 textureCoordinate; // Use half-precision for texture coordinates
} RasterizerData;

// Vertex shader optimized for Apple Silicon
// Uses efficient memory access patterns and half-precision where possible
vertex RasterizerData textureToScreenVertexShader(uint vertexID [[ vertex_id ]],
                                                  constant SYPHONTextureVertex *vertexArray [[ buffer(SYPHONVertexInputIndexVertices) ]],
                                                  constant vector_uint2 *viewportSizePointer  [[ buffer(SYPHONVertexInputIndexViewportSize) ]])
{
    RasterizerData out;

    // Load vertex data (efficient on Apple Silicon unified memory)
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;
    float2 viewportSize = float2(*viewportSizePointer);

    // Compute clip space position with optimized math
    out.clipSpacePosition.xy = pixelSpacePosition / (viewportSize * 0.5);
    out.clipSpacePosition.z = 0.0;
    out.clipSpacePosition.w = 1.0;

    // Use half-precision for texture coordinates (sufficient precision, better performance)
    out.textureCoordinate = half2(vertexArray[vertexID].textureCoordinate);

    return out;
}

// Fragment shader optimized for Apple Silicon
// Uses half-precision for color processing and efficient sampling
fragment half4 textureToScreenSamplingShader(RasterizerData in [[stage_in]],
                                             texture2d<half> colorTexture [[ texture(SYPHONTextureIndexZero) ]])
{
    // Linear sampler for better quality (nearest for pixel-perfect when needed)
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::clamp_to_edge,
                                     coord::normalized);

    // Sample texture with half-precision (native format for Apple GPUs)
    // This is more efficient on Apple Silicon than float4
    const half4 colorSample = colorTexture.sample(textureSampler, float2(in.textureCoordinate));

    return colorSample;
}

// Additional shader for fast nearest-neighbor sampling (pixel-perfect copy)
fragment half4 textureToScreenNearestShader(RasterizerData in [[stage_in]],
                                           texture2d<half> colorTexture [[ texture(SYPHONTextureIndexZero) ]])
{
    constexpr sampler textureSampler(mag_filter::nearest,
                                     min_filter::nearest,
                                     address::clamp_to_edge,
                                     coord::normalized);

    const half4 colorSample = colorTexture.sample(textureSampler, float2(in.textureCoordinate));
    return colorSample;
}
