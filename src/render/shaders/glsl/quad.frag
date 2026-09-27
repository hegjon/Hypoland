#version 100

#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable
#include "defines.h"

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
varying vec4   v_color;

uniform vec4 colorSRGB;
#if USE_ROUNDING
uniform float radius;
uniform float roundingPower;
uniform vec2  topLeft;
uniform vec2  fullSize;
#include "rounding.glsl"
#endif

void main() {
    vec4 pixColor = v_color;

#if USE_ROUNDING
    pixColor = rounding(pixColor, radius, roundingPower, topLeft, fullSize);
#endif

    gl_FragColor = pixColor;
}
