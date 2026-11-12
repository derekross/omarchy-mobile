// SPDX-License-Identifier: MIT
// Explicit render-node GLES pixel checks; run under an external deadline.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <fcntl.h>
#include <gbm.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void require(int ok, const char *what)
{
	if (!ok) {
		fprintf(stderr, "FAIL: %s (EGL %#x GL %#x)\n", what,
			eglGetError(), glGetError());
		exit(1);
	}
}

static GLuint shader(GLenum type, const char *source)
{
	GLuint s = glCreateShader(type);
	GLint ok;
	char log[2048];

	glShaderSource(s, 1, &source, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		fprintf(stderr, "%s\n", log);
	}
	require(ok, "shader compile");
	return s;
}

static void pixels(int size, int r, int g, int b, const char *name)
{
	size_t count = (size_t)size * size;
	unsigned char *data = malloc(count * 4);

	require(data != NULL, "pixel allocation");
	glFinish();
	glReadPixels(0, 0, size, size, GL_RGBA, GL_UNSIGNED_BYTE, data);
	require(glGetError() == GL_NO_ERROR, "pixel readback");
	for (size_t i = 0; i < count; ++i) {
		if (abs(data[i * 4] - r) > 1 || abs(data[i * 4 + 1] - g) > 1 ||
		    abs(data[i * 4 + 2] - b) > 1 || data[i * 4 + 3] != 255) {
			fprintf(stderr, "FAIL: %s size %d pixel %zu = %u,%u,%u,%u\n",
				name, size, i, data[i * 4], data[i * 4 + 1],
				data[i * 4 + 2], data[i * 4 + 3]);
			exit(1);
		}
	}
	free(data);
	printf("PASS: %s %dx%d all pixels\n", name, size, size);
	fflush(stdout);
}

int main(int argc, char **argv)
{
	const char *node = argc > 1 ? argv[1] : "/dev/dri/renderD128";
	const char *vs = "#version 300 es\n"
		"void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);"
		"gl_Position=vec4(p*2.-1.,0.,1.);}";
	const char *fs = "#version 300 es\nprecision highp float;"
		"uniform vec4 color;out vec4 outColor;"
		"void main(){outColor=color;}";
	EGLint config_attrs[] = {EGL_SURFACE_TYPE, 0, EGL_RENDERABLE_TYPE,
		EGL_OPENGL_ES3_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
	EGLint context_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
	EGLConfig config;
	EGLint count;
	GLuint program, framebuffer, texture;
	GLint linked, color;
	int sizes[] = {64, 257, 1024};
	int fd = open(node, O_RDWR | O_CLOEXEC);
	struct gbm_device *gbm;
	EGLDisplay display;
	EGLContext context;
	const char *renderer;

	setbuf(stdout, NULL);
	require(fd >= 0, "open render node");
	gbm = gbm_create_device(fd);
	require(gbm != NULL, "GBM device");
	display = eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL);
	require(display != EGL_NO_DISPLAY && eglInitialize(display, NULL, NULL),
		"EGL initialize on explicit GBM device");
	require(eglBindAPI(EGL_OPENGL_ES_API), "bind GLES");
	require(eglChooseConfig(display, config_attrs, &config, 1, &count) && count,
		"GLES3 configuration");
	context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attrs);
	require(context != EGL_NO_CONTEXT, "GLES3 context");
	require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context),
		"surfaceless context");
	renderer = (const char *)glGetString(GL_RENDERER);
	printf("Renderer: %s\nVersion: %s\n", renderer ? renderer : "NULL",
		glGetString(GL_VERSION));
	require(renderer && strstr(renderer, "Mali-G78") && strstr(renderer, "Panfrost"),
		"hardware Mali-G78 Panfrost renderer");
	program = glCreateProgram();
	glAttachShader(program, shader(GL_VERTEX_SHADER, vs));
	glAttachShader(program, shader(GL_FRAGMENT_SHADER, fs));
	glLinkProgram(program);
	glGetProgramiv(program, GL_LINK_STATUS, &linked);
	require(linked, "program link");
	glUseProgram(program);
	color = glGetUniformLocation(program, "color");
	require(color >= 0, "color uniform");
	glGenFramebuffers(1, &framebuffer);
	glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	for (unsigned int i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
		int size = sizes[i];

		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, size, size, 0,
			GL_RGBA, GL_UNSIGNED_BYTE, NULL);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
			GL_TEXTURE_2D, texture, 0);
		require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
			"RGBA8 framebuffer");
		glViewport(0, 0, size, size);
		glDisable(GL_BLEND);
		glClearColor(1, 0, 0, 1);
		glClear(GL_COLOR_BUFFER_BIT);
		pixels(size, 255, 0, 0, "clear");
		glUniform4f(color, 0, 1, 0, 1);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		pixels(size, 0, 255, 0, "shader solid");
		glEnable(GL_BLEND);
		glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
			GL_ZERO, GL_ONE);
		glUniform4f(color, 0, 0, 1, 0.5);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		pixels(size, 0, 127, 128, "shader blend");
	}
	require(glGetError() == GL_NO_ERROR, "final GL status");
	glDeleteTextures(1, &texture);
	glDeleteFramebuffers(1, &framebuffer);
	glDeleteProgram(program);
	eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroyContext(display, context);
	eglTerminate(display);
	gbm_device_destroy(gbm);
	close(fd);
	puts("PASS: Bluejay headless hardware rendering");
	return 0;
}
