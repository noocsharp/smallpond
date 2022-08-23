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

int
draw_line(lua_State *L)
{
	double x1 = lua_tonumber(L, -4);
	double y1 = lua_tonumber(L, -3);
	double x2 = lua_tonumber(L, -2);
	double y2 = lua_tonumber(L, -1);

	cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);

	cairo_move_to(cr, x1, y1);
	cairo_line_to(cr, x2, y2);
	cairo_set_line_width(cr, 1);
	cairo_stroke(cr);

	return 0;
}

int
draw_glyph(lua_State *L)
{
	unsigned int glyph = lua_tonumber(L, -3);
	double x = lua_tonumber(L, -2);
	double y = lua_tonumber(L, -1);

	int index = FT_Get_Char_Index(face, glyph);
	cairo_glyph_t treble_clef = {index, x, y};

	cairo_text_extents_t extents;
	cairo_glyph_extents(cr, &treble_clef, 1, &extents);

	cairo_set_font_face(cr, cface);
	cairo_set_font_size(cr, 32.0);

	cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);
	cairo_show_glyphs(cr, &treble_clef, 1);

	return 0;
}

int
main(int argc, char *argv[])
{
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);
	lua_pushcfunction(L, draw_glyph);
	lua_setglobal(L, "draw_glyph");
	lua_pushcfunction(L, draw_line);
	lua_setglobal(L, "draw_line");
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

	cairo_surface_t *surface = cairo_pdf_surface_create("out.pdf", 648, 864);
	cr = cairo_create(surface);

	if (luaL_dofile(L, "smallpond.lua")) {
		fprintf(stderr, "lua error: %s\n", lua_tostring(L, -1));
		return 1;
	}

	cairo_destroy(cr);
	cairo_surface_destroy(surface);
	lua_close(L);
}