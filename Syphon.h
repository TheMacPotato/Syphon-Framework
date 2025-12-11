/*
    Syphon.h
    Syphon

    Copyright 2010-2011 bangnoise (Tom Butterworth) & vade (Anton Marini).
    All rights reserved.

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
// Syphon Framework - Optimized for Apple Silicon
//
// For new projects, use the Metal API for best performance on Apple Silicon:
// - SyphonMetalServer and SyphonMetalClient provide native Metal integration
// - Optimized for unified memory architecture on Apple Silicon
// - Leverages tile-based deferred rendering for maximum efficiency
//
// OpenGL API is maintained for compatibility with existing applications,
// but is deprecated by Apple and not recommended for new development.
//

// Server Directory (for discovering available Syphon servers)
#import <Syphon/SyphonServerDirectory.h>

// Metal API (Recommended for new projects and Apple Silicon)
#import <Syphon/SyphonMetalServer.h>
#import <Syphon/SyphonMetalClient.h>

// OpenGL API (Maintained for compatibility, deprecated by Apple)
#import <Syphon/SyphonOpenGLServer.h>
#import <Syphon/SyphonOpenGLClient.h>
#import <Syphon/SyphonOpenGLImage.h>

/*
 Deprecated headers (for backward compatibility)
 */
#import <Syphon/SyphonServer.h>
#import <Syphon/SyphonClient.h>
#import <Syphon/SyphonImage.h>
