#version 100
#define ALLOW_INCLUDES
#extension GL_ARB_shading_language_include : enable

#include "defines.h"

#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
varying vec2           v_texcoord; // is in 0-1
uniform sampler2D tex;
uniform sampler2D texMatte;

void main() {
    gl_FragColor = texture2D(tex, v_texcoord) * texture2D(texMatte, v_texcoord)[0]; // I know it only uses R, but matte should be black/white anyways.
}
