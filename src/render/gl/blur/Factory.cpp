#include "Factory.hpp"

#include "Aurora.hpp"
#include "Drops.hpp"
#include "Glass.hpp"
#include "Haze.hpp"
#include "HeatShimmer.hpp"
#include "Kawase.hpp"
#include "../../ShaderLoader.hpp"
#include "../../../debug/log/Logger.hpp"

using namespace Render;
using namespace Render::GL;

UP<IGLBlurProvider> Render::GL::createBlurProvider(eBlurType type, CHyprOpenGLImpl& impl) {
    switch (type) {
        case eBlurType::BLUR_DUAL_KAWASE: return makeUnique<CDualKawaseBlurProvider>(impl);
        case eBlurType::BLUR_FROST: return makeUnique<CGlassBlurProvider>(impl, type, SH_FRAG_FROSTFINISH);
        case eBlurType::BLUR_DROPS: return makeUnique<CDropsBlurProvider>(impl);
        case eBlurType::BLUR_HEAT_SHIMMER: return makeUnique<CHeatShimmerBlurProvider>(impl);
        case eBlurType::BLUR_AURORA: return makeUnique<CAuroraBlurProvider>(impl);
        case eBlurType::BLUR_HAZE: return makeUnique<CHazeBlurProvider>(impl);

        // these need GLES3 (textureSize, integer textures) and are not available
        case eBlurType::BLUR_RIPPLE:
        case eBlurType::BLUR_WATER:
        case eBlurType::BLUR_FLUID_JAR:
        case eBlurType::BLUR_PRISM:
        case eBlurType::BLUR_ACRYLIC:
            Log::logger->log(Log::WARN, "Blur type {} is not available with GLES2, using dual Kawase", sc<uint8_t>(type));
            return makeUnique<CDualKawaseBlurProvider>(impl);
    }

    Log::logger->log(Log::ERR, "Unknown blur provider {}, falling back to dual Kawase", sc<uint8_t>(type));
    return makeUnique<CDualKawaseBlurProvider>(impl);
}
