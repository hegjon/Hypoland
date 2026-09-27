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
uniform int       passes;
uniform float     vibrancy;
uniform float     vibrancy_darkness;

varying vec2           v_texcoord;

#include "blur1.glsl"

void main() {
    gl_FragColor = blur1(v_texcoord, tex, radius, halfpixel, passes, vibrancy, vibrancy_darkness);
}
