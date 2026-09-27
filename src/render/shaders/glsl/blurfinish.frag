#version 100
#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
varying vec2           v_texcoord; // is in 0-1
uniform sampler2D tex;

uniform float     noise;
uniform float     brightness;

#include "defines.h"

#include "blurFinish.glsl"

void main() {
    vec4 pixColor = texture2D(tex, v_texcoord);

    gl_FragColor = blurFinish(pixColor, v_texcoord, noise, brightness
    );
}
