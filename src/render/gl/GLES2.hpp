#pragma once

// Hypoland renders with OpenGL ES 2.0 only.
//
// Include this header instead of the GLES headers. hyprgraphics includes
// <GLES3/gl32.h> from its public headers, so the GLES3 declarations cannot be
// kept out of the build. They are included here first and their entry points
// poisoned afterwards, which turns any use of a GLES3 function into a compile error.

#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <GLES3/gl32.h>
#include <GLES3/gl3ext.h>

// Vertex array objects are an extension in GLES2 (GL_OES_vertex_array_object, required at startup).
// Extension entry points are not exported by libGLESv2, they are loaded in CHyprOpenGLImpl::initEGL().
namespace NGLES2 {
    inline void (*bindVertexArray)(GLuint array)                       = nullptr;
    inline void (*genVertexArrays)(GLsizei n, GLuint* arrays)          = nullptr;
    inline void (*deleteVertexArrays)(GLsizei n, const GLuint* arrays) = nullptr;
}

#define glBindVertexArray    NGLES2::bindVertexArray
#define glGenVertexArrays    NGLES2::genVertexArrays
#define glDeleteVertexArrays NGLES2::deleteVertexArrays

#pragma GCC poison glActiveShaderProgram glBeginQuery glBeginTransformFeedback glBindBufferBase glBindBufferRange glBindImageTexture
#pragma GCC poison glBindProgramPipeline glBindSampler glBindTransformFeedback glBindVertexBuffer glBlendBarrier glBlendEquationi
#pragma GCC poison glBlendEquationSeparatei glBlendFunci glBlendFuncSeparatei glBlitFramebuffer glClearBufferfi glClearBufferfv
#pragma GCC poison glClearBufferiv glClearBufferuiv glClientWaitSync glColorMaski glCompressedTexImage3D glCompressedTexSubImage3D
#pragma GCC poison glCopyBufferSubData glCopyImageSubData glCopyTexSubImage3D glCreateShaderProgramv glDebugMessageCallback glDebugMessageControl
#pragma GCC poison glDebugMessageInsert glDeleteProgramPipelines glDeleteQueries glDeleteSamplers glDeleteSync glDeleteTransformFeedbacks
#pragma GCC poison glDisablei glDispatchCompute glDispatchComputeIndirect glDrawArraysIndirect glDrawArraysInstanced glDrawBuffers
#pragma GCC poison glDrawElementsBaseVertex glDrawElementsIndirect glDrawElementsInstanced glDrawElementsInstancedBaseVertex glDrawRangeElements glDrawRangeElementsBaseVertex
#pragma GCC poison glEnablei glEndQuery glEndTransformFeedback glFenceSync glFlushMappedBufferRange glFramebufferParameteri
#pragma GCC poison glFramebufferTexture glFramebufferTextureLayer glGenProgramPipelines glGenQueries glGenSamplers glGenTransformFeedbacks
#pragma GCC poison glGetActiveUniformBlockiv glGetActiveUniformBlockName glGetActiveUniformsiv glGetBooleani_v glGetBufferParameteri64v glGetBufferPointerv
#pragma GCC poison glGetDebugMessageLog glGetFragDataLocation glGetFramebufferParameteriv glGetGraphicsResetStatus glGetInteger64i_v glGetInteger64v
#pragma GCC poison glGetIntegeri_v glGetInternalformativ glGetMultisamplefv glGetnUniformfv glGetnUniformiv glGetnUniformuiv
#pragma GCC poison glGetObjectLabel glGetObjectPtrLabel glGetPointerv glGetProgramBinary glGetProgramInterfaceiv glGetProgramPipelineInfoLog
#pragma GCC poison glGetProgramPipelineiv glGetProgramResourceIndex glGetProgramResourceiv glGetProgramResourceLocation glGetProgramResourceName glGetQueryiv
#pragma GCC poison glGetQueryObjectuiv glGetSamplerParameterfv glGetSamplerParameterIiv glGetSamplerParameterIuiv glGetSamplerParameteriv glGetStringi
#pragma GCC poison glGetSynciv glGetTexLevelParameterfv glGetTexLevelParameteriv glGetTexParameterIiv glGetTexParameterIuiv glGetTransformFeedbackVarying
#pragma GCC poison glGetUniformBlockIndex glGetUniformIndices glGetUniformuiv glGetVertexAttribIiv glGetVertexAttribIuiv glInvalidateFramebuffer
#pragma GCC poison glInvalidateSubFramebuffer glIsEnabledi glIsProgramPipeline glIsQuery glIsSampler glIsSync
#pragma GCC poison glIsTransformFeedback glMapBufferRange glMemoryBarrier glMemoryBarrierByRegion glMinSampleShading glObjectLabel
#pragma GCC poison glObjectPtrLabel glPatchParameteri glPauseTransformFeedback glPopDebugGroup glPrimitiveBoundingBox glProgramBinary
#pragma GCC poison glProgramParameteri glProgramUniform1f glProgramUniform1fv glProgramUniform1i glProgramUniform1iv glProgramUniform1ui
#pragma GCC poison glProgramUniform1uiv glProgramUniform2f glProgramUniform2fv glProgramUniform2i glProgramUniform2iv glProgramUniform2ui
#pragma GCC poison glProgramUniform2uiv glProgramUniform3f glProgramUniform3fv glProgramUniform3i glProgramUniform3iv glProgramUniform3ui
#pragma GCC poison glProgramUniform3uiv glProgramUniform4f glProgramUniform4fv glProgramUniform4i glProgramUniform4iv glProgramUniform4ui
#pragma GCC poison glProgramUniform4uiv glProgramUniformMatrix2fv glProgramUniformMatrix2x3fv glProgramUniformMatrix2x4fv glProgramUniformMatrix3fv glProgramUniformMatrix3x2fv
#pragma GCC poison glProgramUniformMatrix3x4fv glProgramUniformMatrix4fv glProgramUniformMatrix4x2fv glProgramUniformMatrix4x3fv glPushDebugGroup glReadBuffer
#pragma GCC poison glReadnPixels glRenderbufferStorageMultisample glResumeTransformFeedback glSampleMaski glSamplerParameterf glSamplerParameterfv
#pragma GCC poison glSamplerParameteri glSamplerParameterIiv glSamplerParameterIuiv glSamplerParameteriv glTexBuffer glTexBufferRange
#pragma GCC poison glTexImage3D glTexParameterIiv glTexParameterIuiv glTexStorage2D glTexStorage2DMultisample glTexStorage3D
#pragma GCC poison glTexStorage3DMultisample glTexSubImage3D glTransformFeedbackVaryings glUniform1ui glUniform1uiv glUniform2ui
#pragma GCC poison glUniform2uiv glUniform3ui glUniform3uiv glUniform4ui glUniform4uiv glUniformBlockBinding
#pragma GCC poison glUniformMatrix2x3fv glUniformMatrix2x4fv glUniformMatrix3x2fv glUniformMatrix3x4fv glUniformMatrix4x2fv glUniformMatrix4x3fv
#pragma GCC poison glUnmapBuffer glUseProgramStages glValidateProgramPipeline glVertexAttribBinding glVertexAttribDivisor glVertexAttribFormat
#pragma GCC poison glVertexAttribI4i glVertexAttribI4iv glVertexAttribI4ui glVertexAttribI4uiv glVertexAttribIFormat glVertexAttribIPointer
#pragma GCC poison glVertexBindingDivisor glWaitSync
