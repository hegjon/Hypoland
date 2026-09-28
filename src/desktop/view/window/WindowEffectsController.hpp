#pragma once

#include <optional>

#include "../../../render/transformer/Transformer.hpp"

namespace Render {
    class CWobbleTransformer;
    class CWindowTransformerList;
}

namespace Desktop::View {
    class CWindow;
    enum eWindowUpdateSource : uint8_t;

    class CWindowEffectsController {
      public:
        explicit CWindowEffectsController(CWindow& window);
        ~CWindowEffectsController();

        CWindowEffectsController(const CWindowEffectsController&)                            = delete;
        CWindowEffectsController(CWindowEffectsController&&)                                 = delete;
        CWindowEffectsController&                 operator=(const CWindowEffectsController&) = delete;
        CWindowEffectsController&                 operator=(CWindowEffectsController&&)      = delete;

        void                                      onPositionUpdate(const CBox& previous, const CBox& current, eWindowUpdateSource source);
        void                                      resetWobble();
        void                                      reset();
        bool                                      tickWobble();

        bool                                      hasActiveTransformers() const;
        bool                                      blocksDirectScanout() const;
        CBox                                      transformedExtents(const CBox& currentBox) const;
        CBox                                      transformBoxForDamage(const CBox& currentBox) const;
        void                                      preWindowRender(CSurfacePassElement::SRenderData* renderData) const;
        const UP<Render::CWindowTransformerList>& transformers() const;

      private:
        Render::CWobbleTransformer*        wobbleTransformer();

        CWindow&                           m_window;
        UP<Render::CWindowTransformerList> m_transformers;
    };
}
