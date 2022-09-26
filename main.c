#include <stdio.h>

#include <ft2build.h>
#include FT_FREETYPE_H

#include <cairo-ft.h>
#include <cairo-pdf.h>
#include <cairo.h>

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

	cairo_destroy(cr);
	cairo_surface_destroy(surface);

	surface = cairo_pdf_surface_create("out.pdf", width, height);
	cr = cairo_create(surface);

	cairo_set_font_face(cr, cface);
	cairo_set_font_size(cr, 32.0);

	return 0;
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

	surface = cairo_image_surface_create (CAIRO_FORMAT_A8, 1, 1);
	cr = cairo_create(surface);

	cairo_set_font_face(cr, cface);
	cairo_set_font_size(cr, 32.0);
	if (luaL_dofile(L, "smallpond.lua")) {
		fprintf(stderr, "lua error: %s\n", lua_tostring(L, -1));
		return 1;
	}

	cairo_destroy(cr);
	cairo_surface_destroy(surface);
	lua_close(L);
}