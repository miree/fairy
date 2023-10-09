module asciirender;
@safe:

import std.range, std.algorithm, std.array, std.stdio;

enum Pixel : ubyte {
	empty = 0,
	white = 128,
	light = 129,
	gray  = 130,
	dark  = 131,
	black = 132,
	line  = 133
}
bool is_pixel(in ubyte p) {
	with(Pixel) {
		return (p == empty || p == white || p == light || p == gray || p == dark || p == black || p == line);
	}
}
wchar render_pixel(in Pixel p) {
	with(Pixel) switch(p) {
		case empty: return ('·');
		case white: return (' ');
		case light: return ('░');
		case gray:  return ('▒');
		case dark:  return ('▓');
		case black: return ('█');
		case line:  return ('█');
		default: return cast(wchar)p;
	}
}
Pixel blend_pixels(in Pixel p1, in Pixel p2) {
	with(Pixel) {
		if (!p1.is_pixel) return p1; // non-pixel wins
		if (!p2.is_pixel) return p2;
		if (p1 == line)   return p1;
		if (p2 == line)   return p2;

		int u1 = (p1==empty)?white:p1;
		int u2 = (p2==empty)?white:p2;
		
		return cast(Pixel)((u1+u2+1)/2);
	}
}
auto convert_direct(in ubyte[][] pixels) {
	if (pixels is null || pixels[0] is null) {
		throw new Exception("pixels invalid");	
	}
	wchar cp(in ubyte ch){
		return render_pixel(cast(Pixel)ch);
	}
	return pixels.map!(line=>line.map!(x=>cp(x))).joiner([cast(ubyte)'\n']);
}

auto convert_twolines(in ubyte[][] pixels) {
	if (pixels is null || pixels[0] is null) {
		throw new Exception("pixels invalid");	
	}

	wchar cp(T)(T tuple) {
		auto top = cast(Pixel)tuple[0];
		auto bot = cast(Pixel)tuple[1];
		with(Pixel) {
			if (!top.is_pixel) return top;
			if (!bot.is_pixel) return bot;
			if (top != line  && bot != line ) return render_pixel(blend_pixels(top,bot));
			if (top != line  && bot == line ) return ('▄');
			if (top == line  && bot != line ) return ('▀');
			if (top == line  && bot == line ) return ('█');
			return (' ');
		}
	}
	auto linepairs = zip(pixels.stride(2), pixels.drop(1).stride(2));
	return linepairs.map!(pair=>zip(pair[0],pair[1]).map!(t=>cp(t))).joiner([cast(ubyte)'\n']);
}

auto convert_quadrants(in ubyte[][] pixels) {
	if (pixels is null || pixels[0] is null) {
		throw new Exception("pixels invalid");	
	}
	wchar cp(T)(T tuple) {
		// quadrants 0 1
		//           2 3
		auto q0 = cast(Pixel)tuple[0];
		auto q1 = cast(Pixel)tuple[1];
		auto q2 = cast(Pixel)tuple[2];
		auto q3 = cast(Pixel)tuple[3];
		with(Pixel) {
			if (!q0.is_pixel) return q0;
			if (!q1.is_pixel) return q1;
			if (!q2.is_pixel) return q2;
			if (!q3.is_pixel) return q3;

			if (q0 != line && q1 != line && q2 != line && q3 != line) return render_pixel(blend_pixels(blend_pixels(q0,q1),blend_pixels(q2,q3)));

			if (q0 == line && q1 == line && q2 == line && q3 == line) return  ('█');
			if (q0 != line && q1 != line && q2 == line && q3 == line) return  ('▄');
			if (q0 == line && q1 == line && q2 != line && q3 != line) return  ('▀');
			if (q0 == line && q1 != line && q2 == line && q3 != line) return  ('▌');
			if (q0 != line && q1 == line && q2 != line && q3 == line) return  ('▐');

			if (q0 == line && q1 != line && q2 != line && q3 == line) return  ('▚');
			if (q0 != line && q1 == line && q2 == line && q3 != line) return  ('▞');

			if (q0 != line && q1 != line && q2 == line && q3 != line) return  ('▖');
			if (q0 != line && q1 != line && q2 != line && q3 == line) return  ('▗');
			if (q0 == line && q1 != line && q2 != line && q3 != line) return  ('▘');
			if (q0 != line && q1 == line && q2 != line && q3 != line) return  ('▝');

			if (q0 == line && q1 != line && q2 == line && q3 == line) return  ('▙');
			if (q0 == line && q1 == line && q2 == line && q3 != line) return  ('▛');
			if (q0 == line && q1 == line && q2 != line && q3 == line) return  ('▜');
			if (q0 != line && q1 == line && q2 == line && q3 == line) return  ('▟');

			return (' ');
		}
	}
	auto linepairs = zip(pixels.stride(2), pixels.drop(1).stride(2));
	return linepairs.map!(pair=>zip(pair[0].stride(2), pair[0].drop(1).stride(2),
		                            pair[1].stride(2), pair[1].drop(1).stride(2)).map!(t=>cp(t))).joiner([cast(ubyte)'\n']);

}

import graphics, ui;

//class TerminalWindow: AsciiRender, GuiWindow {
//private:
//	DrawArea area;
//	string name;
//public:


//	this(long w, long h, string window_name) {
//		if (w < 0) w = 80;
//		if (h < 0) h = 40;
//		import std.stdio;
//		writeln("TerminalWindow w,h = ",w,",",h);
//		super(w,h);
//		area.resize(cast(int)w,cast(int)h);
//		area.drawer = this;
//		name = window_name;
//	}


//	//void set_autoscale_x(bool active) {
//	//	area.autoscale_x = active;
//	//	if (active) need_redraw();
//	//}
//	//void set_autoscale_y(bool active) {
//	//	area.autoscale_y = active;
//	//	if (active) need_redraw();
//	//}
//	//void set_autoscale_z(bool active) {
//	//	area.autoscale_z = active;
//	//	if (active) need_redraw();
//	//}
//	override void close_window() {
//		gui_windows.remove(name);
//	}
//	override void window_font_size(int size) {
//		// nothing;
//	}
//	override void area_changed() {
//		// nothing;
//	}
//	import item;
//	override void add_item(string item_name, Item item) {

//	}
//	override void remove_item(string item_name) {

//	}
//	override void update_items() {
//	}
//	override void show_visualizer(string item_name) {
//	}
//	override void hide_visualizer(string item_name) {
//	}
//	//void set_overlay(bool overlay) {
//	//	area.overlay = overlay;
//	//	need_redraw();
//	//}
//	//void set_rows(int rows) {
//	//	area.row_major = false;
//	//	area.columns_or_rows = rows;
//	//	need_redraw();
//	//}
//	//void set_columns(int columns) {
//	//	area.row_major = true;
//	//	area.columns_or_rows = columns;
//	//	need_redraw();
//	//}

//	override Geometry get_geometry() {
//		GuiWindow.Geometry result;
//		result.x = 0;
//		result.h = 0;
//		result.w = cast(int)super.w;
//		result.h = cast(int)super.h;
//		return result;
//	}
//	override int get_win_x() {
//		return 0;
//	}
//	override int get_win_y() {
//		return 0;
//	}
//	override int get_win_w() {
//		return cast(int)super.w;
//	}
//	override int get_win_h() {
//		return cast(int)super.h;
//	}
//	override bool get_win_maximized() {
//		return false;
//	}
//	override DrawArea* get_draw_area() {
//		return &area;
//	}	

//	override void need_redraw() {
//		//area.draw_grid_vertical = false;
//		//area.draw_grid_horizontal = false;
//		area.draw_content();
//		super.need_redraw();
//	}

//	override void redraw() {
//		need_redraw();
//	}

//}

import graphics;
class AsciiRender: BackendInterface {
private:
	ubyte[][] bitmap;
	long w, h;
	long clip_x1, clip_x2, clip_y1, clip_y2;
	Mode output_mode;

	bool draw_rectangle;
	double rect_x1,  rect_x2,  rect_y1,  rect_y2;
	long   rect_x1i, rect_x2i, rect_y1i, rect_y2i;
	ubyte color_setting = 0;

public:



	enum Mode {
		single_pixel,
		double_pixel,
		quad_pixel
	}
	this(long width=160, long height=80, Mode mode = Mode.quad_pixel) {
		bitmap = iota(height).map!(x=>new ubyte[cast(uint)width]).array;
		w = width;
		h = height;
		output_mode = mode;
		reset_clip();
	}

	override void init() {

	}
	override void finish() {

	}

	override void reset_clip() {
		set_clip(0,0,w,h);
	}
	override void set_clip(double x1, double y1, double x2, double y2) {
		clip_x1 = cast(long)x1;
		clip_y1 = cast(long)y1;
		clip_x2 = cast(long)x2;
		clip_y2 = cast(long)y2;
		if (clip_x1 > clip_x2) swap(clip_x1, clip_x2);
		if (clip_y1 > clip_y2) swap(clip_y1, clip_y2);
	}

	override void clear(double r, double g, double b) {
		bitmap.each!((ref line){line[]=0;});
	}
	override void set_color(double r, double g, double b) {
		double brightness = (r+g+b)/3;
		color_setting = cast(ubyte)(133-5.0*brightness);
		if (color_setting > 132) color_setting = 132;
		if (color_setting < 128) color_setting = 128;
	}
	override void set_line_width(double w) {
		// nothing
	}
	override double get_line_width() {
		return 0.1;
	}
	override void vertical_line(double x, double y1, double y2) {
		import std.math;
		long y1i = cast(long)round(y1);
		long y2i = cast(long)round(y2);
		long xi  = cast(long)round(x);
		if (xi < clip_x1 || xi >= clip_x2) return;
		if (y2i<y1i) swap(y1i,y2i);
		if (y2i<0) return;
		if (y1i>h) return;
		y1i = max(y1i,clip_y1);
		y2i = min(y2i+1,clip_y2);
		foreach(yi; y1i..y2i) {
			bitmap[cast(uint)yi][cast(uint)xi] = Pixel.line;
		}
	}
	override void line(double x1, double y1, double x2, double y2) {
		import std.stdio;
		write("line ");
		if (cast(int)x1==cast(int)x2 && cast(int)y1==cast(int)y2) {
			if (cast(int)x1<0) return;
			if (cast(int)x1>=w) return;
			if (cast(int)y1<0) return;
			if (cast(int)y1>=h) return;
			bitmap[cast(uint)y1][cast(uint)x1] = Pixel.line;
			return;
		}
		if (x1==x2) {
			writeln("vertical");
			vertical_line(x1,y1,y2);
			return;
		}
		if (y1==y2) {
			writeln("horizontal");
			horizontal_line(y1,x1,x2);
			return;
		}
		writeln("general");
		import std.math;
		bool x_iteration = abs(x2-x1) > abs(y2-y1);
		int dx = (x2>x1)?1:-1;
		int dy = (y2>y1)?1:-1;
		int i1 = x_iteration?cast(int)x1:cast(int)y1;
		int i2 = x_iteration?cast(int)x2:cast(int)y2;
		int di = x_iteration?dx:dy;
		double j1 = x_iteration?cast(int)y1:cast(int)x1;
		double j2 = x_iteration?cast(int)y2:cast(int)x2;
		int i = i1;
		for (;;) {
			int j = cast(int)round(j1+(j2-j1)*1.0*(i-i1)/(i2-i1));

			if (x_iteration) {
				if (i >= 0 && i < w && j >= 0 && j < h) {
					bitmap[j][i] = Pixel.line;
				}
			} else {
				if (i >= 0 && i < h && j >= 0 && j < w) {
					bitmap[i][j] = Pixel.line;
				}
			}
			if (i == i2) break;
			i += di;
		}
	}
	override void horizontal_line(double y, double x1, double x2) {
		import std.math;
		long x1i = cast(long)round(x1);
		long x2i = cast(long)round(x2);
		long yi  = cast(long)round(y);
		if (yi < clip_y1 || yi >= clip_y2) return;
		if (x2i <  x1i) swap(x1i,x2i);
		if (x2i <  clip_x1) return;
		if (x1i >= clip_x2) return;
		x1i = max(x1i  ,clip_x1);
		x2i = min(x2i+1,clip_x2);
		foreach(xi; x1i..x2i) {
			bitmap[cast(uint)yi][cast(uint)xi] = Pixel.line;
		}
	}
	override void rectangle(double x1, double y1, double x2, double y2) {
		rect_x1  = x1;
		rect_y1  = y1;
		rect_x2  = x2;
		rect_y2  = y2;
		rect_x1i = cast(long)rect_x1;
		rect_y1i = cast(long)rect_y1;
		rect_x2i = cast(long)rect_x2;
		rect_y2i = cast(long)rect_y2;
		if (rect_x1i > rect_x2i) swap(rect_x1i, rect_x2i);
		if (rect_x2i <  clip_x1) return;
		if (rect_x1i >= clip_x2) return;
		rect_x1i = max(rect_x1i  , clip_x1);
		rect_x2i = min(rect_x2i+1, clip_x2);

		if (rect_y1i > rect_y2i) swap(rect_y1i, rect_y2i);
		if (rect_y2i <  clip_y1) return;
		if (rect_y1i >= clip_y2) return;
		rect_y1i = max(rect_y1i  , clip_y1);
		rect_y2i = min(rect_y2i+1, clip_y2);

		draw_rectangle = true;
	}
	override void fill() {
		if (draw_rectangle) {
			foreach(y; rect_y1i..rect_y2i) bitmap[cast(uint)y][cast(uint)rect_x1i..cast(uint)rect_x2i] = color_setting;
			draw_rectangle = false;
		}
	}
	override void stroke() {
		if (draw_rectangle) {
			horizontal_line(rect_y1, rect_x1, rect_x2);
			horizontal_line(rect_y2, rect_x1, rect_x2);
			vertical_line(rect_x1, rect_y1, rect_y2);
			vertical_line(rect_x2, rect_y1, rect_y2);
			draw_rectangle = false;
		}
	}

	struct UserBitmap {
		int w, h;
		uint[] data;
		this(int width, int height) {
			w = width;
			h = height;
			data = new uint[](w*h);
		}
	}
	UserBitmap[ulong] user_bitmaps;
	ulong user_bitmap_counter = 0;

	@trusted
	override ulong    create_bitmap(int w, int h) {
		import std.stdio;
		writeln("create_bitmap ", w, " ", h);
		++user_bitmap_counter;
		user_bitmaps[user_bitmap_counter] = UserBitmap(w,h);
		return user_bitmap_counter;
	}
	override void   destroy_bitmap(ulong handle) {
		user_bitmaps.remove(handle);
	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		return user_bitmaps[handle].data;
	}
	override void    access_bitmap_done(ulong handle) {
		// nothing to do
	}
	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                                    double dx, double dy, double dw, double dh) {
		writeln("draw_bitmap ", sx, " ", sy, " ", sw, " ", sh, "   ", dx, " ", dy, " ", dw, " ", dh);

		import std.math;
		int x1, x2, deltax;
		bool x_source_iteration;
		if (abs(sw) > abs(dw)) {
			x_source_iteration = true;
			x1 = cast(int)sx;
			x2 = x1+cast(int)sw;
		} else {
			x_source_iteration = false;
			x1 = cast(int)dx;
			x2 = x1+cast(int)dw;
		}
		deltax = (x2>x1)?1:-1;

		int y1, y2, deltay;
		bool y_source_iteration;
		if (abs(sh) > abs(dh)) {
			y_source_iteration = true;
			y1 = cast(int)sy;
			y2 = cast(int)sy+cast(int)sh;
		} else {
			y_source_iteration = false;
			y1 = cast(int)dy;
			y2 = cast(int)dy+cast(int)dh;
		}
		deltay = (y2>y1)?1:-1;
		UserBitmap* ubmp = &user_bitmaps[handle];
		import std.stdio;
		//writeln("x1=",x1," x2=",x2, " deltax=", deltax, "  y1=",y1, " y2=",y2, " deltay=", deltay);
		int x = x1;
		for(;;) {
			int y = y1;
			for(;;) {
				int sourcex, sourcey;
				int destx  , desty;
				if (x_source_iteration) {
					sourcex = x;
					destx = cast(int)(dx+dw*1.0*(x-x1)/(x2-x1));
				} else {
					destx = x;
					sourcex = cast(int)(sx+sw*1.0*(x-x1)/(x2-x1));
				}
				if (y_source_iteration) {
					sourcey = y;
					desty = cast(int)(dy+dh*1.0*(y-y1)/(y2-y1));
				} else {
					desty = y;
					sourcey = cast(int)(sy+sh*1.0*(y-y1)/(y2-y1));
				}
				//writeln("sx=",sourcex, " sy=", sourcey, "  dx=",destx, " dy=", desty);
				if (sourcex >= 0 && sourcex < ubmp.w &&
					sourcey >= 0 && sourcey < ubmp.h &&
					destx >= 0 && destx < w &&
					desty >= 0 && desty < h) {

					uint source_color = ubmp.data[sourcex+ubmp.w*sourcey];
					//writeln("source_color=",source_color);
					uint a = 0xff & (source_color >> 24);
					uint r = 0xff & (source_color >> 16);
					uint g = 0xff & (source_color >>  8);
					uint b = 0xff & (source_color >>  0);
					double brightness = (r+g+b)/3.0/255.0;
					//writeln("brightness=",brightness, "a=", a, " r=",r, " g=",g, " b=",b);
					ubyte pixel = cast(ubyte)(133-5.0*brightness);
					if (pixel < 128) pixel = 128;
					if (pixel > 132) pixel = 132;
					bitmap[desty][destx] = pixel;
					if (a <= 128) {
						bitmap[desty][destx] = 0;
					}

				}
				if (y == y2) break;
				y += deltay;
			} 
			if (x == x2) break;
			x += deltax;
		}
		writeln("draw_bitmap done");
	}

	override void set_text_size(int s) {
		// nothing
	}
	override void text_extent(string str, out double w, out double h) {
		with(Mode) final switch(output_mode) {
			case single_pixel: w=str.length;   h=1; break;
			case double_pixel: w=str.length;   h=2; break;
			case quad_pixel:   w=str.length*2; h=2; break;
		}
	}
	override void text(double x, double y, string str) {
		long dx;
		with(Mode) final switch(output_mode) {
			case single_pixel: y-=1; dx=1; break;
			case double_pixel: y-=2; dx=1; break;
			case quad_pixel:   y-=2; dx=2; break;
		}
		long xi = cast(long)x;
		long yi = cast(long)y;
		if (yi <  clip_y1) return;
		if (yi >= clip_y2) return;
		foreach(idx,ch;str) {
			auto x_pos = xi+idx*dx;
			if (x_pos >= clip_x1 && x_pos < clip_x2 ) {
				bitmap[cast(uint)yi][cast(uint)x_pos] = cast(ubyte)ch;
			}
		}
	}

	string render() {
		import std.conv;
		with(Mode) final switch(output_mode) {
			case single_pixel: return bitmap.convert_direct.to!string; 
			case double_pixel: return bitmap.convert_twolines.to!string; 
			case quad_pixel:   return bitmap.convert_quadrants.to!string; 
		}
	}
	override void need_redraw() {
		render.writeln;
	}
	override void show_mouse_pos(double x, double y, double z) {

	}
	override void show_value(double value, string itemname) {

	}
}


//void main() {
//	int width = 80;
//	int height = 40;
//	auto screen = iota(height).map!(x=>new ubyte[width]).array;
//	//screen.each!((ref line){line[] = ' ';});
//	screen[1][]=Pixel.line;
//	screen[2][]=Pixel.black;
//	screen[5][]=Pixel.line;
//	screen[7][]=Pixel.light;
//	screen[8][]=Pixel.light;
//	screen[9][]=Pixel.gray;
//	screen[10][]=Pixel.dark;
//	screen[11][]=Pixel.black;
//	screen[12][]=Pixel.line;
//	screen[18][]=Pixel.gray;
//	screen[19][]=Pixel.gray;
//	foreach(xy; 0..height) {
//		screen[xy][xy]=Pixel.line;
//	}
//	screen.each!((ref line) {line[9]=Pixel.line;});
//	screen[10][40..50] = 'x';
//	screen.convert_direct.writeln;
//	writeln;
//	screen.convert_twolines.writeln;
//	writeln;
//	screen.convert_quadrants.writeln;
//}