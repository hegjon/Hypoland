#pragma once

// Runtime support for GPUs that can only do OpenGL ES 2.0.
//
// Intel gen4 / gen4.5 / gen5 (GMA X3100 through GM45 to Ironlake) top out at
// OpenGL ES 2.0 under Mesa's crocus driver, so a GLES3-only Hyprland cannot
// start on e.g. a ThinkPad X200. Rather than needing a separately compiled
// binary, the renderer detects the context version at startup and takes a
// GLES2-compatible path where the two differ; see
// CHyprOpenGLImpl::initEGL() and CHyprOpenGLImpl::m_legacyGLES.
//
// The build always compiles against the GLES3 headers: libglvnd's libGLESv2
// exports the GLES3 entry points regardless of driver, and dispatches them per
// context, so one binary can carry both paths and simply not call the GLES3
// ones when the context is 2.0.

#include <GLES3/gl32.h>

namespace Hyprgraphics::Egl {
    struct SPixelFormat;
}

namespace NGLES2Compat {
    // The GL format/type triple to hand glTexImage2D for a pixel format.
    struct SGLFormat {
        int  internalFormat = 0;
        int  format         = 0;
        int  type           = 0;
        bool needsSwizzle   = false; // caller should apply the format's swizzle
        bool usable         = true;  // false: not expressible on this context
    };

    // On GLES2 there is no texture swizzle, so a BGRA-ordered 8888 format is
    // uploaded as GL_BGRA_EXT (EXT_texture_format_BGRA8888, which Mesa exposes
    // on crocus) rather than as RGBA plus a sampling swizzle. Sized internal
    // formats and half-float render targets do not exist there either.
    SGLFormat glFormatFor(const Hyprgraphics::Egl::SPixelFormat* fmt, bool legacyGLES);

    // True when the current context reports OpenGL ES 2.x. Reads
    // glGetString(GL_VERSION) rather than trusting the version that was
    // requested: asking EGL for a GLES2 context on modern hardware still
    // returns a 3.2 context, so only the reported version is authoritative.
    bool currentContextIsGLES2();

    // Verifies GL_OES_vertex_array_object on the current context. Core in
    // GLES3, an extension in GLES2; Mesa exposes it on every gallium driver
    // including crocus, and the core entry points dispatch to it. Returns false
    // if the driver lacks it, in which case the renderer cannot run.
    bool checkVertexArrayObjectExt();
}
