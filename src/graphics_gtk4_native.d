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
	  GtkWidget *window;
	  //GtkWidget *frame;
	  //GtkWidget *drawing_area;
	  //GtkGesture *drag;
	  //GtkGesture *press;

	  window = gtk_application_window_new (app);
	  gtk_window_set_title (cast(GtkWindow*)window, "Drawing Area");

	  //g_signal_connect (window, "destroy", &close_window, null);

	  //frame = gtk_frame_new (null);
	  //gtk_window_set_child (cast(GtkWindow*)window, frame);

	  //drawing_area = gtk_drawing_area_new ();
	  ///* set a minimum size */
	  //gtk_widget_set_size_request (drawing_area, 100, 100);

	  //gtk_frame_set_child (cast(GtkFrame*)frame, drawing_area);

	  //gtk_drawing_area_set_draw_func (cast(GtkDrawingArea*)drawing_area, &draw_cb, null, null);

	  //g_signal_connect_after (drawing_area, "resize", &resize_cb, null);

	  //drag = gtk_gesture_drag_new ();
	  //gtk_gesture_single_set_button (cast(GtkGestureSingle*)drag, GdkButton.PRIMARY);
	  //gtk_widget_add_controller (drawing_area, cast(GtkEventController*)drag);
	  //g_signal_connect (drag, "drag-begin", &drag_begin, drawing_area);
	  //g_signal_connect (drag, "drag-update", &drag_update, drawing_area);
	  //g_signal_connect (drag, "drag-end", &drag_end, drawing_area);

	  //press = gtk_gesture_click_new ();
	  //gtk_gesture_single_set_button (cast(GtkGestureSingle*)press, GdkButton.SECONDARY);
	  //gtk_widget_add_controller (drawing_area, cast(GtkEventController*)press);

	  //g_signal_connect (press, "pressed", &pressed, drawing_area);

		immutable ulong refresh_period_ms = 20;
		g_timeout_add(refresh_period_ms, &timeout_callback, null);

		gtk_window_present (cast(GtkWindow*)window);
	}

	//static GtkWindow*[string] main_windows;

	override void add_window(string name, ref CanvasProperties canvas) {
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

		g_signal_connect!(GtkApplication*)(application, "activate".toStringz, &activate, cast(gpointer)this);

		int argc = 0;
		char* argv = null;
		gapplication = cast(GApplication*)application;
		auto result = g_application_run (gapplication, argc, &argv);

	}
}

