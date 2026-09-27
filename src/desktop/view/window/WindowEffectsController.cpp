#include "WindowEffectsController.hpp"

#include <algorithm>
#include <cmath>

#include "Window.hpp"
#include "../../../managers/input/InputManager.hpp"
#include "../../../render/Renderer.hpp"
#include "../../../render/transformer/TransformerList.hpp"
#include "../../../render/transformer/WobbleTransformer.hpp"
#include "../../../output/Monitor.hpp"

using namespace Desktop::View;

CWindowEffectsController::CWindowEffectsController(CWindow& window) : m_window(window), m_transformers(makeUnique<Render::CWindowTransformerList>()) {
    ;
}

CWindowEffectsController::~CWindowEffectsController() = default;

Render::CWobbleTransformer* CWindowEffectsController::wobbleTransformer() {
    return m_transformers->get<Render::CWobbleTransformer>();
}

void CWindowEffectsController::resetWobble() {
    if (auto WOBBLE = wobbleTransformer())
        WOBBLE->resetWithDamage();

    m_transformers->removeInactive();
}

void CWindowEffectsController::reset() {
    resetWobble();
}

void CWindowEffectsController::onPositionUpdate(const CBox& previous, const CBox& current, eWindowUpdateSource source) {
    if (previous == current)
        return;

    if (!Render::CWobbleTransformer::shouldEnable(m_window.m_self.lock())) {
        resetWobble();
        return;
    }

    auto WOBBLE = wobbleTransformer();
    if (!WOBBLE)
        WOBBLE = m_transformers->emplace<Render::CWobbleTransformer>(m_window.m_self);

    std::optional<Vector2D> grabPoint;
    if (source == WINDOW_UPDATE_MOUSE && current.w > 0.F && current.h > 0.F) {
        const auto MOUSE = g_pInputManager->getMouseCoordsInternal();
        grabPoint        = Vector2D{std::clamp((MOUSE.x - current.x) / current.w, 0.0, 1.0), std::clamp((MOUSE.y - current.y) / current.h, 0.0, 1.0)};
    }

    if (WOBBLE)
        WOBBLE->record(previous, current, grabPoint);
}

bool CWindowEffectsController::tickWobble() {
    const auto WOBBLE = wobbleTransformer();
    if (!WOBBLE)
        return false;

    const bool ACTIVE = WOBBLE->tick();
    m_transformers->removeInactive();
    return ACTIVE;
}

bool CWindowEffectsController::hasActiveTransformers() const {
    return !m_transformers->empty();
}

bool CWindowEffectsController::blocksDirectScanout() const {
    return m_transformers->blocksDirectScanout();
}

CBox CWindowEffectsController::transformedExtents(const CBox& currentBox) const {
    return m_transformers->transformedExtents(currentBox);
}

CBox CWindowEffectsController::transformBoxForDamage(const CBox& currentBox) const {
    return m_transformers->transformBoxForDamage(currentBox);
}

void CWindowEffectsController::preWindowRender(CSurfacePassElement::SRenderData* renderData) const {
    m_transformers->preWindowRender(renderData);
}

const UP<Render::CWindowTransformerList>& CWindowEffectsController::transformers() const {
    return m_transformers;
}
