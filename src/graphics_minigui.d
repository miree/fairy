module graphics_minigui;
@trusted:

import arsd.minigui;
import graphics;

class MiniGui : Gui {


	@trusted:
	override void add_window(string name, ref CanvasProperties canvas) {
		new MainWindow(name,&canvas);
	}
	override void close_window(string name) {
		auto window = MainWindow.main_windows[name];
		MainWindow.main_windows.remove(name);
		window.window.close();
	}
	override void redraw_window(string name) {
		MainWindow.main_windows[name].draw_area.need_redraw();
	}
	override void save_window(string name) {
		auto window = MainWindow.main_windows[name];
		auto point = window.window.globalCoordinates();
		window.canvas.xpos = point.x; 
		window.canvas.ypos = point.y; 
	}
	override void remove_item(string name) {
	}
	override void add_item(string name) {
	}
	override void update_from_canvas(string name) {
	}
	override void loop() {
		import fairy;
		EventLoop main_event_loop = EventLoop.get;

		foreach(name, ref canvas; session.windows) {
			add_window(name, canvas);
		}

		auto timer = new Timer(10, delegate void (){

			foreach(window; MainWindow.main_windows) {
				import ui;
				if (window.canvas.autorefresh) {
					winrefresh(window.name);
				}
			}

			import std.stdio;
			if (fairy.iterate(0)) {
				import std.stdio;
				stdout.write("fairy> ");
				stdout.flush();
			}

			if (!fairy.running) { // quit
				foreach(name; MainWindow.main_windows.byKey) {
					save_window(name);
				}
				main_event_loop.exit;
			}

		});

		main_event_loop.run;
	}

}

class MainWindow
{
private:
	static MainWindow[string] main_windows;

	CanvasProperties *canvas;
	string name;

	SimpleWindow simple;
	Window       window;


	//Button button;

	DrawArea draw_area;

public:
	@trusted
	this(string canvas_name, CanvasProperties *canvas_pointer) {
		import std.stdio;
		writeln("new minigui window with name ", canvas_name);
		assert(canvas_pointer !is null);
		canvas = canvas_pointer;
		name = canvas_name;

		simple = new SimpleWindow(canvas.width, canvas.height, canvas_name, OpenGlOptions.no, Resizability.allowResizing);
		window = new Window(simple);


		if (canvas.xpos >= 0 && canvas.ypos >= 0) {
			simple.move(canvas.xpos-1, canvas.ypos-24);

			//auto point = window.globalCoordinates();
			//int dx = point.x-canvas.xpos;
			//int dy = point.y-canvas.ypos;

			//simple.move(canvas.xpos+dx, canvas.ypos+dy);

		}

		//button = new Button(name, window);
		draw_area = new DrawArea(canvas_name, canvas_pointer, window);

		simple.onClosing = delegate () { 
			import fairy;
			main_windows.remove(name);
			session.windows.remove(name);
		};

		auto default_windowResized = simple.windowResized;
		simple.windowResized = delegate(int width, int height) {
			if ((name in main_windows) !is null) {
				main_windows[name].canvas.width = width;
				main_windows[name].canvas.height = height;
			}
			default_windowResized(width,height);
		};

		main_windows[name] = this;
	}
}


class DrawArea : Widget, BackendInterface 
{
	import arsd.ttf;
	CanvasProperties* canvas;
	string name;
	CanvasPainter painter;
	double line_width = 1;
	Color color;

	double rect_x1, rect_x2, rect_y1, rect_y2;
	bool rect_valid = false;

	bool first_draw = true;

	WidgetPainter *widget_painter;

	TtfFont font;
	int text_size = 20;

	struct MiniImage {
		int w;
		int h;
		uint[] argb_data;
	}

	MiniImage[ulong] images;
	ulong image_counter = 0;
	ubyte[] accessed_image;

	this(string window_name, CanvasProperties *canvas_ptr, Widget parent) {
		first_draw = true;
		canvas = canvas_ptr;
		name = window_name;
		painter = CanvasPainter(canvas, this);
		super(parent);
		import std.file;
		version(windows) {
			font.load(cast(ubyte[])std.file.read("C:\\Windows\\Fonts\\verdana.ttf"));
		}
		else {
			font.load(cast(ubyte[])std.file.read("/usr/share/fonts/TTF/DejaVuSans.ttf"));
		}
	}


	override void defaultEventHandler_mousedown(MouseDownEvent event) {
		if (event.button == MouseButton.left)    painter.left_button_pressed  (1, event.clientX, event.clientY);
		if (event.button == MouseButton.middle)  painter.mid_button_pressed   (1, event.clientX, event.clientY, this);
		if (event.button == MouseButton.right)   painter.right_button_pressed (1, event.clientX, event.clientY);
		if (event.button == MouseButton.wheelUp)   painter.scroll(0,-1);
		if (event.button == MouseButton.wheelDown) painter.scroll(0, 1);

	}
	override void defaultEventHandler_mouseup(MouseUpEvent event) {
		if (event.button == MouseButton.left)    painter.left_button_released (1, event.clientX, event.clientY);
		if (event.button == MouseButton.middle)  painter.mid_button_released  (1, event.clientX, event.clientY);
		if (event.button == MouseButton.right)   painter.right_button_released(1, event.clientX, event.clientY);
	}


	override void defaultEventHandler_mousemove(MouseMoveEvent event) {
		painter.mouse_motion(event.clientX, event.clientY, this);
	}

	override void defaultEventHandler_keydown(KeyDownEvent event) {
		import ui;
		switch(cast(char)event.key) {
			case Key.N1: .. case Key.N9:
				if (canvas.display_mode == DisplayMode.rows)    rows(name, event.key-'0');
				if (canvas.display_mode == DisplayMode.columns) columns(name, event.key-'0');
			break;
			case Key.U: winrefresh(name); break;
			case Key.P: winpoll(name); break;
			case Key.Q: winzoom(name,1*1.2); break;
			case Key.E: winzoom(name,1/1.1666666666); break;
			case Key.A: winmove(name,'x',-0.2); break;
			case Key.D: winmove(name,'x',+0.2); break;
			case Key.S: winmove(name,'y',-0.2); break;
			case Key.W: winmove(name,'y',+0.2); break;
			case Key.O: overlay(name); break;
			case Key.B: colorbar(name); break;
			case Key.G: grid(name,"top","toggle"); break;
			case Key.C: columns(name, canvas.columns_or_rows); break;
			case Key.R: rows   (name, canvas.columns_or_rows); break;
			case Key.X: autoscale  (name, 'x', "toggle");  break;
			case Key.Y: autoscale  (name, 'y', "toggle");  break;
			case Key.Z: autoscale  (name, 'z', "toggle");  break;
			case Key.L: logscale(name, canvas.dim==2?'z':'y', "toggle");  break;
			case Key.F: winfit(name);  break;
			default: {}
		}

	}


	override Rectangle paintContent(WidgetPainter w_painter, const Rectangle bounds) {
		//if (first_draw) { // correct window position for decoration
		//	auto point = globalCoordinates();
		//	int delta_x = point.x - canvas.xpos;
		//	int delta_y = point.y - canvas.ypos;
		//	MainWindow.main_windows[name].simple.move(canvas.xpos-delta_x, canvas.ypos-delta_y);
		//	first_draw = false;
		//}

		widget_painter = &w_painter;

		painter.draw_content();

		widget_painter = null;
		return bounds;
	}





	override bool inverted_y_direction() {
		return true;
	} // true if the y-coordinates go from top to bottom
	override bool text_with_border() {
		return false;
	} // true if black text should be rendered with a white border

	override void initialize() {

	}   // must be called before anything else
	override void finish() {

	} // must be called after anything else

	override void reset_clip() {

	}
	override void set_clip(double x1, double y1, double x2, double y2) {
		widget_painter.setClipRectangle(Point(cast(int)x1,cast(int)y1),cast(int)(x2-x1),cast(int)(y2-y1));
	}

	override void clear(double r, double g, double b) {

	}
	override void set_color(double r, double g, double b) {
		color = Color(cast(int)(r*255), cast(int)(g*255), cast(int)(b*255), 255);
		widget_painter.pen = Pen(color, cast(int)line_width, Pen.Style.Solid);
	}
	
	// line drawing
	override void set_line_width(double w) {
		line_width = w;
		widget_painter.pen = Pen(color, cast(int)line_width, Pen.Style.Solid);
	}
	override double get_line_width() {
		return line_width;
	}
	override void vertical_line(double xd, double y1d, double y2d) {
		if (y1d < y2d) {
			y1d+=line_width/2;
			y2d-=line_width/2;
		} else {
			y2d+=line_width/2;
			y1d-=line_width/2;
		}
		int x = cast(int)(xd+0.5);
		int y1 = cast(int)(y1d+0.5);
		int y2 = cast(int)(y2d+0.5);
		widget_painter.drawLine(Point(x,y1),Point(x,y2));
	}
	override void horizontal_line(double yd, double x1d, double x2d) {
		int y = cast(int)(yd+0.5);
		int x1 = cast(int)(x1d+0.5);
		int x2 = cast(int)(x2d+0.5);
		widget_painter.drawLine(Point(x1,y),Point(x2,y));
	}
	override void line(double x1d, double y1d, double x2d, double y2d) {
		int x1 = cast(int)(x1d+0.5);
		int y1 = cast(int)(y1d+0.5);
		int x2 = cast(int)(x2d+0.5);
		int y2 = cast(int)(y2d+0.5);
		widget_painter.drawLine(Point(x1,y1),Point(x2,y2));
	}
	override void rectangle(double x1d, double y1d, double x2d, double y2d) {
		rect_x1 = x1d;
		rect_x2 = x2d;
		rect_y1 = y1d;
		rect_y2 = y2d;
		rect_valid = true;
	}
	override void fill() {
		if (!rect_valid) return;
		import std.algorithm;
		if (rect_x1 > rect_x2) swap(rect_x1, rect_x2);
		if (rect_y1 > rect_y2) swap(rect_y1, rect_y2);
		int x1 = cast(int)(rect_x1);
		int y1 = cast(int)(rect_y1);
		int wx = cast(int)(rect_x2-rect_x1+1);
		int wy = cast(int)(rect_y2-rect_y1+1);
		widget_painter.outlineColor = color;
		widget_painter.fillColor = color;
		widget_painter.drawRectangle(Point(x1,y1),wx,wy);
		rect_valid = false;
	}
	override void stroke() {
		if (!rect_valid) return;
		int x1 = cast(int)(rect_x1+0.5);
		int y1 = cast(int)(rect_y1+0.5);
		int x2 = cast(int)(rect_x2+0.5);
		int y2 = cast(int)(rect_y2+0.5);
		widget_painter.drawLine(Point(x1,y1),Point(x2,y1));
		widget_painter.drawLine(Point(x1,y2),Point(x2,y2));
		widget_painter.drawLine(Point(x1,y1),Point(x1,y2));
		widget_painter.drawLine(Point(x2,y1),Point(x2,y2));
		rect_valid = false;
		// nothing
	}

	// bitmap drawing
	@trusted
	override ulong  create_bitmap(int w, int h) {
		++image_counter;
		images[image_counter] = MiniImage(w,h,new uint[w*h]);
		return image_counter;
	}
	override void   destroy_bitmap(ulong handle) {
		images.remove(handle);
	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		return images[handle].argb_data;
	}
	override void   access_bitmap_done(ulong handle) {
	}
	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                         double dx, double dy, double dw, double dh) {
		if (dw < 0) {
			dx = dx+dw;
			dw =    -dw;
			sx  = sx+sw;
			sw  =   -sw;
		}
		if (dh < 0) {
			dy = dy+dh;
			dh =    -dh;
			sy  = sy+sh;
			sh  =   -sh;
		}
		const i = &images[handle];
		import std.parallelism;
		import std.range, std.algorithm;

		// clipping
		if (dy < 0) {
			sy -= sh*dy/dh;
			sh += sh*dy/dh;
			dh += dy;
			dy -= dy;
		}
		if (dy >= canvas.height) {
			return;
		}
		if (dy+dh >= canvas.height) {
			sh  -= sh*((dy+dh)-canvas.height)/dh;
			dh -= ((dy+dh)-canvas.height);
		}

		if (dx < 0) {
			sx -= sw*dx/dw;
			sw += sw*dx/dw;
			dw += dx;
			dx -= dx;
		}
		if (dx >= canvas.width) {
			return;
		}
		if (dx+dw >= canvas.width) {
			sw  -= sw*((dx+dw)-canvas.width)/dw;
			dw -= ((dx+dw)-canvas.width);
		}

		int ddw = cast(int)dw;
		int ddx = cast(int)dx;
		int ddh = cast(int)dh;
		int ddy = cast(int)dy;

		auto yvalues = iota(ddy,ddy+ddh);
		auto xvalues = iota(ddx,ddx+ddw);

		//foreach(y;taskPool.parallel(yvalues,100)) {
		foreach(y; yvalues) {
		//for (int y = ddy; y <= ddy+ddh; ++y) {
			int yy = cast(int)(sy+(sh*(y-ddy)/ddh));

			//foreach(x; taskPool.parallel(xvalues)) {
			foreach(x; xvalues) {
			//for (int x = ddx; x <= ddx+ddw; ++x) {
				int xx = cast(int)(sx+(sw*(x-ddx)/ddw));
				uint rgba = i.argb_data[xx+yy*i.w];
				uint a = (rgba>>24)&0xff;
				uint r = (rgba>>16)&0xff;	
				uint g = (rgba>> 8)&0xff;	
				uint b = (rgba>> 0)&0xff;
				if (a == 0) continue;	
				auto c = Color(r,g,b);
				version(windows) {
					with(widget_painter.impl) {
						widget_painter.impl.SetPixel(widget_painter.impl.hdc, x, y, RGB(r,g,b) );
					}
				}
				else {
					widget_painter.pen = Pen(c, 1, Pen.Style.Solid);
					widget_painter.drawPixel(Point(x,y));
					//with(widget_painter.impl) {
					//	XDrawPoint(display, d, gc, x, y);
					//}
				}
			}

		}
	}

	// text drawing 
	override void set_text_size(int s) {
		text_size = s;
	}
	override void text_extent(string str, out double w, out double h) {
		int wi=1, hi=1;
		font.getStringSize(str, text_size, wi,hi);
		w = wi;
		h = hi;
	}
	override void text(double x, double y, string str) {
		int w, h;
		auto bitmap = font.renderString(str, text_size, w, h);
		auto img = new Image(w, h);

		for (int j=0; j < h; ++j) {
			for (int i=0; i < w; ++i) {
				auto c = cast(int)((255-bitmap[j*w+i])*0.9);
				img.putPixel(i, j, Color(c,c,c,c));
			}
		}
		widget_painter.drawImage(Point(cast(int)x, cast(int)(y-h+1)), img);

	} 

	override void need_redraw() {
		redraw();
	}
	override void show_mouse_pos(double x, double y, double z) {

	}
	override void show_value(double value, string itemname) {

	}




}