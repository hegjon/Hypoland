#version 100
#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif

uniform sampler2D tex;
uniform float     radius;
uniform vec2      halfpixel;

varying vec2           v_texcoord;

#include "blur2.glsl"

void main() {
    gl_FragColor = blur2(v_texcoord, tex, radius, halfpixel);
}
