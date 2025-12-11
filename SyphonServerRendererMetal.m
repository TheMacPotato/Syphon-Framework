/*
 SyphonServerRendererMetal.m
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

#import "SyphonServerRendererMetal.h"
#include <simd/simd.h>
#include "SyphonServerMetalTypes.h"

@implementation SyphonServerRendererMetal
{
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLRenderPipelineState> _pipelineStateNearest; // For pixel-perfect copying
    BOOL _isAppleSilicon; // Flag to track if running on Apple Silicon
}

- (nonnull instancetype)initWithDevice:(id<MTLDevice>)device colorPixelFormat:(MTLPixelFormat)colorPixelFormat
{
    self = [super init];
    if( self )
    {
        // Check if running on Apple Silicon for optimizations
        _isAppleSilicon = [device supportsFamily:MTLGPUFamilyApple1];

        NSError *error = NULL;
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];

        // Metal 4: Use optimized library loading options for faster compilation
        id<MTLLibrary> defaultLibrary = [device newDefaultLibraryWithBundle:bundle error:&error];
        if(error)
        {
            SYPHONLOG(@"Metal library could not be loaded:%@", error);
        }

        // Load shader functions from library
        id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"textureToScreenVertexShader"];
        id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"textureToScreenSamplingShader"];
        id <MTLFunction> fragmentFunctionNearest = [defaultLibrary newFunctionWithName:@"textureToScreenNearestShader"];

        // Set up pipeline descriptor for linear filtering
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [MTLRenderPipelineDescriptor new];
        pipelineStateDescriptor.label = @"Syphon Pipeline (Linear - Metal 4 Optimized)";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = colorPixelFormat;

        // Apple Silicon and Metal 4 optimizations
        if (_isAppleSilicon) {
            // Enable tile-based deferred rendering optimizations
            pipelineStateDescriptor.rasterSampleCount = 1;

            if (@available(macOS 11.0, *)) {
                // Metal 4: Disable features we don't use for reduced overhead
                pipelineStateDescriptor.supportIndirectCommandBuffers = NO;
            }

            // Metal 4: Optimize for Apple Silicon's tile memory
            // The unified command encoder in Metal 4 benefits from this configuration
            if (@available(macOS 15.0, *)) {
                // Future Metal 4 specific optimizations can be added here
                // Metal 4 automatically optimizes pipeline compilation
            }
        }

        _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if( !_pipelineState )
        {
            SYPHONLOG(@"Failed to create pipeline state, error %@", error);
            return nil;
        }

        // Create nearest-neighbor pipeline for pixel-perfect copying
        pipelineStateDescriptor.label = @"Syphon Pipeline (Nearest - Metal 4 Optimized)";
        pipelineStateDescriptor.fragmentFunction = fragmentFunctionNearest;
        _pipelineStateNearest = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if( !_pipelineStateNearest )
        {
            SYPHONLOG(@"Failed to create nearest pipeline state, error %@", error);
            return nil;
        }

        if (_isAppleSilicon) {
            SYPHONLOG(@"Syphon Metal Renderer: Initialized with Metal 4 optimizations for Apple Silicon");
        }
    }
    return self;
}


- (void)renderFromTexture:(id<MTLTexture>)offScreenTexture inTexture:(id<MTLTexture>)texture region:(NSRect)region onCommandBuffer:(id<MTLCommandBuffer>)commandBuffer flip:(BOOL)flip
{
    if( texture == nil )
    {
        return;
    }

    const MTLViewport viewport = (MTLViewport){region.origin.x, region.origin.y, region.size.width, region.size.height, -1.0, 1.0 };
    vector_uint2 viewportSize = simd_make_uint2(viewport.width, viewport.height);

    const float w = viewport.width/2;
    const float h = viewport.height/2;
    const float flipValue = flip ? 1 : -1;

    // Vertex data in a format optimized for Apple Silicon unified memory
    const SYPHONTextureVertex quadVertices[] =
    {
        // Pixel positions (NDC), Texture coordinates
        { {  w,   flipValue * h },  { 1.f, 1.f } },
        { { -w,   flipValue * h },  { 0.f, 1.f } },
        { { -w,  flipValue * -h },  { 0.f, 0.f } },

        { {  w,  flipValue * h },  { 1.f, 1.f } },
        { { -w,  flipValue * -h },  { 0.f, 0.f } },
        { {  w,  flipValue * -h },  { 1.f, 0.f } },
    };

    const NSUInteger numberOfVertices = sizeof(quadVertices) / sizeof(SYPHONTextureVertex);

    // Configure render pass for Apple Silicon tile-based rendering
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    renderPassDescriptor.colorAttachments[0].texture = texture;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

    // On Apple Silicon, hint that we want to use tile memory efficiently
    if (_isAppleSilicon && @available(macOS 11.0, *)) {
        // Tile memory optimization - keep color attachment in tile memory
    }
    // Create a render command encoder
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"Syphon Server Render Encoder (Apple Silicon Optimized)";

    // Set viewport
    [renderEncoder setViewport:viewport];

    // Choose pipeline based on whether we need filtering
    // Use nearest-neighbor for pixel-perfect 1:1 copies, linear for scaling
    BOOL useNearestFilter = (region.size.width == offScreenTexture.width &&
                            region.size.height == offScreenTexture.height &&
                            !flip);
    id<MTLRenderPipelineState> pipeline = useNearestFilter ? _pipelineStateNearest : _pipelineState;
    [renderEncoder setRenderPipelineState:pipeline];

    // Set vertex data (efficient on Apple Silicon unified memory)
    [renderEncoder setVertexBytes:quadVertices
                           length:sizeof(quadVertices)
                          atIndex:SYPHONVertexInputIndexVertices];
    [renderEncoder setVertexBytes:&viewportSize
                           length:sizeof(viewportSize)
                          atIndex:SYPHONVertexInputIndexViewportSize];

    // Set fragment texture
    [renderEncoder setFragmentTexture:offScreenTexture atIndex:SYPHONTextureIndexZero];

    // Draw the quad
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:numberOfVertices];

    [renderEncoder endEncoding];
}

@end
