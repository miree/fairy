module graphics_allegro5;
@trusted:

import allegro5_import;
import graphics;

private bool run_main_loop = true;
private ALLEGRO_EVENT_QUEUE* queue;
private ALLEGRO_FONT*[int] fonts;
private ALLEGRO_FONT*      font;
private int default_font_size = 10;

void gui_add_window(string name, ref CanvasProperties canvas) {
	new MainWindow(name, &canvas);
}

void gui_loop() {
	al_install_system((ALLEGRO_VERSION << 24) | (ALLEGRO_SUB_VERSION << 16) | 
                      (ALLEGRO_WIP_VERSION << 8) | ALLEGRO_RELEASE_NUMBER | 
                       ALLEGRO_UNSTABLE_BIT, &atexit);
	al_init_primitives_addon();
	al_init_font_addon();
	al_init_ttf_addon();

	al_install_keyboard();
	al_install_mouse();

	queue = al_create_event_queue();

	fonts[default_font_size] = al_load_ttf_font("/usr/share/fonts/TTF/DejaVuSans.ttf", default_font_size, 0);
	if (!fonts[default_font_size]) {
		throw new Exception("cannot load font.ttf");
	}
	font = fonts[default_font_size];


	auto timeout_timer = al_create_timer(0.050);
	al_register_event_source(queue, al_get_timer_event_source(timeout_timer));
	al_start_timer(timeout_timer);


	al_register_event_source(queue, al_get_keyboard_event_source());
	al_register_event_source(queue, al_get_mouse_event_source());
	run_main_loop = true;

	import fairy;


	foreach(name, ref canvas; session.windows) {
		gui_add_window(name, canvas);
	}

	import std.stdio;
	while(fairy.running) {
		ALLEGRO_EVENT event;
		al_wait_for_event(queue, &event);

		if (event.type == ALLEGRO_EVENT_DISPLAY_CLOSE) 
		{
			auto window = MainWindow.main_windows[event.display.source];
			window.close_window();
		} 
		else if (event.type == ALLEGRO_EVENT_DISPLAY_RESIZE) 
		{
			auto window = MainWindow.main_windows[event.display.source];
			al_acknowledge_resize(event.display.source);
			window.resize(event.display.width, event.display.height);

			window.need_redraw();
		} 
		else if (event.type == ALLEGRO_EVENT_DISPLAY_EXPOSE) 
		{
			auto window = MainWindow.main_windows[event.display.source];
			window.need_redraw();
		} 
		else if (event.type == ALLEGRO_EVENT_KEY_DOWN) {
			//import std.stdio;
			//writeln("KEY_DOWN", event.keyboard.keycode, " ", cast(char)event.keyboard.keycode);

			auto window = MainWindow.main_windows[event.keyboard.display];
			int key = event.keyboard.keycode;
			//window.keypress(key);
			if (key == ALLEGRO_KEY_SPACE) window.space_pressed = true;
			window.need_redraw();
		}
		else if (event.type == ALLEGRO_EVENT_KEY_UP) {
			//import std.stdio;
			//writeln("KEY_UP", event.keyboard.keycode, " ", cast(char)event.keyboard.keycode);
			auto window = MainWindow.main_windows[event.keyboard.display];
			int key = event.keyboard.keycode;
			if (key == ALLEGRO_KEY_SPACE) window.space_pressed = false;
			window.need_redraw();
		}
		else if (event.type == ALLEGRO_EVENT_TIMER) 
		{
			foreach(display, window; MainWindow.main_windows) {
				import std.datetime.stopwatch;
				//if (window.get_draw_area().autorefresh) {
				//	import ui;
				//	refresh(window.name);
				//}
				if (window.redraw_scheduled && window.time_since_last_redraw.peek() > msecs(20)) {
					window.initialize();
					window.draw();
				}
			}
		}
		else if (event.type == ALLEGRO_EVENT_MOUSE_BUTTON_DOWN) 
		{
			auto window = MainWindow.main_windows[event.mouse.display];
			import std.stdio;
			if (event.mouse.button == 1) {
				window.painter.left_button_pressed(1, event.mouse.x, event.mouse.y);
			} else if (event.mouse.button == 2) { // right button
				window.painter.right_button_pressed(1, event.mouse.x, event.mouse.y);
			} else if (event.mouse.button == 3) { // middle button
				window.painter.mid_button_pressed(1, event.mouse.x, event.mouse.y);
			}
		} 
		else if (event.type == ALLEGRO_EVENT_MOUSE_BUTTON_UP) 
		{
			auto window = MainWindow.main_windows[event.mouse.display];
			import std.stdio;
			if (event.mouse.button == 1) {
				window.painter.left_button_released(1, event.mouse.x, event.mouse.y);
			} else if (event.mouse.button == 2) { // right button
				window.painter.right_button_released(1, event.mouse.x, event.mouse.y);
			} else if (event.mouse.button == 3) { // middle button
				window.painter.mid_button_released(1, event.mouse.x, event.mouse.y);
			}
		} 
		else if (event.type == ALLEGRO_EVENT_MOUSE_AXES) 
		{
			auto window = MainWindow.main_windows[event.mouse.display];
			if (event.mouse.dx || event.mouse.dy) {
				window.painter.mouse_motion(event.mouse.x, event.mouse.y);
			}
			if (event.mouse.dz || event.mouse.dw) {
				window.painter.scroll(event.mouse.dw,   // w-axis is left right
					                 -event.mouse.dz    // z-axis is up down (normal mouse wheel movement)
					                 );
			}

		} 

		if (fairy.iterate(0)) {
			import std.stdio;
			stdout.write("fairy> ");
			stdout.flush();
		}
	}

	// copy window position to canvas so that this information is stored in the session file
	foreach(window; MainWindow.main_windows) {
		int xpos, ypos;
		al_get_window_position(window.display, &xpos, &ypos);
		window.canvas.xpos = xpos-1; // for some reason reading back the position
		window.canvas.ypos = ypos-1; // has an offset of 1 that needs to be corrected
	}

}


class MainWindow : BackendInterface
{
private:
	static MainWindow[ALLEGRO_DISPLAY*] main_windows;

	CanvasProperties *canvas;
	ALLEGRO_DISPLAY* display;

	CanvasPainter painter;

	string name;

	bool redraw_scheduled = false;

public:
	import graphics;
	this(string canvas_name, CanvasProperties *canvas_pointer) {
		canvas = canvas_pointer;
		painter = CanvasPainter(canvas_pointer, this);
		name = canvas_name;

		with (ALLEGRO_DISPLAY_OPTIONS)
		{
			al_set_new_display_option(ALLEGRO_SAMPLE_BUFFERS, 1, ALLEGRO_SUGGEST);
			al_set_new_display_option(ALLEGRO_SAMPLES, 8, ALLEGRO_SUGGEST);
			al_set_new_display_option(ALLEGRO_DEPTH_SIZE, 16, ALLEGRO_SUGGEST);
		}
		al_set_new_display_flags(ALLEGRO_RESIZABLE | ALLEGRO_GENERATE_EXPOSE_EVENTS);
		display = al_create_display(canvas.width, canvas.height);
		if (!display) {
			throw new Exception("Application already running");
		}

		import std.string;
		string title_string = "fairy - " ~ name;
		al_set_window_title(display, title_string.toStringz);
		if (canvas.xpos != -1 && canvas.ypos != -1) {
			al_set_window_position(display, canvas.xpos, canvas.ypos);
		}

		main_windows[display] = this;
		al_register_event_source(queue, al_get_display_event_source(display));

		draw();

		time_since_last_redraw.start();
	}

	void need_redraw() {
		redraw_scheduled = true;
	}

	void draw() {
		al_set_target_bitmap(al_get_backbuffer(display));
		painter.draw_content();
		time_since_last_redraw.reset();
		redraw_scheduled = false;
	}

	void resize(int w, int h) {
		canvas.width = w;
		canvas.height = h;
		//area.resize(w,h);
	}

	void close_window() {
		import ui;
		import fairy;
		al_unregister_event_source(queue, al_get_display_event_source(display));
		al_destroy_display(display);
		main_windows.remove(display);
		session.windows.remove(name);
		//gui_windows.remove(name);

	}

	////////////////////////////////////////
	// BackendInterface functions
	////////////////////////////////////////
	ALLEGRO_COLOR color;
	double line_width = 1.0;
	double rect_x1, rect_x2, rect_y1, rect_y2;
	bool draw_rectangle = false;
	double mouse_x, mouse_y, mouse_z, mouse_value;
	string mouse_itemname;
	bool space_pressed = false;

	override bool inverted_y_direction() {
		return true;
	}
	override void initialize() {
		al_set_target_bitmap(al_get_backbuffer(display));
		set_text_size(default_font_size);
	}

	override void reset_clip() {
		al_set_clipping_rectangle(cast(int)0,cast(int)0, cast(int)canvas.width,cast(int)canvas.height);
	}
	override void set_clip(double x1, double y1, double x2, double y2) {
		al_set_clipping_rectangle(cast(int)x1,cast(int)y1, cast(int)(x2-x1),cast(int)(y2-y1));
	}

	override void clear(double r, double g, double b) {
		color.r = r;
		color.g = g;
		color.b = b;
		color.a = 1;
		al_clear_to_color(color);
	}
	override void set_color(double r, double g, double b) {
		color.r = r;
		color.g = g;
		color.b = b;
		color.a = 1;
	}
	override void set_line_width(double w) {
		line_width = w;
	}
	override double get_line_width() {
		return line_width;
	}
	override void vertical_line(double x, double y1, double y2) {
		al_draw_line(x,y1, x,y2, color, line_width);
	}
	override void horizontal_line(double y, double x1, double x2) {
		al_draw_line(x1,y, x2,y, color, line_width);
	}
	override void line(double x1, double y1, double x2, double y2) {
		al_draw_line(x1,y1, x2,y2, color, line_width);
	}
	void rectangle(double x1, double y1, double x2, double y2)
	{
		draw_rectangle = true;
		rect_x1 = x1;
		rect_y1 = y1;
		rect_x2 = x2;
		rect_y2 = y2;
	}
	override void fill() {
		if (draw_rectangle) {
			al_draw_filled_rectangle(rect_x1,rect_y1, rect_x2,rect_y2, color);
			draw_rectangle = false;
		}
	}
	override void stroke() {
		if (draw_rectangle) {
			al_draw_rectangle(rect_x1,rect_y1, rect_x2,rect_y2, color, line_width);
			draw_rectangle = false;
		}
	}


	ALLEGRO_BITMAP*[ulong] bitmaps;
	ulong bitmap_counter = 0;
	@trusted
	override ulong create_bitmap(int w, int h) {
		//import allegro5.allegro;
		al_set_new_bitmap_flags(ALLEGRO_MEMORY_BITMAP);
		al_set_new_bitmap_format(ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ARGB_8888);
		auto bitmap = al_create_bitmap(w,h);
		++bitmap_counter;
		auto handle = bitmap_counter;
		bitmaps[handle] = bitmap;
		return handle;
	}
	override void destroy_bitmap(ulong handle) {
		bitmaps.remove(handle);
	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		auto bitmap = bitmaps[handle];
		auto lock = al_lock_bitmap(bitmap,ALLEGRO_PIXEL_FORMAT.ALLEGRO_PIXEL_FORMAT_ARGB_8888,0);
		auto width = al_get_bitmap_width(bitmap);
		auto height = al_get_bitmap_height(bitmap);
		return (cast(uint*)lock.data)[0..width*height*lock.pixel_size/4]; 
	}
	override void access_bitmap_done(ulong handle) {
		al_unlock_bitmap(bitmaps[handle]);
	}

	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                                    double dx, double dy, double dw, double dh) {

		import std.math;
		long sxi = cast(long)floor(sx);
		long syi = cast(long)floor(sy);
		long swi = cast(long)ceil(sx+sw)-sxi;
		long shi = cast(long)ceil(sy+sh)-syi;
		al_draw_scaled_bitmap(bitmaps[handle], sxi,syi, swi,shi, dx,dy, dw,dh, 0);
	}


	override void finish() {
		if (space_pressed) {

			double w,h,w_item,h_item;
			import std.conv;
			string x_str = "x=" ~ mouse_x.to!string; 
			string y_str = "y=" ~ mouse_y.to!string;
			string z_str = "z=" ~ mouse_z.to!string;
			string v_str = mouse_value.to!string;
			al_set_clipping_rectangle(cast(int)0,cast(int)0, cast(int)canvas.width,cast(int)canvas.height);
			text_extent("0", w,h);
			text_extent(mouse_itemname, w_item, h_item);
			double width = 16*w;
			if (w_item > width) width = w_item;
			set_color(1.0,1.0,1.0);
			rectangle(0,0,width,h*7.5);
			fill();
			set_color(0,0,0);
			text(0, 1.5*h, x_str);
			text(0, 3.0*h, y_str);
			text(0, 4.5*h, z_str);
			if (mouse_itemname !is null && mouse_itemname != "") {
				text(0, 6.0*h, mouse_itemname);
				text(0, 7.5*h, v_str);
			}
		}

		al_flip_display();
	}


	override void set_text_size(int s) {
		auto f = s in fonts;
		if (f is null) {
			fonts[s] = al_load_ttf_font("/usr/share/fonts/TTF/DejaVuSans.ttf", 20, 0);
			if (!fonts[s]) {
				throw new Exception("cannot load font.ttf");
			}				
			font = fonts[s];
		} else {
			font = *f;
		}
	}

	void set_overlay(bool overlay) {
		canvas.display_mode = DisplayMode.overlay;
		need_redraw();
	}
	void set_rows(int rows) {
		canvas.display_mode    = DisplayMode.rows;
		canvas.columns_or_rows = rows;
		need_redraw();
	}
	void set_columns(int columns) {
		canvas.display_mode    = DisplayMode.columns;
		canvas.columns_or_rows = columns;
		need_redraw();
	}

	immutable text_margin_x = 1;
	immutable text_margin_y = 3;
	override void text_extent(string str, out double w, out double h) {
		import std.string;
		int xi, yi, wi, hi;
		al_get_text_dimensions(font, str.toStringz, &xi, &yi, &wi, &hi);
		//x=xi;
		//y=yi;
		w=wi+2*text_margin_x;
		h=hi+2*text_margin_y;
	}
	override void text(double x, double y, string str) {
		import std.string;
		int xi, yi, wi, hi;
		al_get_text_dimensions(font, str.toStringz, &xi, &yi, &wi, &hi);
		al_draw_text(font, color, x+text_margin_x, y-yi-hi-text_margin_y, ALLEGRO_ALIGN_LEFT, str.toStringz); 
	}
	import std.datetime.stopwatch;
	StopWatch time_since_last_redraw;
	override void show_mouse_pos(double x, double y, double z) {
		import std.stdio;
		mouse_x = x;
		mouse_y = y;
		mouse_z = z;
		need_redraw();
		//writeln("mouse ", x, " ", y);
	}

	override void show_value(double value, string itemname) {
		mouse_value = value;
		mouse_itemname = itemname;
		need_redraw();
	}


}



