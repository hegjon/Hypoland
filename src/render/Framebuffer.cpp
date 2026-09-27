#include "Framebuffer.hpp"
#include "helpers/Format.hpp"
#include "helpers/cm/ColorManagement.hpp"

using namespace Render;

IFramebuffer::IFramebuffer(const std::string& name) : m_name(name) {}

bool IFramebuffer::alloc(int w, int h, DRMFormat format) {
    RASSERT((w > 0 && h > 0), "cannot alloc a FB with negative / zero size! (attempted {}x{})", w, h);

    const bool sizeChanged   = m_size != Vector2D(w, h);
    const bool formatChanged = format != m_drmFormat;

    if (m_fbAllocated && !sizeChanged && !formatChanged)
        return true;

    if (sizeChanged || formatChanged)
        m_tex.reset();

    m_size        = {w, h};
    m_drmFormat   = format;
    m_fbAllocated = internalAlloc(w, h, format);
    return m_fbAllocated;
}

bool IFramebuffer::isAllocated() {
    return m_fbAllocated && m_tex;
}

SP<ITexture> IFramebuffer::getTexture() {
    return m_tex;
}

SP<ITexture> IFramebuffer::getStencilTex() {
    return m_stencilTex;
}

NColorManagement::PImageDescription IFramebuffer::imageDescription() {
    return m_tex ? m_tex->m_imageDescription : m_imageDescription;
}

void IFramebuffer::setImageDescription(NColorManagement::PImageDescription desc) {
    m_imageDescription = desc;
    if (m_tex)
        m_tex->m_imageDescription = desc;
    else
        Log::logger->log(Log::TRACE, "CM: FIXME no framebuffer texture");
}
