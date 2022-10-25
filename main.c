#include <stdint.h>
#include <stdio.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#include <cairo-ft.h>
#include <cairo-pdf.h>
#include <cairo.h>

#include <libavcodec/avcodec.h>
#include <libavutil/frame.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

cairo_t *cr;
FT_Face face;
cairo_font_face_t *cface;
cairo_surface_t *surface;

int
draw_line(lua_State *L)
{
	double t = lua_tonumber(L, -5);
	double x1 = lua_tonumber(L, -4);
	double y1 = lua_tonumber(L, -3);
	double x2 = lua_tonumber(L, -2);
	double y2 = lua_tonumber(L, -1);

	cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);

	cairo_move_to(cr, x1, y1);
	cairo_line_to(cr, x2, y2);
	cairo_set_line_width(cr, t);
	cairo_stroke(cr);

	return 0;
}

int
draw_quad(lua_State *L)
{
	double x1 = lua_tonumber(L, -8);
	double y1 = lua_tonumber(L, -7);
	double x2 = lua_tonumber(L, -6);
	double y2 = lua_tonumber(L, -5);
	double x3 = lua_tonumber(L, -4);
	double y3 = lua_tonumber(L, -3);
	double x4 = lua_tonumber(L, -2);
	double y4 = lua_tonumber(L, -1);

	cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);

	cairo_move_to(cr, x1, y1);
	cairo_line_to(cr, x2, y2);
	cairo_line_to(cr, x3, y3);
	cairo_line_to(cr, x4, y4);
	cairo_fill(cr);

	return 0;
}

int
draw_glyph(lua_State *L)
{
	unsigned int val = lua_tonumber(L, -3);
	double x = lua_tonumber(L, -2);
	double y = lua_tonumber(L, -1);

	int index = FT_Get_Char_Index(face, val);
	cairo_glyph_t glyph = {index, x, y};

	cairo_set_font_face(cr, cface);
	cairo_set_font_size(cr, 32.0);

	cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);
	cairo_show_glyphs(cr, &glyph, 1);

	return 0;
}

int
glyph_extents(lua_State *L)
{
	unsigned int val = lua_tonumber(L, -1);
	unsigned int index = FT_Get_Char_Index(face, val);
	cairo_glyph_t glyph = {index, 0, 0};
	cairo_text_extents_t extents;
	cairo_glyph_extents(cr, &glyph, 1, &extents);

	lua_pushnumber(L, extents.width);
	lua_pushnumber(L, extents.height);

	return 2;
}

int
create_surface(lua_State *L)
{
	double width = lua_tonumber(L, -2);
	double height = lua_tonumber(L, -1);

	cairo_set_font_face(cr, cface);
	cairo_set_font_size(cr, 32.0);

	return 0;
}

int
putframe(AVCodecContext *ctx, AVFrame *frame, AVPacket *pkt, FILE *out)
{
	int ret;

	ret = avcodec_send_frame(ctx, frame);
	if (ret < 0) {
		fprintf(stderr, "error sending frame to encoder\n");
		exit(1);
	}

	while (ret >= 0) {
		ret = avcodec_receive_packet(ctx, pkt);
		if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
			return 0;
		else if (ret < 0) {
			fprintf(stderr, "error encoding audio frame\n");
			exit(1);
		}

		fwrite(pkt->data, 1, pkt->size, out);
		av_packet_unref(pkt);
	}
}

int
main(int argc, char *argv[])
{
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);
	lua_pushcfunction(L, create_surface);
	lua_setglobal(L, "create_surface");
	lua_pushcfunction(L, draw_glyph);
	lua_setglobal(L, "draw_glyph");
	lua_pushcfunction(L, draw_line);
	lua_setglobal(L, "draw_line");
	lua_pushcfunction(L, draw_quad);
	lua_setglobal(L, "draw_quad");
	lua_pushcfunction(L, glyph_extents);
	lua_setglobal(L, "glyph_extents");
	FT_Library library;
	int error = FT_Init_FreeType(&library);

	// TODO: print the actual error
	if (error) {
		fprintf(stderr, "freetype init error");
		return 1;
	}

	error = FT_New_Face(library, "/usr/share/fonts/OTF/Bravura.otf", 0, &face);
	if (error) {
		fprintf(stderr, "freetype font load error");
		return 1;
	}

	cface = cairo_ft_font_face_create_for_ft_face(face, 0);
	if (!cface) {
		fprintf(stderr, "cairo font face load error");
		return 1;
	}

	FILE *output = fopen("out.h264", "wb");
	if (!output) {
		fprintf(stderr, "couldn't open output\n");
		return 1;
	}

	AVPacket *pkt = av_packet_alloc();
	if (!pkt) {
		fprintf(stderr, "couldn't allocate packet!\n");
		return 1;
	}

	AVFrame *frame = av_frame_alloc();
	if (!frame) {
		fprintf(stderr, "couldn't allocate frame!\n");
		return 1;
	}

	const AVCodec *codec = avcodec_find_encoder_by_name("libx264rgb");
	if (!codec) {
		fprintf(stderr, "couldn't find h264 codec!\n");
		return 1;
	}

	AVCodecContext *c = avcodec_alloc_context3(codec);
	if (!c) {
		fprintf(stderr, "couldn't alloc AVCodec context!\n");
		return 1;
	}

	// suggested bitrates: https://www.videoproc.com/media-converter/bitrate-setting-for-h264.htm
	c->bit_rate = 2500*1000;
	c->width = 854;
	c->height = 480;
	c->time_base.num = 1;
	c->time_base.den = 30;
	c->framerate.num = 30;
	c->framerate.den = 1;
	c->pix_fmt = AV_PIX_FMT_RGB24;
	c->gop_size = 30*3;
	AVDictionary *opts = NULL;

	frame->format = c->pix_fmt;
	frame->width = c->width;
	frame->height = c->height;

	if (avcodec_open2(c, codec, &opts) < 0) {
		fprintf(stderr, "failed to open codec\n");
		return 1;
	}

	if (av_frame_get_buffer(frame, 0) < 0) {
		fprintf(stderr, "couldn't allocate frame data\n");
		return 1;
	}

	surface = cairo_image_surface_create(CAIRO_FORMAT_RGB24, 854, 480);
	cr = cairo_create(surface);

	cairo_set_font_face(cr, cface);
	cairo_set_font_size(cr, 32.0);
	if (av_frame_make_writable(frame) < 0) {
		fprintf(stderr, "couldn't make frame writeable\n");
		return 1;
	}

	if (luaL_dofile(L, "smallpond.lua")) {
		fprintf(stderr, "lua error: %s\n", lua_tostring(L, -1));
		return 1;
	}

	for (int i = 0; i < 30; i++) {
		/* fill with white */
		cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
		cairo_rectangle(cr, 0, 0, 854, 480);
		cairo_fill(cr);
		// draw frame
		lua_getglobal(L, "drawframe");
		lua_pushnumber(L, i);
		lua_call(L, 1, 0);

		cairo_surface_flush(surface);
		uint8_t *image_data = cairo_image_surface_get_data(surface);
		if (av_frame_make_writable(frame) < 0) {
			fprintf(stderr, "couldn't make frame writeable\n");
			return 1;
		}

		for (int y = 0; y < 480; y++) {
			for (int x = 0; x < 854; x++) {
				int srcoffset = cairo_image_surface_get_stride(surface) * y + 4*x;
				uint32_t val = *(uint32_t *)(image_data + srcoffset);
				// we are assuming RGB24 here
				int offset = y * frame->linesize[0] + 3*x;

				frame->data[0][offset] = (val >> 16) & 0xFF;
				frame->data[0][offset + 1] = (val >> 8) & 0xFF;
				frame->data[0][offset + 2] = val & 0xFF;
			}
		}

		fflush(stdout);
		frame->pts = i;
		putframe(c, frame, pkt, output);
	}

	putframe(c, NULL, pkt, output);
	fclose(output);

	avcodec_free_context(&c);
	av_frame_free(&frame);
	av_packet_free(&pkt);

	cairo_destroy(cr);
	cairo_surface_destroy(surface);
	lua_close(L);
}