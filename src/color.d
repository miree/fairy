//    Fairy: Flexible Analysis of Ionizing Radiation Yields
//    Copyright (C) 2019-2026 Michael Reese

//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.

//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.

//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <https://www.gnu.org/licenses/>.

module color;
@safe:

uint mix(uint a, uint b, float d) {
	ubyte a_r = (a>>16) & 0xff;
	ubyte a_g = (a>> 8) & 0xff;
	ubyte a_b = (a>> 0) & 0xff;
	ubyte b_r = (b>>16) & 0xff;
	ubyte b_g = (b>> 8) & 0xff;
	ubyte b_b = (b>> 0) & 0xff;

	if (d < 0.0) d = 0.0;
	if (d > 1.0) d = 1.0;

	uint R = cast(uint)(b_r * d + a_r * (1.0 - d));
	uint G = cast(uint)(b_g * d + a_g * (1.0 - d));
	uint B = cast(uint)(b_b * d + a_b * (1.0 - d));
	return 0xff000000 | (R<<16) | (G<<8) | (B<<0);
}

//////////////////////////////////////////////////////////////////////////
// 2D-histogram color palettes: one function per palette (rather than one
// function with a runtime branch on which palette is selected), dispatched
// through a function pointer table below -- this keeps the hot per-bin call
// in Hist2Visualizer.generate_rgb_data() to a single indirect call instead
// of a branch/switch evaluated for every single bin.
//////////////////////////////////////////////////////////////////////////

void get_rgb_grayscale(double c, out uint rgb) {
	if (c>1.0) c = 1.0;
	if (c<0.0) c = 0.0;
	uint i = cast(uint)(255*c);
	rgb = 0xff000000 | (i<<16) | (i<<8) | (i<<0);
}

void get_rgb_bluish(double c, out uint rgb) {
	rgb = 0xff000000;
	if (c>1.0) c = 1.0;
	if (c<0.0) c = 0.0;
	c *= 3;
	if (c < 1.0) { // black to blue
		rgb |= cast(uint)(0xff*c);
		return;
	}
	rgb = 0xff0000ff;
	if (c < 2.0)  { // blue to lightblue
		c -= 1.0;
		rgb |=  (cast(uint)(0x0000ff00*c) & 0x0000ff00) ;
		return;
	}
	rgb = 0xff00ffff; // lightblue to white
	c -= 2.0;
	rgb |= cast(uint)(0xff*c)<<16;
}

void get_rgb_rainbow(double c, out uint rgb) {
	// rainbow color blue green yellow red
	rgb = 0xff000000;
	if (c>1.0) c = 1.0;
	if (c<0.0) c = 0.0;
	c *= 7;

	if (c < 3.0) { // blue to green
		c /= 3;
		rgb |= (cast(uint)(0xff*(1.0-c)) | (cast(uint)(0xff*c)<<8));
		return;
	}
	if (c < 4.0)  { // green to yellow
		c -= 3.0;
		if (c>1.0) c = 1.0;
		if (c<0.0) c = 0.0;
		rgb |= (0xff00 | (cast(uint)(0xff*c)<<16));
		return;
	}
	if (c < 7.0)  { // yellow to red
		c -= 4.0;
		c /= 3;
		if (c>1.0) c = 1.0;
		if (c<0.0) c = 0.0;
		rgb |= (cast(uint)(0xff*(1.0-c))<<8 | 0xff0000);
		return;
	}
	rgb |= 0xff0000;
}

void get_rgb_viridis(double c, out uint rgb) {
	if (c>1.0) c = 1.0;
	if (c<0.0) c = 0.0;
	c *= 5;
	import std.math;
	uint ca = cast(uint)floor(c);
	uint cb = ca+1;
	float delta = c-ca;
	uint[6] supports = [ 0xff440154,
	                     0xff414487,
	                     0xff2a788e,
	                     0xff22a884,
	                     0xff7ad151,
	                     0xfffde725 ];

	if (ca > 5) ca = 5;
	if (cb > 5) cb = 5;
	rgb = mix(supports[ca],supports[cb],delta);
}

void get_rgb_hot(double c, out uint rgb) {
	if (c>1.0) c = 1.0;
	if (c<0.0) c = 0.0;
	c *= 2;
	import std.math;
	uint ca = cast(uint)floor(c);
	uint cb = ca+1;
	float delta = c-ca;
	uint[3] supports = [ 0xff000000,
	                     0xffff0000,
	                     0xffffff00 ];

	if (ca > 2) ca = 2;
	if (cb > 2) cb = 2;
	rgb = mix(supports[ca],supports[cb],delta);
}


enum Palette { viridis, grayscale, bluish, rainbow, hot }

alias PaletteFunc = void function(double, out uint) @safe;

immutable PaletteFunc[5] palette_functions = [
	&get_rgb_viridis,
	&get_rgb_grayscale,
	&get_rgb_bluish,
	&get_rgb_rainbow,
	&get_rgb_hot,
];
immutable string[5] palette_names = ["viridis", "grayscale", "bluish", "rainbow", "hot"];

// maps c (expected in [0,1]) to an rgb color using the given 2D-histogram palette
void get_rgb(double c, Palette palette, out uint rgb) {
	palette_functions[palette](c, rgb);
}

Palette palette_from_name(string name) {
	foreach(i, n; palette_names) if (n == name) return cast(Palette)i;
	import std.array : join;
	throw new Exception("unknown color palette \"" ~ name ~ "\" (available: " ~ palette_names[].join(", ") ~ ")");
}

//////////////////////////////////////////////////////////////////////////
// 1D-histogram line colors: a small, fixed, user-selectable set. The fill
// color used underneath a filled 1D-histogram is normally derived from the
// selected line color (see brighten() below), not separately selectable --
// except "teal", which restores the original hardcoded line+fill pair this
// feature replaced (a purple line with an unrelated teal fill, not a
// brightened version of its own line color), for anyone who wants that
// exact look back.
//////////////////////////////////////////////////////////////////////////

enum LineColor { blue, red, green, purple, yellow, black, teal }

immutable uint[7] line_colors = [
	0xff1f77b4, // blue
	0xffd62728, // red
	0xff2ca02c, // green
	0xff9467bd, // purple
	0xffbcbd22, // yellow
	0xff000000, // black
	0xff440154, // teal (the original hardcoded line color)
];
immutable string[7] line_color_names = ["blue", "red", "green", "purple", "yellow", "black", "teal"];

uint line_color(LineColor c) {
	return line_colors[c];
}

// a brighter version of rgb, used as the default fill color underneath a line color's filled histogram
uint brighten(uint rgb, double amount = 0.5) {
	return mix(rgb, 0xffffffff, cast(float)amount);
}

// the fill color used underneath a filled 1D histogram for the given line color
uint fill_color(LineColor c) {
	if (c == LineColor.teal) return 0xff2a788e; // the original hardcoded fill color
	return brighten(line_color(c));
}

LineColor line_color_from_name(string name) {
	foreach(i, n; line_color_names) if (n == name) return cast(LineColor)i;
	import std.array : join;
	throw new Exception("unknown line color \"" ~ name ~ "\" (available: " ~ line_color_names[].join(", ") ~ ")");
}
