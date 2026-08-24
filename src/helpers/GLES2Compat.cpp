#include "GLES2Compat.hpp"

#include <GLES2/gl2ext.h>
#include <hyprgraphics/egl/Egl.hpp>
#include <drm_fourcc.h>

#include <string_view>

#include "../debug/log/Logger.hpp"

namespace NGLES2Compat {
    SGLFormat glFormatFor(const Hyprgraphics::Egl::SPixelFormat* fmt, bool legacyGLES) {
        using namespace Hyprgraphics::Egl;

        SGLFormat res{
            .internalFormat = fmt->glInternalFormat ? fmt->glInternalFormat : fmt->glFormat,
            .format         = fmt->glFormat,
            .type           = fmt->glType,
            .needsSwizzle   = fmt->swizzle.has_value(),
            .usable         = true,
        };

        if (!legacyGLES)
            return res;

        // Half-float colour buffers cannot be expressed with a GLES2
        // glTexImage2D call; callers must not pick such a format.
        if (fmt->glType == GL_HALF_FLOAT_OES || fmt->drmFormat == DRM_FORMAT_ABGR16161616F || fmt->drmFormat == DRM_FORMAT_XBGR16161616F) {
            res.usable = false;
            return res;
        }

        // GLES2 has no sized internal formats: internalformat must equal format.
        res.internalFormat = fmt->glFormat;

        // No swizzle in GLES2. A BGRA-ordered 8888 format is uploaded as BGRA
        // directly instead, which is both correct and cheaper than sampling.
        //
        // Both BGRA (ARGB8888) and BGR1 (XRGB8888) qualify: the colour channels
        // are in the same order, and BGR1 only differs by forcing alpha to one,
        // which the renderer already handles by marking the texture TEXTURE_RGBX
        // and using the non-RGBA shader variant. Missing BGR1 here left every
        // opaque window sampling its channels reversed.
        const bool BGRA_ORDERED = fmt->swizzle.has_value() && (fmt->swizzle.value() == SWIZZLE_BGRA || fmt->swizzle.value() == SWIZZLE_BGR1);

        if (BGRA_ORDERED && fmt->glFormat == GL_RGBA && fmt->glType == GL_UNSIGNED_BYTE) {
            res.internalFormat = GL_BGRA_EXT;
            res.format         = GL_BGRA_EXT;
            res.needsSwizzle   = false;
        } else
            res.needsSwizzle = false; // unrepresentable; colours may be off, but do not error out

        return res;
    }

    bool currentContextIsGLES2() {
        const auto* VERSION = reinterpret_cast<const char*>(glGetString(GL_VERSION));
        if (!VERSION) {
            Log::logger->log(Log::ERR, "GLES: could not query GL_VERSION, assuming GLES3");
            return false;
        }

        // Mesa reports e.g. "OpenGL ES 2.0 Mesa 26.2.1" or "OpenGL ES 3.2 Mesa 26.2.1".
        const std::string_view SV{VERSION};
        const auto             POS = SV.find("OpenGL ES ");
        if (POS == std::string_view::npos) {
            Log::logger->log(Log::ERR, "GLES: unrecognised GL_VERSION \"{}\", assuming GLES3", VERSION);
            return false;
        }

        return SV.substr(POS + 10).starts_with("2.");
    }

    bool checkVertexArrayObjectExt() {
        const auto* EXTENSIONS = reinterpret_cast<const char*>(glGetString(GL_EXTENSIONS));
        if (!EXTENSIONS) {
            Log::logger->log(Log::ERR, "GLES2: could not query GL_EXTENSIONS");
            return false;
        }

        if (!std::string_view{EXTENSIONS}.contains("GL_OES_vertex_array_object")) {
            Log::logger->log(Log::ERR, "GLES2: driver does not advertise GL_OES_vertex_array_object, which the renderer requires");
            return false;
        }

        Log::logger->log(Log::DEBUG, "GLES2: GL_OES_vertex_array_object present");
        return true;
    }
}
