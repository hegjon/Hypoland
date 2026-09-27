#ifndef ALLOW_INCLUDES
#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable
#endif
#ifndef COLOR_GLSL
#define COLOR_GLSL

#include "constants.h"

// There is no color management, the only transfer functions are sRGB, gamma 2.2 and linear.

// Many transfer functions (including sRGB) follow the same pattern: a linear
// segment for small values and a power function for larger values.
vec3 tfInvLinPow(vec3 color, float gamma, float thres, float scale, float alpha) {
    bvec3 isLow = lessThanEqual(color.rgb, vec3(thres * scale));
    vec3  lo    = color.rgb / scale;
    vec3  hi    = pow((color.rgb + alpha - 1.0) / alpha, vec3(gamma));
    return mix(hi, lo, vec3(isLow));
}

vec3 tfInvSRGB(vec3 color) {
    return tfInvLinPow(color, SRGB_POW, SRGB_CUT, SRGB_SCALE, SRGB_ALPHA);
}

vec3 tfLinPow(vec3 color, float gamma, float thres, float scale, float alpha) {
    bvec3 isLow = lessThanEqual(color.rgb, vec3(thres));
    vec3  lo    = color.rgb * scale;
    vec3  hi    = pow(color.rgb, vec3(1.0 / gamma)) * alpha - (alpha - 1.0);
    return mix(hi, lo, vec3(isLow));
}

vec3 tfSRGB(vec3 color) {
    return tfLinPow(color, SRGB_POW, SRGB_CUT, SRGB_SCALE, SRGB_ALPHA);
}

vec3 toLinearRGB(vec3 color, int tf) {
    if (tf == CM_TRANSFER_FUNCTION_LINEAR || tf == CM_TRANSFER_FUNCTION_EXT_LINEAR)
        return color;
    if (tf == CM_TRANSFER_FUNCTION_GAMMA22)
        return pow(max(color, vec3(0.0)), vec3(2.2));

    return tfInvSRGB(color);
}

vec3 fromLinearRGB(vec3 color, int tf) {
    if (tf == CM_TRANSFER_FUNCTION_LINEAR || tf == CM_TRANSFER_FUNCTION_EXT_LINEAR)
        return color;
    if (tf == CM_TRANSFER_FUNCTION_GAMMA22)
        return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));

    return tfSRGB(color);
}

vec4 fromLinear(vec4 color, int tf) {
    if (tf == CM_TRANSFER_FUNCTION_EXT_LINEAR || tf == CM_TRANSFER_FUNCTION_LINEAR)
        return color;

    color.rgb /= max(color.a, 0.001);
    color.rgb = fromLinearRGB(color.rgb, tf);
    color.rgb *= color.a;
    return color;
}

#endif
