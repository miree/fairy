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
		window.canvas.width  = window.window.width;
		window.canvas.height = window.window.height;
		window.canvas.xpos = point.x; 
		window.canvas.ypos = point.y; 
	}
	override void reset_item(string name) {
	}
	override void remove_item(string name) {
	}
	override void add_item(string name) {
		import std.stdio;
		writeln("add item", name);
		foreach(window_name, window; MainWindow.main_windows) {
			window.item_view.addOption(name);
		}
	}
	override void update_from_canvas(string name) {
		foreach(n,win; MainWindow.main_windows) {
			win.autorefresh.isChecked = win.canvas.autorefresh;
			win.fitX.isChecked        = win.canvas.autoscale[0];
			win.fitY.isChecked        = win.canvas.autoscale[1];
			win.fitZ.isChecked        = win.canvas.autoscale[2];
			win.logX.isChecked        = win.canvas.transform[0].logscale;
			win.logY.isChecked        = win.canvas.transform[1].logscale;
			win.logZ.isChecked        = win.canvas.transform[2].logscale;
			win.gridX.isChecked       = win.canvas.grid[0];
			win.gridY.isChecked       = win.canvas.grid[1];
			win.gridTop.isChecked     = win.canvas.grid_ontop;
			win.numsX.isChecked       = win.canvas.numbers[0];
			win.numsY.isChecked       = win.canvas.numbers[1];
			win.numsTop.isChecked     = win.canvas.numbers_ontop;
			win.radio_overlay.isChecked = false;
			win.radio_rows.isChecked    = false;
			win.radio_cols.isChecked    = false;
			if (win.canvas.display_mode == DisplayMode.overlay) win.radio_overlay.isChecked = true;
			if (win.canvas.display_mode == DisplayMode.rows)    win.radio_rows.isChecked    = true;
			if (win.canvas.display_mode == DisplayMode.columns) win.radio_cols.isChecked    = true;
		}
	}
	override void loop() {
		import fairy;
		EventLoop main_event_loop = EventLoop.get;

		foreach(name, ref canvas; session.windows) {
			add_window(name, canvas);
		}

		auto timer = new Timer(20, delegate void (){

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

	HorizontalLayout   main_content;
		VerticalLayout itemlist;
			ListWidget         item_view;
		Widget             plotwidget;
			DrawArea           draw_area;
			HorizontalLayout   controls;
				//VerticalLayout     autorefr;    
					Fieldset refreshlayout;
						Button           refresh;
						Checkbox         autorefresh;
				//VerticalLayout     fitcontrol;
					Fieldset fitlayout;
						//TextLabel    fitlabel;
						Checkbox     fitX;
						Checkbox     fitY;
						Checkbox     fitZ;
					Fieldset loglayout;
						//TextLabel    loglabel;
						Checkbox     logX;
						Checkbox     logY;
						Checkbox     logZ;
				//VerticalLayout     gridcontrol;
					Fieldset gridlayout;
						//TextLabel      gridlabel;
						Checkbox       gridX;
						Checkbox       gridY;
						Checkbox       gridTop;
				//VerticalLayout     numscontrol;
					Fieldset numslayout;
						//TextLabel      numslabel;
						Checkbox       numsX;
						Checkbox       numsY;
						Checkbox       numsTop;
				//VerticalLayout     modecontrol;
					Fieldset         modeselect;
						Radiobox       radio_overlay;
						Radiobox       radio_rows;
						Radiobox       radio_cols;


public:
	@trusted
	this(string canvas_name, CanvasProperties *canvas_pointer) {
		assert(canvas_pointer !is null);
		canvas = canvas_pointer;
		name = canvas_name;

		simple = new SimpleWindow(canvas.width, canvas.height, canvas_name, OpenGlOptions.no, Resizability.allowResizing);
		window = new Window(simple);


		if (canvas.xpos >= 0 && canvas.ypos >= 0) {
			simple.move(canvas.xpos-1, canvas.ypos-24);
		}

		main_content = new HorizontalLayout(window);
		itemlist = new VerticalLayout(200, main_content);
			item_view  = new ListWidget(itemlist);
		import fairy, std.algorithm, std.array;
		foreach (itemname; fairy.session.items.byKey.array.sort) {
			item_view.addOption(itemname);
		}
		plotwidget = new Widget(main_content);
		draw_area = new DrawArea(canvas_name, canvas_pointer, plotwidget);

		controls = new HorizontalLayout(40,plotwidget);

		//autorefr = new VerticalLayout(80,controls);
			refreshlayout = new Fieldset("refresh", controls);

			refresh     = new Button("now", refreshlayout);
			autorefresh = new Checkbox("auto", refreshlayout); autorefresh.isChecked = canvas.autorefresh;
			fitlayout = new Fieldset("fit",controls);
				fitX     = new Checkbox ("X"  ,fitlayout);        fitX.isChecked = canvas.autoscale[0];
				fitY     = new Checkbox ("Y"  ,fitlayout);        fitY.isChecked = canvas.autoscale[1];
				fitZ     = new Checkbox ("Z"  ,fitlayout);        fitZ.isChecked = canvas.autoscale[2];
			loglayout = new Fieldset("log",controls);
				logX     = new Checkbox ("X"  ,loglayout);        logX.isChecked = canvas.transform[0].logscale;
				logY     = new Checkbox ("Y"  ,loglayout);        logY.isChecked = canvas.transform[1].logscale;
				logZ     = new Checkbox ("Z"  ,loglayout);        logZ.isChecked = canvas.transform[2].logscale;
			gridlayout = new Fieldset("grid",controls);
				gridX     = new Checkbox ("X"  ,gridlayout);      gridX.isChecked = canvas.grid[0];
				gridY     = new Checkbox ("Y"  ,gridlayout);      gridY.isChecked = canvas.grid[1];
				gridTop   = new Checkbox ("top",gridlayout);      gridTop.isChecked = canvas.grid_ontop;
			numslayout = new Fieldset("num", controls);
				numsX     = new Checkbox ("X"  ,numslayout);      numsX.isChecked = canvas.numbers[0];
				numsY     = new Checkbox ("Y"  ,numslayout);      numsY.isChecked = canvas.numbers[1];
				numsTop   = new Checkbox ("top",numslayout);      numsTop.isChecked = canvas.numbers_ontop;
			modeselect = new Fieldset("mode",controls);
				radio_overlay = new Radiobox("overlay", modeselect);  if (canvas.display_mode == DisplayMode.overlay) radio_overlay.isChecked = true;
				radio_rows    = new Radiobox("rows"   , modeselect);  if (canvas.display_mode == DisplayMode.rows)    radio_rows.isChecked = true;
				radio_cols    = new Radiobox("columns", modeselect);  if (canvas.display_mode == DisplayMode.columns) radio_cols.isChecked = true;

		import ui;
	
		//item_view.addEventListener(EventType.click, () {ui.show(canvas_name, item_view.getSelectionString);});
	
		autorefresh.addEventListener(EventType.change,   () { ui.winpoll(canvas_name, autorefresh.isChecked?"true":"false"); });
		    refresh.addEventListener(EventType.triggered,() { ui.winrefresh(canvas_name); });
		       fitX.addEventListener(EventType.change,   () { ui.autoscale(canvas_name, 'x', fitX.isChecked?"true":"false"); });
		       fitY.addEventListener(EventType.change,   () { ui.autoscale(canvas_name, 'y', fitY.isChecked?"true":"false"); });
		       fitZ.addEventListener(EventType.change,   () { ui.autoscale(canvas_name, 'z', fitZ.isChecked?"true":"false"); });
		       logX.addEventListener(EventType.change,   () { ui.logscale( canvas_name, 'x', logX.isChecked?"true":"false"); });
		       logY.addEventListener(EventType.change,   () { ui.logscale( canvas_name, 'y', logY.isChecked?"true":"false"); });
		       logZ.addEventListener(EventType.change,   () { ui.logscale( canvas_name, 'z', logZ.isChecked?"true":"false"); });
		       gridX.addEventListener(EventType.change,  () { ui.grid(canvas_name, "x",   gridX.isChecked?"true":"false"); });
		       gridY.addEventListener(EventType.change,  () { ui.grid(canvas_name, "y",   gridY.isChecked?"true":"false"); });
		       gridTop.addEventListener(EventType.change,() { ui.grid(canvas_name, "top", gridTop.isChecked?"true":"false"); });
		       numsX.addEventListener(EventType.change,  () { ui.numbers( canvas_name, "x",   numsX.isChecked?"true":"false"); });
		       numsY.addEventListener(EventType.change,  () { ui.numbers( canvas_name, "y",   numsY.isChecked?"true":"false"); });
		       numsTop.addEventListener(EventType.change,() { ui.numbers( canvas_name, "top", numsTop.isChecked?"true":"false"); });
		       radio_overlay.addEventListener(EventType.change, () { if (radio_overlay.isChecked) ui.overlay(canvas_name); });
		       radio_rows.addEventListener(EventType.change,    () { if (radio_rows.isChecked) ui.rows   (canvas_name, canvas.columns_or_rows); });
		       radio_cols.addEventListener(EventType.change,    () { if (radio_cols.isChecked) ui.columns(canvas_name, canvas.columns_or_rows); });
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
	double cr,cg,cb,ca;
	double rx1,ry1,rx2,ry2;
	bool rect_valid = false;

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
		if (event.button == MouseButton.left)    painter.left_button_pressed  (1, event.clientX, event.clientY, this);
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
		//glEnable(GL_SCISSOR_TEST);
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

		canvas.height=height;
		canvas.width=width;
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

	override bool inverted_y_direction() {
		return true;
	} // true if the y-coordinates go from top to bottom
	override bool text_with_border() {
		return true;
	} // true if black text should be rendered with a white border

	override void initialize() {

	}   // must be called before anything else
	override void finish() {
		glFlush();
		glFinish();
	} // must be called after anything else

	override void reset_clip() {
		glDisable(GL_SCISSOR_TEST);
	}
	override void set_clip(double x1, double y1, double x2, double y2) {
		glEnable(GL_SCISSOR_TEST);
		import std.algorithm;
		if (x1>x2) swap(x1,x2);
		if (y1>y1) swap(y1,y2);
		int w = cast(int)(x2-x1);
		int h = cast(int)(y2-y1);
		glScissor(cast(int)x1,cast(int)(height-y2-h)+h,w,h);
	}

	override void clear(double r, double g, double b) {
		glClearColor(r,g,b,1);
		glClear(GL_COLOR_BUFFER_BIT);
	}
	override void set_color(double r, double g, double b, double a) {
		cr=r;
		cg=g;
		cb=b;
		ca=a;
		glColor4f(cr,cg,cb,ca);
	}
	
	// line drawing
	override void set_line_width(double w) {
		line_width = w;
	}
	override double get_line_width() {
		return line_width;
	}
	override void vertical_line(double xd, double y1d, double y2d) {
		glBegin(GL_QUADS);
		glColor4f(cr,cg,cb,ca);
		glVertex2f(xd+line_width/2.0,y1d);
		glVertex2f(xd-line_width/2.0,y1d);
		glVertex2f(xd-line_width/2.0,y2d);
		glVertex2f(xd+line_width/2.0,y2d);
		glEnd();
	}
	override void horizontal_line(double yd, double x1d, double x2d) {
		glBegin(GL_QUADS);
		glColor4f(cr,cg,cb,ca);
		glVertex2f(x1d,yd+line_width/2.0);
		glVertex2f(x1d,yd-line_width/2.0);
		glVertex2f(x2d,yd-line_width/2.0);
		glVertex2f(x2d,yd+line_width/2.0);
		glEnd();
	}
	override void line(double x1d, double y1d, double x2d, double y2d) {
		double dx=x2d-x1d;
		double dy=y2d-y1d;
		double ox=-dy;
		double oy= dx;
		import std.math;
		double lo=sqrt(ox*ox+oy*oy);
		if (lo < 1e-6) return;

		glBegin(GL_QUADS);
			glColor4f(cr,cg,cb,ca);
			glVertex2f(x1d+line_width*ox/2/lo, y1d+line_width*oy/2/lo);
			glVertex2f(x2d+line_width*ox/2/lo, y2d+line_width*oy/2/lo);
			glVertex2f(x2d-line_width*ox/2/lo, y2d-line_width*oy/2/lo);
			glVertex2f(x1d-line_width*ox/2/lo, y1d-line_width*oy/2/lo);
		glEnd();

	}
	override void rectangle(double x1d, double y1d, double x2d, double y2d) {
		rx1=x1d;
		ry1=y1d;
		rx2=x2d;
		ry2=y2d;
		rect_valid = true;
	}
	override void polygon(double[2][] xys) {
		// not implemented yet
	}		
	override void fill() {
		if (!rect_valid) return;
		glBegin(GL_QUADS);
		glColor4f(cr,cg,cb,ca);
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
	}
	override void text(double x, double y, string str) {
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