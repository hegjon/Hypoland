#version 100
#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable

#include "defines.h"

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
varying vec4       v_color;
varying vec2       v_texcoord;

uniform vec4  colorSRGB;
uniform vec2  topLeft;
uniform vec2  bottomRight;
uniform vec2  windowTopLeft;
uniform vec2  windowBottomRight;
uniform vec2  fullSize;
uniform float radius;
uniform float roundingPower;
uniform float range;
uniform float shadowPower;
uniform float thick;

// Gradients are in OkLabA!!!! {l, a, b, alpha}
uniform vec4  gradient[10];
uniform vec4  gradient2[10];
uniform int   gradientLength;
uniform int   gradient2Length;
uniform float angle;
uniform float angle2;
uniform float gradientLerp;
uniform float alpha;

#include "shadow.glsl"

void main() {
    vec4 pixColor = v_color;
    gl_FragColor =
        getShadow(pixColor, colorSRGB, v_texcoord, radius, roundingPower, topLeft, fullSize, range, shadowPower, bottomRight, windowTopLeft, windowBottomRight, thick,
                  gradientLength, gradient, angle, gradient2Length, gradient2, angle2, gradientLerp, alpha
        );
}
