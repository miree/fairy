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

	}
	override void redraw_window(string name) {
		MainWindow.main_windows[name].draw_area.need_redraw();
	}
	override void loop() {
		import fairy;
		EventLoop main_event_loop = EventLoop.get;

		foreach(name, ref canvas; session.windows) {
			add_window(name, canvas);
		}

		auto timer = new Timer(10, delegate void (){

			import std.stdio;
			if (fairy.iterate(0)) {
				import std.stdio;
				stdout.write("fairy> ");
				stdout.flush();
			}

			if (!fairy.running) { // quit
				 //copy window position to canvas so that this information is stored in the session file
				foreach(window; MainWindow.main_windows) {
					auto point = window.draw_area.globalCoordinates();
					window.canvas.xpos = point.x; 
					window.canvas.ypos = point.y; 
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
			simple.move(canvas.xpos, canvas.ypos);
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
	CanvasProperties* canvas;
	string name;
	CanvasPainter painter;
	double line_width = 1;
	Color color;

	double rect_x1, rect_x2, rect_y1, rect_y2;
	bool rect_valid = false;

	bool first_draw = true;

	WidgetPainter *widget_painter;

	this(string window_name, CanvasProperties *canvas_ptr, Widget parent) {
		canvas = canvas_ptr;
		name = window_name;
		painter = CanvasPainter(canvas, this);
		super(parent);
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
			case '1': .. case '9':
				if (canvas.display_mode == DisplayMode.rows)    rows(name, event.key-'0');
				if (canvas.display_mode == DisplayMode.columns) columns(name, event.key-'0');
			break;
			case 'u': winrefresh(name); break;
			case 'p': winpoll(name); break;
			case 'q': winzoom(name,1*1.2); break;
			case 'e': winzoom(name,1/1.1666666666); break;
			case 'a': winmove(name,'x',-0.2); break;
			case 'd': winmove(name,'x',+0.2); break;
			case 's': winmove(name,'y',-0.2); break;
			case 'w': winmove(name,'y',+0.2); break;
			case 'o': overlay(name); break;
			case 'b': colorbar(name); break;
			case 'g': grid(name,"top","toggle"); break;
			case 'c': columns(name, canvas.columns_or_rows); break;
			case 'r': rows   (name, canvas.columns_or_rows); break;
			case 'x': autoscale  (name, 'x', "toggle");  break;
			case 'y': autoscale  (name, 'y', "toggle");  break;
			case 'z': autoscale  (name, 'z', "toggle");  break;
			case 'l': logscale(name, canvas.dim==2?'z':'y', "toggle");  break;
			case 'f': winfit(name);  break;
			default: {}
		}

	}


	override Rectangle paintContent(WidgetPainter w_painter, const Rectangle bounds) {
		if (first_draw) {
			auto point = globalCoordinates();
			import std.stdio;
			writeln("point : ", point);
			int delta_x = point.x - canvas.xpos;
			int delta_y = point.y - canvas.ypos;
			MainWindow.main_windows[name].simple.move(canvas.xpos-delta_x, canvas.ypos-delta_y);
			first_draw = false;
		}


		widget_painter = &w_painter;

		painter.draw_content();

		widget_painter = null;
		return bounds;
	}





	override bool inverted_y_direction() {
		return true;
	} // true if the y-coordinates go from top to bottom
	override bool text_with_border() {
		return true;
	} // true if black text should be rendered with a white border

	override void initialize() {

	}   // must be called before anything else
	override void finish() {

	} // must be called after anything else

	override void reset_clip() {

	}
	override void set_clip(double x1, double y1, double x2, double y2) {

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
		return 0;
	}
	override void   destroy_bitmap(ulong handle) {

	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		return null;
	}
	override void   access_bitmap_done(ulong handle) {

	}
	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                         double dx, double dy, double dw, double dh) {

	}

	// text drawing 
	override void set_text_size(int s) {

	}
	override void text_extent(string str, out double w, out double h) {

	}
	override void text(double x, double y, string str) {

	} 

	override void need_redraw() {
		redraw();
	}
	override void show_mouse_pos(double x, double y, double z) {

	}
	override void show_value(double value, string itemname) {

	}




}