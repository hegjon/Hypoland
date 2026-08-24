#include "GLES2ShaderCompat.hpp"

#include <regex>
#include <sstream>
#include <vector>

namespace NGLES2Shader {
    namespace {
        const std::regex RE_VERSION(R"(^\s*#version\b.*$)");
        const std::regex RE_LINE_DIRECTIVE(R"(^\s*#line\b.*$)");
        const std::regex RE_EXT_INCLUDE(R"(^\s*#extension\s+GL_ARB_shading_language_include\b.*$)");
        const std::regex RE_EXT_EXTERNAL_ESSL3(R"(^(\s*#extension\s+)GL_OES_EGL_image_external_essl3(\s*:.*)$)");
        const std::regex RE_PRECISION_HIGHP(R"(^\s*precision\s+highp\s+float\s*;\s*$)");
        const std::regex RE_LAYOUT_OUT(R"(^(\s*)layout\s*\(\s*location\s*=\s*(\d+)\s*\)\s*out\s+(\w+)\s+(\w+)\s*;\s*$)");
        const std::regex RE_OUT_DECL(R"(^(\s*)(?:centroid\s+|smooth\s+)?out\s+(\w+)\s+(\w+)\s*;\s*$)");
        const std::regex RE_IN_DECL(R"(^(\s*)(?:centroid\s+|smooth\s+)?in\s+(\w+)\s+(\w+)\s*;\s*$)");

        // texture() -> texture2D(). The word boundary plus "\s*\(" leaves
        // textureSize()/textureLod()/texelFetch() untouched so that the
        // unsupported-construct check below can still catch them.
        const std::regex RE_TEXTURE_CALL(R"(\btexture\s*\()");

        // Constructs with no GLSL ES 1.00 equivalent. Hitting one means a
        // feature that should have been gated off on this path was not.
        const std::regex RE_UNSUPPORTED(R"(\b(texelFetch|textureSize|textureLod|uint|uvec[234]|usampler2D|isampler2D)\b)");

        const std::regex RE_SWITCH_OPEN(R"(^(\s*)switch\s*\((.+)\)\s*\{\s*$)");
        const std::regex RE_CASE(R"(^\s*case\s+(-?\d+)\s*:(.*)$)");
        const std::regex RE_DEFAULT(R"(^\s*default\s*:(.*)$)");

        std::string      trim(const std::string& s) {
            const auto b = s.find_first_not_of(" \t\r");
            if (b == std::string::npos)
                return "";
            return s.substr(b, s.find_last_not_of(" \t\r") - b + 1);
        }

        struct SCaseGroup {
            std::vector<std::string> labels;
            bool                     isDefault = false;
            std::vector<std::string> body;
        };

        // GLSL ES 1.00 has no switch. Every switch in the renderer's shaders is
        // a pure value lookup -- each case returns, none fall through into a
        // non-empty body, and default comes last -- so it maps exactly onto an
        // if/else chain. Anything outside that shape is rejected rather than
        // silently mistranslated.
        bool convertSwitch(const std::vector<std::string>& lines, size_t& i, const std::string& indent, const std::string& expr, int uid, std::vector<std::string>& out,
                           std::string& error) {
            std::vector<SCaseGroup> groups;
            int                     depth = 1;
            size_t                  j     = i + 1;

            for (; j < lines.size(); ++j) {
                const auto& line = lines[j];

                for (const char ch : line) {
                    if (ch == '{')
                        depth++;
                    else if (ch == '}')
                        depth--;
                }
                if (depth == 0)
                    break; // closing brace of the switch

                std::smatch m;
                const bool  isCase = std::regex_match(line, m, RE_CASE);
                std::smatch md;
                const bool  isDefault = !isCase && std::regex_match(line, md, RE_DEFAULT);

                if (isCase || isDefault) {
                    const std::string rest = trim(isCase ? m[2].str() : md[1].str());

                    // An empty label body falls through to the next label: keep
                    // accumulating into the same group.
                    if (!groups.empty() && groups.back().body.empty()) {
                        if (isCase)
                            groups.back().labels.push_back(m[1].str());
                        else
                            groups.back().isDefault = true;
                    } else {
                        SCaseGroup g;
                        if (isCase)
                            g.labels.push_back(m[1].str());
                        else
                            g.isDefault = true;
                        groups.push_back(std::move(g));
                    }

                    if (!rest.empty())
                        groups.back().body.push_back(rest);
                    continue;
                }

                if (groups.empty()) {
                    if (trim(line).empty())
                        continue;
                    error = "statement before the first case label in a switch";
                    return false;
                }
                groups.back().body.push_back(trim(line));
            }

            if (depth != 0) {
                error = "unterminated switch";
                return false;
            }

            for (size_t g = 0; g < groups.size(); ++g) {
                if (groups[g].body.empty()) {
                    error = "empty case body at the end of a switch";
                    return false;
                }
                if (groups[g].isDefault && g + 1 != groups.size()) {
                    error = "default label is not last in a switch";
                    return false;
                }
                // No break statements, so every group must exit via return.
                const auto& last = groups[g].body.back();
                if (last.rfind("return", 0) != 0) {
                    error = "case body does not end in return (fallthrough is not supported)";
                    return false;
                }
            }

            const std::string var = "hyprSwitch" + std::to_string(uid);
            out.push_back(indent + "{");
            out.push_back(indent + "    int " + var + " = " + expr + ";");

            bool first = true;
            for (const auto& g : groups) {
                std::string cond;
                if (g.isDefault && g.labels.empty())
                    cond = "";
                else {
                    for (size_t k = 0; k < g.labels.size(); ++k) {
                        if (k)
                            cond += " || ";
                        cond += var + " == " + g.labels[k];
                    }
                    if (g.isDefault)
                        cond = ""; // default subsumes its fall-through labels
                }

                if (cond.empty())
                    out.push_back(indent + "    " + (first ? "" : "else ") + "{");
                else
                    out.push_back(indent + "    " + (first ? "if (" : "else if (") + cond + ") {");

                for (const auto& b : g.body) {
                    out.push_back(indent + "        " + b);
                }
                out.push_back(indent + "    }");
                first = false;
            }
            out.push_back(indent + "}");

            i = j; // consume through the switch's closing brace
            return true;
        }
    }

    SResult downgradeToES100(const std::string& src, bool vertexStage) {
        SResult                  res;

        std::vector<std::string> lines;
        {
            std::istringstream in(src);
            std::string        line;
            while (std::getline(in, line)) {
                lines.push_back(line);
            }
        }

        std::string              fragColorName;
        std::vector<std::string> body;
        body.reserve(lines.size() + 32);
        int switchUid = 0;

        for (size_t i = 0; i < lines.size(); ++i) {
            const auto& line = lines[i];

            if (std::regex_match(line, RE_VERSION) || std::regex_match(line, RE_LINE_DIRECTIVE) || std::regex_match(line, RE_EXT_INCLUDE))
                continue;

            std::smatch m;

            // The essl3 variant of the external-image extension only exists for
            // ES 3.00 shaders; ES 1.00 uses the original extension, where
            // external samplers are read with texture2D().
            if (std::regex_match(line, m, RE_EXT_EXTERNAL_ESSL3)) {
                body.push_back(m[1].str() + "GL_OES_EGL_image_external" + m[2].str());
                continue;
            }

            if (!vertexStage && std::regex_match(line, RE_PRECISION_HIGHP)) {
                body.emplace_back("#ifdef GL_FRAGMENT_PRECISION_HIGH");
                body.emplace_back("precision highp float;");
                body.emplace_back("#else");
                body.emplace_back("precision mediump float;");
                body.emplace_back("#endif");
                continue;
            }

            if (!vertexStage && std::regex_match(line, m, RE_LAYOUT_OUT)) {
                if (m[2].str() != "0") {
                    res.ok    = false;
                    res.error = "shader writes to colour attachment " + m[2].str() + "; GLES2 has only one (MRT is unavailable)";
                    return res;
                }
                fragColorName = m[4].str();
                continue;
            }

            if (std::regex_match(line, m, RE_OUT_DECL)) {
                if (vertexStage) {
                    body.push_back(m[1].str() + "varying " + m[2].str() + " " + m[3].str() + ";");
                    continue;
                }
                fragColorName = m[3].str();
                continue;
            }

            if (std::regex_match(line, m, RE_IN_DECL)) {
                body.push_back(m[1].str() + (vertexStage ? "attribute " : "varying ") + m[2].str() + " " + m[3].str() + ";");
                continue;
            }

            if (std::regex_match(line, m, RE_SWITCH_OPEN)) {
                std::string error;
                if (!convertSwitch(lines, i, m[1].str(), m[2].str(), switchUid++, body, error)) {
                    res.ok    = false;
                    res.error = "switch conversion failed: " + error;
                    return res;
                }
                continue;
            }

            body.push_back(line);
        }

        std::ostringstream out;
        out << "#version 100\n";
        // dFdx/dFdy/fwidth are core in ES 3.00 but an extension in ES 1.00.
        // "enable" rather than "require" so a driver without it only warns.
        if (!vertexStage)
            out << "#extension GL_OES_standard_derivatives : enable\n";
        if (!vertexStage && !fragColorName.empty() && fragColorName != "gl_FragColor")
            out << "#define " << fragColorName << " gl_FragColor\n";

        for (const auto& l : body) {
            out << l << "\n";
        }

        res.source = std::regex_replace(out.str(), RE_TEXTURE_CALL, "texture2D(");

        std::smatch bad;
        if (std::regex_search(res.source, bad, RE_UNSUPPORTED)) {
            res.ok    = false;
            res.error = "shader uses '" + bad[1].str() + "', which does not exist in GLSL ES 1.00";
        }

        return res;
    }
}
