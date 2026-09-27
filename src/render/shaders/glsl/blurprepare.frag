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

uniform float     contrast;
uniform float     brightness;


#include "blurprepare.glsl"

void main() {
    gl_FragColor = blurPrepare(texture2D(tex, v_texcoord), contrast, brightness
    );
}
