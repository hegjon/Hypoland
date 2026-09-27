#include "GLRenderbuffer.hpp"
#include "../Renderer.hpp"
#include "../OpenGL.hpp"
#include "../../Compositor.hpp"
#include "../Framebuffer.hpp"
#include "GLFramebuffer.hpp"
#include "GLTexture.hpp"
#include "../Renderbuffer.hpp"
#include <hyprutils/memory/SharedPtr.hpp>
#include <hyprutils/signal/Listener.hpp>
#include <hyprutils/signal/Signal.hpp>

#include <dlfcn.h>

using namespace Render::GL;

CGLRenderbuffer::~CGLRenderbuffer() {
    if (!g_pCompositor || g_pCompositor->m_isShuttingDown || !g_pHyprRenderer)
        return;

    g_pHyprOpenGL->makeEGLCurrent();

    if (m_framebuffer) {
        unbind();
        m_framebuffer->release();
    }

    if (m_rbo)
        glDeleteRenderbuffers(1, &m_rbo);

    if (m_image != EGL_NO_IMAGE_KHR)
        g_pHyprOpenGL->m_proc.eglDestroyImageKHR(g_pHyprOpenGL->m_eglDisplay, m_image);
}

CGLRenderbuffer::CGLRenderbuffer(SP<Aquamarine::IBuffer> buffer, uint32_t format) : IRenderbuffer(buffer, format) {
    auto dma = buffer->dmabuf();

    m_image = g_pHyprOpenGL->createEGLImage(dma);
    if (m_image == EGL_NO_IMAGE_KHR) {
        Log::logger->log(Log::ERR, "rb: createEGLImage failed");
        return;
    }

    m_framebuffer = makeShared<CGLFramebuffer>();
    glGenFramebuffers(1, &GLFB(m_framebuffer)->m_fb);
    GLFB(m_framebuffer)->m_fbAllocated = true;
    m_framebuffer->m_size              = buffer->size;
    m_framebuffer->m_drmFormat         = dma.format;

    // Render into the buffer through a renderbuffer, and import it a second time as a texture so the renderer
    // can also sample from it (blur). With the texture the renderer can draw a frame straight into this buffer
    // instead of into a work buffer that is copied over afterwards, see CHyprOpenGLImpl::canRenderDirectly().
    glGenRenderbuffers(1, &m_rbo);
    glBindRenderbuffer(GL_RENDERBUFFER, m_rbo);
    g_pHyprOpenGL->m_proc.glEGLImageTargetRenderbufferStorageOES(GL_RENDERBUFFER, m_image);
    glBindRenderbuffer(GL_RENDERBUFFER, 0);

    m_framebuffer->bind();
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, m_rbo);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        Log::logger->log(Log::ERR, "rbo: glCheckFramebufferStatus failed");
        return;
    }

    // the texture takes over its own EGLImage
    if (const auto TEXIMAGE = g_pHyprOpenGL->createEGLImage(dma); TEXIMAGE != EGL_NO_IMAGE_KHR) {
        auto tex = makeShared<CGLTexture>(dma, TEXIMAGE, true);
        if (tex->ok()) {
            GLFB(m_framebuffer)->m_tex     = tex;
            GLFB(m_framebuffer)->m_tempBuf = false;

            // blur needs a stencil when it renders into this buffer
            glGenRenderbuffers(1, &GLFB(m_framebuffer)->m_stencilRB);
            glBindRenderbuffer(GL_RENDERBUFFER, GLFB(m_framebuffer)->m_stencilRB);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, buffer->size.x, buffer->size.y);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, GLFB(m_framebuffer)->m_stencilRB);
            glBindRenderbuffer(GL_RENDERBUFFER, 0);

            if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
                Log::logger->log(Log::ERR, "rbo: no stencil for the buffer, frames are copied into it");
                glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, 0);
                glDeleteRenderbuffers(1, &GLFB(m_framebuffer)->m_stencilRB);
                GLFB(m_framebuffer)->m_stencilRB = 0;
                GLFB(m_framebuffer)->m_tex.reset();
                GLFB(m_framebuffer)->m_tempBuf = true;
            }
        }
    }

    GLFB(m_framebuffer)->unbind();

    m_listeners.destroyBuffer = buffer->events.destroy.listen([this] { g_pHyprRenderer->onRenderbufferDestroy(this); });

    m_good = true;
}

void CGLRenderbuffer::bind() {
    g_pHyprOpenGL->makeEGLCurrent();
    g_pHyprRenderer->bindFB(m_framebuffer);
}

void CGLRenderbuffer::unbind() {
    GLFB(m_framebuffer)->unbind();
}
