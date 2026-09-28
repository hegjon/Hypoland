#include "GLFramebuffer.hpp"
#include "../../helpers/GLES2Compat.hpp"
#include "../OpenGL.hpp"
#include "../Renderer.hpp"
#include "macros.hpp"
#include "../Framebuffer.hpp"
#include <hyprgraphics/egl/Egl.hpp>
#include <algorithm>
#include <limits>

using namespace Hyprgraphics::Egl;
using namespace Render::GL;

CGLFramebuffer::CGLFramebuffer() : IFramebuffer(), m_tempBuf(true) {}
CGLFramebuffer::CGLFramebuffer(const std::string& name) : IFramebuffer(name), m_tempBuf(true) {}

bool CGLFramebuffer::internalAlloc(int w, int h, uint32_t drmFormat) {
    g_pHyprOpenGL->makeEGLCurrent();
    m_tempBuf = false;

    if (!m_tex) {
        m_tex = g_pHyprRenderer->createTexture();
        m_tex->allocate({w, h}, drmFormat);
        m_tex->bind();
        m_tex->setTexParameter(GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        m_tex->setTexParameter(GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        m_tex->setTexParameter(GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        m_tex->setTexParameter(GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    }

    if (!m_fbAllocated) {
        glGenFramebuffers(1, &m_fb);
        m_fbAllocated = true;
    }

    const auto format = getPixelFormatFromDRM(drmFormat);
    const auto GLFMT  = NGLES2Compat::glFormatFor(format);
    if (!GLFMT.usable)
        Log::logger->log(Log::ERR, "Framebuffer \"{}\": drm format 0x{:x} cannot be used on this GL context", m_name, drmFormat);
    m_tex->bind();
    GLCALL(glTexImage2D(GL_TEXTURE_2D, 0, GLFMT.internalFormat, w, h, 0, GLFMT.format, GLFMT.type, nullptr));
    g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, m_fb);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_tex->m_texID, 0);

    // GLES2 has no packed depth/stencil texture, the stencil is a renderbuffer of this framebuffer.
    // m_stencilTex only says that a stencil was asked for.
    if (m_stencilTex) {
        if (!m_stencilRB)
            glGenRenderbuffers(1, &m_stencilRB);

        glBindRenderbuffer(GL_RENDERBUFFER, m_stencilRB);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, w, h);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_stencilRB);
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
    }

    auto status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE)
        Log::logger->log(Log::ERR, "Framebuffer \"{}\" incomplete: status 0x{:x}, drm format 0x{:x}, gl iformat 0x{:x} format 0x{:x} type 0x{:x}, stencil {}", m_name, status,
                         drmFormat, GLFMT.internalFormat, GLFMT.format, GLFMT.type, m_stencilRB ? "yes" : "no");
    RASSERT((status == GL_FRAMEBUFFER_COMPLETE), "Framebuffer incomplete, couldn't create! (FB status: {}, GL Error: 0x{:x})", status, sc<int>(glGetError()));

    Log::logger->log(Log::DEBUG, "Framebuffer \"{}\" created, status {}", m_name, status);

    glBindTexture(GL_TEXTURE_2D, 0);
    g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, 0);

    // this can run mid frame, restore the draw fb the renderer had bound
    if (g_pHyprRenderer && g_pHyprRenderer->m_renderData.currentFB)
        g_pHyprRenderer->m_renderData.currentFB->bind();
    else
        g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, 0);

    return true;
}

void CGLFramebuffer::addStencil(SP<ITexture> tex) {
    if (m_stencilTex == tex)
        return;

    RASSERT(!m_fbAllocated, "Should add stencil tex prior to FB allocation")
    m_stencilTex = tex;
}

void CGLFramebuffer::bind() {
    // temp buffer, created without CGLFramebuffer::internalAlloc.
    // that means its a temp buffer that we have to raw bind and not change the viewport.
    // the temp buffer code binds this fb to add attachments themself
    if (m_tempBuf) {
        if (g_pHyprOpenGL)
            g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, m_fb);
        else
            glBindFramebuffer(GL_FRAMEBUFFER, m_fb);
        return;
    }

    if (g_pHyprOpenGL) {
        g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, m_fb);
        g_pHyprOpenGL->setViewport(0, 0, m_size.x, m_size.y);
    } else {
        glBindFramebuffer(GL_FRAMEBUFFER, m_fb);
        glViewport(0, 0, m_size.x, m_size.y);
    }
}

void CGLFramebuffer::unbind() {
    if (g_pHyprOpenGL)
        g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, 0);
    else
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

void CGLFramebuffer::release() {
    if (m_fbAllocated) {
        if (g_pHyprOpenGL)
            g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, m_fb);
        else
            glBindFramebuffer(GL_FRAMEBUFFER, m_fb);

        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0);

        if (m_stencilRB) {
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, 0);
            glDeleteRenderbuffers(1, &m_stencilRB);
            m_stencilRB = 0;
        }

        glDeleteFramebuffers(1, &m_fb);
        if (g_pHyprOpenGL)
            g_pHyprOpenGL->onFramebufferDeleted(m_fb);

        // releasing can happen mid frame from a temp fb, rebind the fb the renderer
        // had previously bound, otherwise draws continue into fb 0 and raise GL_INVALID_FRAMEBUFFER_OPERATION
        if (g_pHyprRenderer && g_pHyprRenderer->m_renderData.currentFB && g_pHyprRenderer->m_renderData.currentFB.get() != this)
            g_pHyprRenderer->m_renderData.currentFB->bind();

        m_fbAllocated = false;
        m_fb          = 0;
    }

    if (m_tex)
        m_tex.reset();

    m_size = Vector2D();
}

bool CGLFramebuffer::readPixels(CHLBufferReference buffer, uint32_t offsetX, uint32_t offsetY, uint32_t width, uint32_t height) {
    auto shm = buffer->shm();
    if (!shm.success) {
        LOGM(Log::ERR, "Can't copy: buffer is not shm");
        return false;
    }

    auto [pixelData, fmt, bufLen] = buffer->beginDataPtr(0); // no need for end, cuz it's shm
    if (!pixelData) {
        LOGM(Log::ERR, "Can't copy: failed to get shm data pointer");
        return false;
    }

    const auto PFORMAT = getPixelFormatFromDRM(shm.format);
    if (!PFORMAT) {
        LOGM(Log::ERR, "Can't copy: failed to find a pixel format");
        return false;
    }

    const auto fbWidth    = sc<uint32_t>(m_size.x);
    const auto fbHeight   = sc<uint32_t>(m_size.y);
    const auto readWidth  = width > 0 ? width : fbWidth;
    const auto readHeight = height > 0 ? height : fbHeight;

    if (readWidth == 0 || readHeight == 0 || shm.stride <= 0) {
        LOGM(Log::ERR, "Can't copy: invalid shm read dimensions");
        return false;
    }

    if (offsetX > fbWidth || offsetY > fbHeight || readWidth > fbWidth - offsetX || readHeight > fbHeight - offsetY) {
        LOGM(Log::ERR, "Can't copy: read rect exceeds framebuffer");
        return false;
    }

    const auto shmWidth  = sc<uint32_t>(shm.size.x);
    const auto shmHeight = sc<uint32_t>(shm.size.y);
    if (offsetX > shmWidth || offsetY > shmHeight || readWidth > shmWidth - offsetX || readHeight > shmHeight - offsetY) {
        LOGM(Log::ERR, "Can't copy: read rect exceeds shm buffer");
        return false;
    }

    const auto strideBytes = sc<size_t>(shm.stride);
    const auto rowOffset   = sc<size_t>(minStride(PFORMAT, offsetX));
    const auto rowBytes    = sc<size_t>(minStride(PFORMAT, readWidth));

    if (rowBytes == 0) {
        LOGM(Log::ERR, "Can't copy: invalid shm row size");
        return false;
    }

    if (rowOffset > std::numeric_limits<size_t>::max() - rowBytes || rowOffset + rowBytes > strideBytes) {
        LOGM(Log::ERR, "Can't copy: shm stride is too small");
        return false;
    }

    const auto lastRow = sc<size_t>(offsetY) + sc<size_t>(readHeight) - 1;
    if (strideBytes > 0 && lastRow > std::numeric_limits<size_t>::max() / strideBytes) {
        LOGM(Log::ERR, "Can't copy: shm row offset overflows");
        return false;
    }

    const auto lastRowStart = lastRow * strideBytes;
    const auto rowEnd       = rowOffset + rowBytes;
    if (lastRowStart > std::numeric_limits<size_t>::max() - rowEnd || lastRowStart + rowEnd > bufLen) {
        LOGM(Log::ERR, "Can't copy: shm buffer is too small");
        return false;
    }

    g_pHyprOpenGL->makeEGLCurrent();
    g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, getFBID());
    bind();

    glPixelStorei(GL_PACK_ALIGNMENT, 1);

    int         glFormat = PFORMAT->glFormat;

    static auto stripSwizzleAlpha = [](std::array<GLint, 4> arr) {
        arr[3] = GL_ONE;
        return arr;
    };

    if (PFORMAT->swizzle.has_value()) {
        if (stripSwizzleAlpha(*PFORMAT->swizzle) == stripSwizzleAlpha(SWIZZLE_RGBA))
            glFormat = GL_RGBA;
        else if (stripSwizzleAlpha(*PFORMAT->swizzle) == stripSwizzleAlpha(SWIZZLE_BGRA))
            glFormat = GL_BGRA_EXT;
        else {
            LOGM(Log::ERR, "Copied frame via shm might be broken or color flipped");
            glFormat = GL_RGBA;
        }
    } else if (glFormat == GL_RGBA)
        glFormat = GL_BGRA_EXT;

    // This could be optimized by using a pixel buffer object to make this async,
    // but really clients should just use a dma buffer anyways.
    if (rowOffset == 0 && rowBytes == strideBytes) {
        glReadPixels(offsetX, offsetY, readWidth, readHeight, glFormat, PFORMAT->glType, pixelData + sc<size_t>(offsetY) * strideBytes);
    } else {
        for (uint32_t i = 0; i < readHeight; ++i) {
            const auto y = offsetY + i;
            glReadPixels(offsetX, y, readWidth, 1, glFormat, PFORMAT->glType, pixelData + sc<size_t>(y) * strideBytes + rowOffset);
        }
    }

    unbind();
    glPixelStorei(GL_PACK_ALIGNMENT, 4);

    g_pHyprOpenGL->bindFramebuffer(GL_FRAMEBUFFER, 0);
    return true;
}

CGLFramebuffer::~CGLFramebuffer() {
    release();
}

GLuint CGLFramebuffer::getFBID() {
    return m_fbAllocated ? m_fb : 0;
}

void CGLFramebuffer::invalidate(const std::vector<GLenum>& attachments) {
    if (!isAllocated())
        return;

    // glInvalidateFramebuffer is GLES3, so there is nothing to tell the driver here

    // m_cleared tracks the color attachment only, see clearAfterInvalidation()
    if (std::ranges::contains(attachments, sc<GLenum>(GL_COLOR_ATTACHMENT0)))
        m_cleared = false;
}

void CGLFramebuffer::clearAfterInvalidation() {
    if (m_cleared)
        return;

    m_cleared = true;
    glClearColor(0, 0, 0, 0);
    g_pHyprOpenGL->scissor(nullptr);
    glClear(GL_COLOR_BUFFER_BIT);
}

void CGLFramebuffer::clearRegionAfterInvalidation(const CRegion& region) {
    if (m_cleared)
        return;

    // Only a partial clear, so m_cleared stays false. On GPUs without fast clears a full clear costs as much
    // fill rate as drawing a fullscreen quad, which is most of a frame on old hardware.
    glClearColor(0, 0, 0, 0);
    region.forEachRect([](const auto& RECT) {
        g_pHyprOpenGL->scissor(&RECT, false);
        glClear(GL_COLOR_BUFFER_BIT);
    });
    g_pHyprOpenGL->scissor(nullptr);
}
