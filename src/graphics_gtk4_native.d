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
		auto self = cast(Gtk4NativeGui)user_data;

		import fairy;
		if(!fairy.running) g_application_quit(gapplication);

		if (fairy.iterate(0)) {
			import std.stdio;
			stdout.write("fairy> ");
			stdout.flush();
		}
		foreach(name, window; self.main_windows) {
			import ui;
			if (window.canvas.autorefresh) winrefresh(window.name);
		}
		return true; // continue

	}


	override void add_window(string name, ref CanvasProperties canvas) {
		main_windows[name] = MainWindow(name, &canvas, application);
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

	extern(C) static void activate (GtkApplication *app, gpointer user_data) {
		auto self = cast(Gtk4NativeGui)user_data;
		import fairy;
	 
		immutable ulong refresh_period_ms = 20;
		g_timeout_add(refresh_period_ms, &timeout_callback, null);
		foreach(name, ref canvas; session.windows) {
			self.add_window(name, canvas);
		}

	}
}

struct MainWindow 
{
import graphics;

private:
	GtkWindow*        window;
	GtkApplication*   application;
	CanvasProperties* canvas;

	string[] item_list;
	MyItemView item_view;

	string name; 
	this (string window_name, CanvasProperties* canvas_properties, GtkApplication* app)
	{
		name = window_name;
		application = app;
		window      = cast(GtkWindow*)gtk_application_window_new(app);
		canvas      = canvas_properties;

		item_view  = MyItemView(item_list);


		gtk_window_set_title(window, name.toStringz);
		gtk_window_set_child(window, cast(GtkWidget*)item_view.scrolled_window);
		gtk_window_present(window);
	}
}


struct MyItemView {
  GtkStringList* string_list;
  GtkTreeListModel* treelistmodel;
  GtkSelectionModel* selection_model;
  GtkListItemFactory *signal_list_item_factory;
  GtkColumnViewColumn* col1;
  GtkColumnView* col_view;
  GtkScrolledWindow *scrolled_window;

  this(ref string[] item_list) {

	  string_list = gtk_string_list_new(null); // this implements GListModel
	  gtk_string_list_append(string_list, "item1");
	  gtk_string_list_append(string_list, "item2");
	  gboolean passthrough;
	  gboolean autoexpand;
	  treelistmodel = cast(GtkTreeListModel*)gtk_tree_list_model_new(cast(GListModel*)string_list,
	    passthrough=false, 
	    autoexpand=false,
	    &treelist_listmodel_create,cast(void*)&this,null);
	  selection_model = cast(GtkSelectionModel*)gtk_multi_selection_new(cast(GListModel*)treelistmodel);
	  signal_list_item_factory = gtk_signal_list_item_factory_new();
	  g_signal_connect(signal_list_item_factory, "setup", &signal_list_item_factory_setup, cast(void*)&this);
	  g_signal_connect(signal_list_item_factory, "bind", &signal_list_item_factory_bind, cast(void*)&this);
	  g_signal_connect(signal_list_item_factory, "unbind", &signal_list_item_factory_unbind, cast(void*)&this);
	  g_signal_connect(signal_list_item_factory, "teardown", &signal_list_item_factory_teardown, cast(void*)&this);
	  col1 = cast(GtkColumnViewColumn*)gtk_column_view_column_new("1111", signal_list_item_factory);
	  col_view = cast(GtkColumnView*)gtk_column_view_new(selection_model);
	  gtk_column_view_append_column(col_view, col1);
	  scrolled_window = cast(GtkScrolledWindow*)gtk_scrolled_window_new();
	  gtk_scrolled_window_set_child(scrolled_window, cast(GtkWidget*)col_view);
	  gtk_widget_set_size_request (cast(GtkWidget*)scrolled_window, 300, 300);
  }


	static extern(C) GListModel* treelist_listmodel_create(void* item, void* user_data) 
	{
		MyItemView* itemview = cast(MyItemView*)user_data;
		import std.stdio, std.conv;
		auto str_obj = cast(GtkStringObject*)(item);
		auto str = gtk_string_object_get_string(str_obj).to!string;
		import core.stdc.string;
		GtkStringList* string_list = gtk_string_list_new(null); // this implements GListModel

		if (str == "item1") {
			gtk_string_list_append(string_list, "item1_a");
			gtk_string_list_append(string_list, "item1_b");
			gtk_string_list_append(string_list, "item1_c");
		} else if (str == "item2") {
			gtk_string_list_append(string_list, "item2_x");
			gtk_string_list_append(string_list, "item2_y");
			gtk_string_list_append(string_list, "item2_z");
		} else if (str == "item1_a") {
			char[100] buf;
			import core.stdc.stdio;
			foreach(i;0..1000) {
				snprintf(buf.ptr,100,"item1_%d",i);
				gtk_string_list_append(string_list, buf.ptr);
			}
		}
		return cast(GListModel*)string_list;
	}


	extern(C) static void signal_list_item_factory_setup(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		MyItemView* itemview = cast(MyItemView*)user_data;
		import std.stdio;
		//writeln("setup");
		auto expander = gtk_tree_expander_new();
		auto checkbutton = gtk_check_button_new();
		auto label = gtk_label_new(null);
		auto box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
		gtk_box_append(cast(GtkBox*)box, checkbutton);
		gtk_box_append(cast(GtkBox*)box, label);
		gtk_tree_expander_set_child(cast(GtkTreeExpander*)expander, box);
		gtk_tree_expander_set_hide_expander(cast(GtkTreeExpander*)expander, false);
		gtk_list_item_set_child((cast(GtkListItem*)object), expander);
	}

	extern(C) static void signal_list_item_factory_bind(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		MyItemView* itemview = cast(MyItemView*)user_data;
		import std.conv;
		auto list_item = cast(GtkListItem*)object;
		auto expander = cast(GtkTreeExpander*)gtk_list_item_get_child(list_item);
		auto box = cast(GtkBox*)gtk_tree_expander_get_child(expander);
		auto checkbutton = cast(GtkCheckButton*)gtk_widget_get_first_child(cast(GtkWidget*)box);
		auto label = cast(GtkLabel*)gtk_widget_get_next_sibling(cast(GtkWidget*)checkbutton);
		// get the content (string) of the list model row
		auto tree_list_row = cast(GtkTreeListRow*)gtk_list_item_get_item(list_item);
		auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(tree_list_row);
		const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
		char[64] buf;
		import core.stdc.stdio;
		snprintf(buf.ptr,64,"%s -> %d", str, gtk_list_item_get_position(list_item));
		gtk_label_set_text(label, buf.ptr);
		gtk_tree_expander_set_list_row(cast(GtkTreeExpander*)expander, tree_list_row);
	}

	extern(C) static void signal_list_item_factory_unbind(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		MyItemView* itemview = cast(MyItemView*)user_data;
		import std.stdio;
		import std.conv;
		auto item = cast(GtkListItem*)object;
		//writeln("unbind "~gtk_list_item_get_position(item).to!string);
	}

	extern(C) static void signal_list_item_factory_teardown(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		MyItemView* itemview = cast(MyItemView*)user_data;
		import std.stdio;
		//writeln("teardown");
	}

}