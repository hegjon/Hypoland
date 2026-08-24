#pragma once

#include <string>

// Rewrites the renderer's GLSL ES 3.00 shaders into GLSL ES 1.00 so they can be
// compiled by an OpenGL ES 2.0 driver (Intel gen4/gen4.5/gen5 under crocus --
// e.g. the GM45 in a ThinkPad X200).
//
// Input must be *preprocessed* source: all #include and #if directives already
// resolved, which is what CShaderLoader::processSource() produces. That means
// this pass only ever sees plain declarations and statements, so a line-oriented
// rewrite is sufficient and there is no need to reimplement a GLSL parser.
//
// Deliberately dependency-free (no Hyprland headers) so it can be unit-tested
// against a real GLES2 context outside the compositor.
namespace NGLES2Shader {
    struct SResult {
        std::string source;
        bool        ok = true;
        std::string error; // set when the shader cannot be expressed in ES 1.00
    };

    // vertexStage selects the `in`/`out` mapping: attribute/varying for vertex
    // shaders, varying/gl_FragColor for fragment shaders.
    SResult downgradeToES100(const std::string& src, bool vertexStage);
}
