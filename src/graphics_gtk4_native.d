@trusted:

import gtk4_import;
import std.string : toStringz;


void g_signal_connect(Widget,Callback)(Widget w, const char* signal_name, Callback callback, void* user_data) 
{
	g_signal_connect_d(cast(void*)w, signal_name, cast(void*)callback, user_data);
}

void g_signal_connect_swapped(Widget,Callback)(Widget w, const char* signal_name, Callback callback, void* user_data) 
{
	g_signal_connect_swapped_d(cast(void*)w, signal_name, cast(void*)callback, user_data);
}

void g_signal_connect_after(Widget,Callback)(Widget w, const char* signal_name, Callback callback, void* user_data) 
{
	g_signal_connect_after_d(cast(void*)w, signal_name, cast(void*)callback, user_data);
}




import graphics;



class Gtk4NativeGui : Gui {

	static GtkApplication* application  = null;
	static GApplication*   gapplication = null;

	static MainWindow[string] main_windows;


	extern(C)
	static gboolean 
	timeout_callback(gpointer user_data) 
	{
		import fairy;
		if(!fairy.running) g_application_quit(gapplication);

		if (fairy.iterate(0)) {
			import std.stdio;
			stdout.write("fairy> ");
			stdout.flush();
		}
		//foreach(name, window; main_windows) {
		//	import ui;
		//	if (window.canvas.autorefresh) winrefresh(window.name);
		//}
		return true; // continue

	}
	extern(C) 
	static void
	activate (GtkApplication *app,
	          gpointer        user_data)
	{
		auto self = cast(Gtk4NativeGui)user_data;
		import fairy;
	 
		immutable ulong refresh_period_ms = 20;
		g_timeout_add(refresh_period_ms, &timeout_callback, null);
		foreach(name, ref canvas; session.windows) {
			self.add_window(name, canvas);
		}

	}


	override void add_window(string name, ref CanvasProperties canvas) {
		main_windows[name] = new MainWindow(name, &canvas, application);
	}
	override void close_window(string name) {
	}
	override void redraw_window(string name) {
	}
	override void save_window(string name) { // copy window properties to canvas
	}
	override void remove_item(string name) {
	}
	override void add_item(string name) {
	}
	override void update_from_canvas(string name) {
	}

	override void loop() {
		// setup the application instance only if it is not already running
		if (application !is null) {
			import std.stdio;
			throw new Exception("Application already running");
			return;
		}

		application = gtk_application_new ("de.risingedge.fairy", G_APPLICATION_NON_UNIQUE);
		scope(exit) g_object_unref (application);

		g_signal_connect!(GtkApplication*)(application, "activate", &activate, cast(gpointer)this);

		int argc = 0;
		char* argv = null;
		gapplication = cast(GApplication*)application;
		auto result = g_application_run (gapplication, argc, &argv);

	}
}

class MainWindow 
{
import graphics;

private:
	GtkWindow*        window;
	GtkApplication*   application;
	CanvasProperties* canvas;
	this (string name, CanvasProperties* canvas_properties, GtkApplication* app)
	{
		application = app;
		window      = cast(GtkWindow*)gtk_application_window_new(app);
		canvas      = canvas_properties;

		gtk_window_set_title(window, "Drawing Area");
		gtk_window_present(window);
	}
}