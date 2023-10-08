module graphics_allegro5;
@trusted:

import allegro5_import;
import graphics;

private bool run_main_loop = true;
private ALLEGRO_EVENT_QUEUE* queue;
private ALLEGRO_FONT*[int] fonts;
private ALLEGRO_FONT*      font;
private int default_font_size = 10;

void gui_add_window(string name, ref Canvas canvas) {
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
		else if (event.type == ALLEGRO_EVENT_TIMER) 
		{
			foreach(display, window; MainWindow.main_windows) {
				import std.datetime.stopwatch;
				//if (window.get_draw_area().autorefresh) {
				//	import ui;
				//	refresh(window.name);
				//}
				if (window.redraw_scheduled/+ && window.time_since_last_redraw.peek() > msecs(20)+/) {
					//window.init();
					//window.drawFunc();
					//window.time_since_last_redraw.reset();
					window.draw();
				}
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


class MainWindow 
{
private:
	static MainWindow[ALLEGRO_DISPLAY*] main_windows;

	Canvas *canvas;
	ALLEGRO_DISPLAY* display;

	string name;

	bool redraw_scheduled = false;

public
	import graphics;
	this (string canvas_name, Canvas *canvas_pointer) {
		canvas = canvas_pointer;
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
	}

	void need_redraw() {
		redraw_scheduled = true;
	}

	void draw() {
		ALLEGRO_COLOR color;
		color.r = 1;
		color.g = 1;
		color.b = 1;
		color.a = 1;
		al_set_target_bitmap(al_get_backbuffer(display));
		al_clear_to_color(color);
		al_flip_display();
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

}



