module graphics_minigui;
@trusted:

import arsd.minigui;
import arsd.ttf;
import graphics;

class MiniGuiGL : Gui {


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
		//import std.stdio;
		//writeln("new minigui window with name ", canvas_name);
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


class DrawArea : OpenGlWidget, BackendInterface 
{
	import arsd.ttf;
	CanvasProperties* canvas;
	string name;
	CanvasPainter painter;

	static OpenGlLimitedFont!(OpenGlFontGLVersion.old) glfont;
	static font_loaded = false;

	int text_size = 20;
	double line_width = 1;
	double cr,cg,cb;
	double rx1,ry1,rx2,ry2;
	bool rect_valid = false;

	double cx1,cy1,cx2,cy2;

	struct MiniImage {
		int w;
		int h;
		uint[] argb_data;
		uint gl_tex;
	}
	ulong image_counter = 0;
	MiniImage[ulong] images;

	this(string window_name, CanvasProperties *canvas_ptr, Widget parent) {
		canvas = canvas_ptr;
		name = window_name;
		painter = CanvasPainter(canvas, this);
		super(parent);
		super.redrawOpenGlScene(&draw_scene);
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
		//import std.stdio;
		//writeln(event.clientX, " ", event.clientY);
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

	void draw_scene() {
		if (!font_loaded) {
			auto osfont = new OperatingSystemFont("DejaVu Sans", 18);

			assert(!osfont.isNull()); // make sure it actually loaded
			// using typeof to avoid repeating the long name lol
			glfont = new typeof(glfont)(
				osfont.getTtfBytes(),
				18, 
				0,
				128
			);			
		}


		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
		//glClearColor(0,0,0,0);
		//glClear(GL_COLOR_BUFFER_BIT);
		glDepthFunc(GL_LEQUAL);

		// Also need to enable 2d textures, since it draws the
		// font characters as images baked in
		glMatrixMode(GL_MODELVIEW);
		glLoadIdentity();
		glDisable(GL_DEPTH_TEST);
		glEnable(GL_TEXTURE_2D);

		// the orthographic matrix is best for 2d things like text
		// so let's set that up. This matrix makes the coordinates
		// in the opengl scene be one-to-one with the actual pixels
		// on screen. (Not necessarily best, you may wish to scale
		// things, but it does help keep fonts looking normal.)
		glMatrixMode(GL_PROJECTION);
		glLoadIdentity();

		glOrtho(0, width, height,0 , 0, 1);


		painter.draw_content();

		// you can do other glScale, glRotate, glTranslate, etc
		// to the matrix here of course if you want.

		// note the x,y coordinates here are for the text baseline
		// NOT the upper-left corner. The baseline is like the line
		// in the notebook you write on. Most the letters are actually
		// above it, but some, like p and q, dip a bit below it.
		//
		// So if you're used to the upper left coordinate like the
		// rest of simpledisplay/minigui usually do, do the
		// y + glfont.ascent to bring it down a little. So this
		// example puts the string in the upper left of the window.
		//glfont.drawString(0, 0 + glfont.ascent/2, "Hello!!", Color.black);

	}
	//override Rectangle paintContent(WidgetPainter w_painter, const Rectangle bounds) {

	//	widget_painter = &w_painter;

	//	painter.draw_content();

	//	widget_painter = null;
	//	return bounds;
	//}


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
		cx1 = 0;
		cy1 = 0;
		cx2 = width;
		cy2 = height;
	}
	override void set_clip(double x1, double y1, double x2, double y2) {
		cx1 = x1;
		cy1 = y1;
		cx2 = x2;
		cy2 = y2;
		import std.algorithm;
		if (x1>x2) swap(x1,x2);
		if (y1>y1) swap(y1,y2);
	}

	override void clear(double r, double g, double b) {
		glClearColor(r,g,b,1);
		glClear(GL_COLOR_BUFFER_BIT);
	}
	override void set_color(double r, double g, double b) {
		glColor3f(r,g,b);
		cr=r;
		cg=g;
		cb=b;
	}
	
	// line drawing
	override void set_line_width(double w) {
		line_width = w;
	}
	override double get_line_width() {
		return line_width;
	}
	override void vertical_line(double xd, double y1d, double y2d) {
		if (xd<cx1) return;
		if (xd>cx2) return;
		import std.algorithm;
		if (y1d>y2d) swap(y1d,y2d);
		if (y1d>cy2) return;
		if (y2d<cy1) return;
		if (y1d<cy1) y1d=cy1;
		if (y2d>cy2) y2d=cy2;
		glBegin(GL_QUADS);
		glVertex2f(xd+line_width/2.0,y1d);
		glVertex2f(xd-line_width/2.0,y1d);
		glVertex2f(xd-line_width/2.0,y2d);
		glVertex2f(xd+line_width/2.0,y2d);
		glEnd();
	}
	override void horizontal_line(double yd, double x1d, double x2d) {
		if (yd<cy1) return;
		if (yd>cy2) return;
		import std.algorithm;
		if (x1d>x2d) swap(x1d,x2d);
		if (x1d>cx2) return;
		if (x2d<cx1) return;
		if (x1d<cx1) x1d=cx1;
		if (x2d>cx2) x2d=cx2;
		glBegin(GL_QUADS);
		glVertex2f(x1d,yd+line_width/2.0);
		glVertex2f(x1d,yd-line_width/2.0);
		glVertex2f(x2d,yd-line_width/2.0);
		glVertex2f(x2d,yd+line_width/2.0);
		glEnd();
	}
	override void line(double x1d, double y1d, double x2d, double y2d) {
		glBegin(GL_LINE_STRIP);
		glVertex2f(x1d,y1d);
		glVertex2f(x2d,y2d);
		glEnd();
	}
	override void rectangle(double x1d, double y1d, double x2d, double y2d) {
		rx1=x1d;
		ry1=y1d;
		rx2=x2d;
		ry2=y2d;
		rect_valid = true;
	}
	override void fill() {
		if (!rect_valid) return;
		glBegin(GL_QUADS);
		glVertex2f(rx1,ry1);
		glVertex2f(rx1,ry2);
		glVertex2f(rx2,ry2);
		glVertex2f(rx2,ry1);
		glEnd();
		rect_valid = false;
	}
	override void stroke() {
		if (!rect_valid) return;
		vertical_line(rx1,ry1,ry2);
		vertical_line(rx2,ry1,ry2);
		horizontal_line(ry1,rx1,rx2);
		horizontal_line(ry2,rx1,rx2);
		rect_valid = false;
	}

	// bitmap drawing
	@trusted
	override ulong  create_bitmap(int w, int h) {
		++image_counter;
		images[image_counter] = MiniImage(w,h,null);
		images[image_counter].argb_data = new uint[w*h];
		glEnable(GL_TEXTURE_2D);
		glGenTextures(1, &images[image_counter].gl_tex);
		return image_counter;
	}
	override void   destroy_bitmap(ulong handle) {
		glEnable(GL_TEXTURE_2D);
		glDeleteTextures(1, &images[image_counter].gl_tex);
		images.remove(handle);
	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		return images[handle].argb_data;
	}
	@trusted
	override void access_bitmap_done(ulong handle) {
		glEnable(GL_TEXTURE_2D);
		//glGenTextures(1, &images[handle].gl_tex);
		glBindTexture(GL_TEXTURE_2D, images[handle].gl_tex);
		glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
		glTexImage2D(
			GL_TEXTURE_2D,
			0,
			GL_RGBA,
			images[handle].w,
			images[handle].h,
			0,
			GL_BGRA,
			GL_UNSIGNED_BYTE,
			images[handle].argb_data.ptr);
		assert(!glGetError());
		glBindTexture(GL_TEXTURE_2D, 0);
	}

	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                         double dx, double dy, double dw, double dh) {
		glEnable(GL_TEXTURE_2D);
		//glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_DECAL);
		glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
		//glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_BLEND);
		glBindTexture(GL_TEXTURE_2D, images[handle].gl_tex);
		glMatrixMode(GL_TEXTURE);
		glPushMatrix();
		glLoadIdentity();
		glScalef(1.0/images[handle].w, 1.0/images[handle].h,0);

		glBegin(GL_QUADS); 
			glColor4f(1,1,1,1); glTexCoord2f(sx   , sy   ); glVertex2f(dx   , dy);
			glColor4f(1,1,1,1); glTexCoord2f(sx+sw, sy   ); glVertex2f(dx+dw, dy); 
			glColor4f(1,1,1,1); glTexCoord2f(sx+sw, sy+sh); glVertex2f(dx+dw, dy+dh); 
			glColor4f(1,1,1,1); glTexCoord2f(sx   , sy+sh); glVertex2f(dx   , dy+dh); 
		glEnd();
		//glBegin(GL_QUADS); 
		//	glTexCoord2f(0,0); glVertex3f(dx   , dy   , 0);      
		//	glTexCoord2f(1,0); glVertex3f(dx+dw, dy   , 0);      
		//	glTexCoord2f(1,1); glVertex3f(dx+dw, dy+dh, 0);   
		//	glTexCoord2f(0,1); glVertex3f(dx   , dy+dh, 0);   
		//glEnd();
		glBindTexture(GL_TEXTURE_2D, 0);
		glPopMatrix();
	}

	// text drawing 
	override void set_text_size(int s) {
		text_size = s;
	}
	override void text_extent(string str, out double w, out double h) {
		h = glfont.ascent;
		w = 0.65*glfont.ascent*str.length;
		//import std.stdio;
		//writeln(h, " ", w);
	}
	override void text(double x, double y, string str) {
		//import std.stdio;
		//writeln("text ", str, " at ", x, " ", y);
		glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
		glfont.drawString(cast(int)x, cast(int)y, str, Color(255*cr,255*cg,255*cb));
	} 

	override void need_redraw() {
		redraw();
	}
	override void show_mouse_pos(double x, double y, double z) {

	}
	override void show_value(double value, string itemname) {

	}




}