#pragma once

#include <array>
#include <compare>
#include <glslang/Include/glslang_c_interface.h>
#include <string>
#include <vector>
#include <map>
#include "../helpers/memory/Memory.hpp"

namespace Render {
    enum ePreparedFragmentShaderFeature : uint16_t {
        SH_FEAT_UNKNOWN = 0, // all features just in case

        SH_FEAT_RGBA            = (1 << 0), // RGBA/RGBX texture sampling
        SH_FEAT_DISCARD         = (1 << 1), // RGBA/RGBX texture sampling
        SH_FEAT_TINT            = (1 << 2), // uniforms: tint; condition: applyTint
        SH_FEAT_ROUNDING        = (1 << 3), // uniforms: radius, roundingPower, topLeft, fullSize; condition: radius > 0
        SH_FEAT_BLUR            = (1 << 4), // condition: render:use_shader_blur_blend
        SH_FEAT_BLUR_ALPHA_MASK = (1 << 5), // condition: transformed-window shader blur blend
        SH_FEAT_BLUR_MATTE      = (1 << 6), // condition: transformed-window blur matte
    };

    using ShaderFeatureFlags = uint16_t;

    struct SShaderVariant {
        ShaderFeatureFlags features = 0;

        auto               operator<=>(const SShaderVariant&) const = default;
    };

    enum ePreparedFragmentShader : uint8_t {
        SH_FRAG_QUAD = 0,
        SH_FRAG_PASSTHRURGBA,
        SH_FRAG_MATTE,
        SH_FRAG_EXT,
        SH_FRAG_BLUR1,
        SH_FRAG_BLUR2,
        SH_FRAG_BLURPREPARE,
        SH_FRAG_BLURFINISH,
        SH_FRAG_SHADOW,
        SH_FRAG_INNER_GLOW,
        SH_FRAG_SURFACE,
        SH_FRAG_BORDER1,
        SH_FRAG_GLITCH,
        SH_FRAG_FROSTFINISH,
        SH_FRAG_DROPSFINISH,
        SH_FRAG_HEATSHIMMERFINISH,
        SH_FRAG_AURORAFINISH,
        SH_FRAG_HAZEFINISH,

        SH_FRAG_LAST,
    };

    class CShaderLoader {
      public:
        CShaderLoader(const std::vector<std::string> includes, const std::array<std::string, SH_FRAG_LAST>& frags, const std::string shaderPath = "");
        ~CShaderLoader();

        void                                      include(const std::string& filename);
        std::string                               process(const std::string& filename);
        std::string                               process(const std::string& filename, const std::map<std::string, std::string>& defines);

        std::string                               getVariantSource(ePreparedFragmentShader frag, SShaderVariant variant);

        const std::map<std::string, std::string>& includes();

        std::vector<glsl_include_result_t*>       m_includeResults;

      private:
        std::string loadShader(const std::string& filename);
        std::string getDefines(const SShaderVariant& variant);
        std::string processSource(const std::string& source, glslang_stage_t stage = GLSLANG_STAGE_FRAGMENT);

        //
        std::string                                                     m_shaderPath;
        std::array<std::string, SH_FRAG_LAST>                           m_fragFiles;
        std::array<std::map<SShaderVariant, std::string>, SH_FRAG_LAST> m_fragVariants;
        std::map<std::string, std::string>                              m_includes;

        std::string                                                     m_overrideDefines;
        glsl_include_callbacks_t                                        m_callbacks;
    };

    inline UP<CShaderLoader> g_pShaderLoader;
}
