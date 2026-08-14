//    Fairy: Flexible Analysis of Ionizing Radiation Yields
//    Copyright (C) 2019-2026 Michael Reese

//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.

//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.

//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <https://www.gnu.org/licenses/>.

@trusted:

import gtk4_import;
import std.string : toStringz;


ulong g_signal_connect(Widget,Callback)(Widget w, const char* signal_name, Callback callback, void* user_data) 
{
	return g_signal_connect_d(cast(void*)w, signal_name, cast(void*)callback, user_data);
}

ulong g_signal_connect_swapped(Widget,Callback)(Widget w, const char* signal_name, Callback callback, void* user_data) 
{
	return g_signal_connect_swapped_d(cast(void*)w, signal_name, cast(void*)callback, user_data);
}

ulong g_signal_connect_after(Widget,Callback)(Widget w, const char* signal_name, Callback callback, void* user_data) 
{
	return g_signal_connect_after_d(cast(void*)w, signal_name, cast(void*)callback, user_data);
}




import graphics;



class Gtk4NativeGui : Gui {

	static GtkApplication* application  = null;
	static GApplication*   gapplication = null;

	static MainWindow[string] main_windows;

	static string[] removed;

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

	extern(C) static gboolean remove_callback(gpointer user_data) 
	{
		//import std.stdio;
		//writeln("removing ", Gtk4NativeGui.removed);
		auto self = cast(Gtk4NativeGui)user_data;
		import ui;
		foreach(rm_item; Gtk4NativeGui.removed) {
			ui.rm(rm_item);
		}
		Gtk4NativeGui.removed.length = 0;
		return false; // don't continue
	}

	extern(C) static gboolean update_callback(gpointer user_data) 
	{
		MainWindow main_window = cast(MainWindow)user_data;
		main_window.update_from_canvas();
		return false; // don't continue
	}
	override void update_session() {
		//import fairy;
		//foreach(window_name, ref window; GtkGui.main_windows) window.header_bar.setTitle("fairy - " ~ fairy.session.name ~ " - " ~ window_name);
	}
	override void add_window(string name, ref CanvasProperties canvas) {
		main_windows[name] = new MainWindow(name, &canvas, application);
		main_windows[name].item_view.refresh_string_list();
	}
	override void close_window(string name) {
		if (name in main_windows) {
			main_windows[name].close();
			main_windows.remove(name);
		}
	}
	override void redraw_window(string name) {
		//import std.stdio;
		//writeln("redraw window ", name);
		gtk_widget_queue_draw(cast(GtkWidget*)main_windows[name].plot_widget.drawing_area);
	}
	override void save_window(string name) { // copy window properties to canvas
		//import std.stdio;
		//writeln("save_window");
		auto window = name in main_windows;
		if (window !is null) {
			int x,y,w,h;
			if (get_window_position_and_size(window.window, &x, &y, &w, &h)) {
				//writeln(" x y w h = ", x, " ", y, " ", w, " ", h);
				window.canvas.width  = w;
				window.canvas.height = h;
				window.canvas.xpos   = x;
				window.canvas.ypos   = y;
				int width, height;
				_cairo_rectangle_int allocation;
				gtk_widget_get_allocation(cast(GtkWidget*)window.window, &allocation);
				window.canvas.width = allocation.width;
				window.canvas.height = allocation.height;
				import std.stdio;
				//writeln("save worked");
			} else {
				import std.stdio;
				//writeln("not worked");
				int width, height;
				_cairo_rectangle_int allocation;
				gtk_widget_get_allocation(cast(GtkWidget*)window.window, &allocation);
				window.canvas.width  = allocation.width;
				window.canvas.height = allocation.height;
			}
		}
	}
	override void remove_item(string name) {
		foreach(window; main_windows) {
			window.item_view.removeItem(name);
		}
	}
	override void reset_item(string name) {
		foreach(window; main_windows) {
			window.plot_widget.cairo_backend.painter.reset_item_names ~= name;
		}
	}	
	override void add_item(string name) {
		foreach(window; main_windows) {
			//import std.stdio;
			//writeln("MainWindow(",window.name,").add_item(",name,")");
			window.item_view.addItem(name, null);
		}
	}
	override void update_from_canvas(string name) {
		if (name in main_windows) {
			//main_windows[name].item_view.refresh_string_list();
			main_windows[name].update_from_canvas();
		}

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
		g_signal_connect!(GtkApplication*)(application, "shutdown", &shutdown, cast(gpointer)this);

		int argc = 0;
		char* argv = null;
		gapplication = cast(GApplication*)application;
		auto result = g_application_run (gapplication, argc, &argv);
	}

	extern(C) static void activate (GtkApplication *app, gpointer user_data) {
		auto self = cast(Gtk4NativeGui)user_data;
		import fairy;
	 
	 	g_application_hold(cast(GApplication*)app);
		immutable ulong refresh_period_ms = 20;
		g_timeout_add(refresh_period_ms, &timeout_callback, user_data);
		foreach(name, ref canvas; session.windows) {
			self.add_window(name, canvas);
		}
	}
	extern(C) static void shutdown (GtkApplication *app, gpointer user_data) {
		auto self = cast(Gtk4NativeGui)user_data;
		foreach(name; main_windows.byKey) self.save_window(name);
		import std.stdio;
		stderr.writeln("Application shutdown");
	}
}

class MainWindow 
{
import graphics;

private:
	GtkApplication*   application;
	CanvasProperties* canvas;

	GtkWindow*    window;
	GtkFrame*     frame;
	GtkBox*       toplevel;
		GtkHeaderBar* header_bar;
		GtkLabel*     header_title;
		GtkPaned*     paned;
	MyItemView    item_view;
	MyPlotWidget  plot_widget;

	GtkButton*      button_menu_open;
	GMenu*          menu_top;
	GtkPopoverMenu* menu_popover;
	GSimpleAction*  menu_action_fairy_quit;
	GSimpleAction*  menu_action_window_new;
	GSimpleAction*  menu_action_window_close;
	GSimpleAction*  menu_action_session_open;
	GSimpleAction*  menu_action_session_save;

	string[]        fairy_quit_accels;
	const(char*)[]  fairy_quit_accels_;
	string[]        new_window_accels;
	const(char*)[]  new_window_accels_;
	string[]        close_window_accels;
	const(char*)[]  close_window_accels_;
	string[]        open_session_accels;
	const(char*)[]  open_session_accels_;
	string[]        save_session_accels;
	const(char*)[]  save_session_accels_;


	string name; 
	this (string window_name, CanvasProperties* canvas_properties, GtkApplication* app)
	{
		name = window_name;
		application = app;
		canvas      = canvas_properties;



		window      = cast(GtkWindow*)gtk_application_window_new(app);
		gtk_window_set_hide_on_close(window, true);
		g_signal_connect(window, "hide",    &hide_callback,    cast(void*)&name);
		g_signal_connect(window, "realize", &realize_callback, cast(void*)canvas);
		gtk_window_set_default_size(window, canvas.width, canvas.height);
		toplevel    = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_VERTICAL,0);
		header_bar  = cast(GtkHeaderBar*)gtk_header_bar_new();
		header_title= cast(GtkLabel*)gtk_label_new(("fairy - " ~ window_name).toStringz);
		frame       = cast(GtkFrame*)gtk_frame_new(null);
		paned       = cast(GtkPaned*)gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
		item_view   = MyItemView(this);
		plot_widget = MyPlotWidget(name, canvas_properties);

		///////////////////////////////
		// main window menu actions
		///////////////////////////////

		// quit program
		menu_action_fairy_quit = g_simple_action_new("quit_fairy", null);
		static extern(C) void menu_action_fairy_quit_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			import ui;
			ui.quit();
		}
		g_signal_connect(menu_action_fairy_quit, "activate", &menu_action_fairy_quit_activate_callback, null);
		g_action_map_add_action(cast(GActionMap*)window, cast(GAction*)menu_action_fairy_quit);


		// create new window
		menu_action_window_new = g_simple_action_new("new_window", null);
		static extern(C) void menu_action_window_new_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			import ui, std.conv;
			for (int i = 0; i < 100; ++i) {
				try { ui.win("window"~i.to!string); break; } 
				catch(Exception e) {}
			}
		}
		g_signal_connect(menu_action_window_new, "activate", &menu_action_window_new_activate_callback, null);
		g_action_map_add_action(cast(GActionMap*)window, cast(GAction*)menu_action_window_new);

		// close window
		menu_action_window_close = g_simple_action_new("close_window", null);
		static extern(C) void menu_action_window_close_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			import ui;
			auto window = cast(MainWindow)user_data;
			ui.close(window.name);
		}
		g_signal_connect(menu_action_window_close, "activate", &menu_action_window_close_activate_callback, cast(void*)this);
		g_action_map_add_action(cast(GActionMap*)window, cast(GAction*)menu_action_window_close);

		// open session
		menu_action_session_open = g_simple_action_new("open_session", null);
		static extern(C) void on_open_response(GtkDialog* dialog, int response) {
			import std.stdio, std.conv;
			stderr.writeln("on_open_response");
			if (response == GTK_RESPONSE_ACCEPT) {
				auto chooser = cast(GtkFileChooser*)dialog;
				GFile* file = gtk_file_chooser_get_file(chooser);
				string pathname = g_file_get_path(file).to!string;
				writeln("on_open_response: ", pathname);
				import ui;
				ui.session_open(pathname);
				g_object_unref(file);
			} else {
				writeln("no accept");
			}
			gtk_window_destroy(cast(GtkWindow*)dialog);
		}
		static extern(C) void menu_action_session_open_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			//auto window = cast(MainWindow)user_data;
			GtkFileChooserAction action = GTK_FILE_CHOOSER_ACTION_OPEN;
			auto window = cast(MainWindow)user_data;
			GtkWidget* dialog = gtk_file_chooser_dialog_new("Open File", window.window, action,
				                                            "Open", GTK_RESPONSE_ACCEPT,
				                                            null);

			gtk_window_present(cast(GtkWindow*)dialog);
			g_signal_connect(dialog, "response", &on_open_response, null);
		}
		g_signal_connect(menu_action_session_open, "activate", &menu_action_session_open_activate_callback, cast(void*)this);
		g_action_map_add_action(cast(GActionMap*)window, cast(GAction*)menu_action_session_open);

		// save session
		menu_action_session_save = g_simple_action_new("save_session", null);
		static extern(C) void on_session_save_response(GtkDialog* dialog, int response) {
			import std.stdio, std.conv;
			stderr.writeln("on_session_save_response");
			if (response == GTK_RESPONSE_ACCEPT) {
				auto chooser = cast(GtkFileChooser*)dialog;
				GFile* file = gtk_file_chooser_get_file(chooser);
				string pathname = g_file_get_path(file).to!string;
				writeln("on_session_save_response: ", pathname);
				import ui;
				ui.session_save(pathname);
				g_object_unref(file);
			} else {
				writeln("no accept");
			}
			gtk_window_destroy(cast(GtkWindow*)dialog);
		}
		static extern(C) void menu_action_session_save_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			//auto window = cast(MainWindow)user_data;
			GtkFileChooserAction action = GTK_FILE_CHOOSER_ACTION_SAVE;
			auto window = cast(MainWindow)user_data;
			GtkWidget* dialog = gtk_file_chooser_dialog_new("Open File", window.window, action,
				                                            "Save", GTK_RESPONSE_ACCEPT,
				                                            null);

			gtk_window_present(cast(GtkWindow*)dialog);
			g_signal_connect(dialog, "response", &on_session_save_response, null);
		}
		g_signal_connect(menu_action_session_save, "activate", &menu_action_session_save_activate_callback, cast(void*)this);
		g_action_map_add_action(cast(GActionMap*)window, cast(GAction*)menu_action_session_save);


		menu_top = cast(GMenu*)g_menu_new();
		g_menu_append(menu_top, "new window",     "win.new_window");
		g_menu_append(menu_top, "close window",     "win.close_window");
		g_menu_append(menu_top, "open session",    "win.open_session");
		g_menu_append(menu_top, "save session",    "win.save_session");
		g_menu_append(menu_top, "quit program",    "win.quit_fairy");

		menu_popover = cast(GtkPopoverMenu*)gtk_popover_menu_new_from_model(cast(GMenuModel*)menu_top);
		//gtk_popover_menu_set_position(menu_popover, GTK_POS_BOTTOM);

		button_menu_open = cast(GtkButton*)gtk_button_new();
		gtk_widget_set_parent(cast(GtkWidget*)menu_popover, cast(GtkWidget*)button_menu_open);		

		gtk_button_set_icon_name(button_menu_open, "open-menu-symbolic");
		gtk_header_bar_pack_start(header_bar, cast(GtkWidget*)button_menu_open);
		static extern(C) void button_menu_open_clicked_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			import std.stdio;
			writeln("clicked callback");
			auto menu_popover = cast(GtkWidget*)user_data;
			gtk_widget_set_visible(menu_popover, true);
		}
		g_signal_connect(button_menu_open, "clicked", &button_menu_open_clicked_callback, menu_popover);
		//application.setAccelsForAction("win.new_window", ["<Control>n"]);
		new_window_accels   = ["<Control>n"];    new_window_accels_ = [ new_window_accels[0].ptr,   null ];
		close_window_accels = ["<Control>w"];  close_window_accels_ = [ close_window_accels[0].ptr, null ];
		open_session_accels = ["<Control>o"];  open_session_accels_ = [ open_session_accels[0].ptr, null ];
		save_session_accels = ["<Control>s"];  save_session_accels_ = [ save_session_accels[0].ptr, null ];
		fairy_quit_accels   = ["<Control>q"];  fairy_quit_accels_   = [ fairy_quit_accels[0].ptr, null ];
		gtk_application_set_accels_for_action(app, "win.new_window",   new_window_accels_.ptr);
		gtk_application_set_accels_for_action(app, "win.close_window", close_window_accels_.ptr);
		gtk_application_set_accels_for_action(app, "win.open_session", open_session_accels_.ptr);
		gtk_application_set_accels_for_action(app, "win.save_session", save_session_accels_.ptr);
		gtk_application_set_accels_for_action(app, "win.quit_fairy",   fairy_quit_accels_.ptr);


		gtk_window_set_decorated(window, true); // enable window decorations 

		gtk_header_bar_set_title_widget(header_bar, cast(GtkWidget*)header_title);
		gtk_header_bar_set_show_title_buttons(header_bar, true);
		gtk_frame_set_child (cast(GtkFrame*)frame, cast(GtkWidget*)toplevel);
		//gtk_box_append(toplevel, cast(GtkWidget*)header_bar);
		gtk_box_append(toplevel, cast(GtkWidget*)paned);
		gtk_paned_set_position(paned, 200);
		gtk_paned_set_start_child(paned, cast(GtkWidget*)item_view.scrolled_window);
		gtk_paned_set_resize_start_child(paned, false);
		gtk_paned_set_shrink_start_child(paned, true);
		gtk_paned_set_end_child(paned, cast(GtkWidget*)plot_widget.main_box);
		gtk_paned_set_resize_end_child(paned, true);
		gtk_paned_set_shrink_end_child(paned, false);


		gtk_window_set_title(window, name.toStringz);
		//gtk_window_set_child(window, cast(GtkWidget*)item_view.scrolled_window);
		gtk_window_set_child(window, cast(GtkWidget*)frame);
		gtk_window_set_titlebar(window, cast(GtkWidget*)header_bar);
		// Tried this because when deactivating window decoration in the constructor the window raises on mouse click (which is undesired)
		// The following code was an attempt to restore the behavior with window decorations (but it didn't work) 
		//g_signal_connect!(GtkWindow*)(window, "realize", &on_realize_callback, cast(gpointer)this);


		gtk_window_present(window);

		if (gdk_is_x11_display(gdk_display_get_default())) {
			// workaround to the fact that GTK4 does not provide API for repositioning windows
			GtkNative *native = gtk_widget_get_native(cast(GtkWidget*)window);
			assert (native !is null, "cannot get GtkNative"); 
			GdkSurface *surface = gtk_native_get_surface(native);
			assert (surface !is null, "cannot get GdkSurface"); 
			Window w = gdk_x11_surface_get_xid(surface);
			GdkDisplay* displayGdk = gdk_display_get_default();
			assert (displayGdk !is null, "cannot get GdkDisplay"); 
			Display* display = gdk_x11_display_get_xdisplay(displayGdk);
			assert (display !is null, "cannot get X11 Display");
			XMoveWindow(display, w, canvas.xpos, canvas.ypos);
			XFlush(display);
		}

	}
	extern(C) static void on_realize_callback (GtkApplication *app, gpointer user_data) {
		auto self = cast(MainWindow)user_data;

		// Tried the following because when deactivating window decoration in the constructor the window raises on mouse click (which is undesired)
		// The following code was an attempt to restore the behavior with window decorations (but it didn't work) 

		// change window properties to NORMAL window. If not doen GTK overrides the behavior of the window manager (like not putting window in foreground on mouse click)
		// compiles and runs without error, but still does not produce the desired effect...
		GtkNative *native = gtk_widget_get_native(cast(GtkWidget*)self.window);
		assert (native !is null, "cannot get GtkNative"); 
		GdkSurface *surface = gtk_native_get_surface(native);
		assert (surface !is null, "cannot get GdkSurface"); 
		Window w = gdk_x11_surface_get_xid(surface);
		GdkDisplay* displayGdk = gdk_display_get_default();
		assert (displayGdk !is null, "cannot get GdkDisplay"); 
		Display* display = gdk_x11_display_get_xdisplay(displayGdk);
		assert (display !is null, "cannot get X11 Display");

		//// set windwo type normal  
		//Atom atom = gdk_x11_get_xatom_by_name_for_display(displayGdk, "_NET_WM_WINDOW_TYPE_NORMAL");
		//Atom atom0 = gdk_x11_get_xatom_by_name_for_display(displayGdk, "_NET_WM_WINDOW_TYPE");
		//XChangeProperty(display, w, atom0, XaAtom.XA_ATOM_, 32, PropMode.Replace, cast(guchar*)&atom, 1);		

		//// Set focus state
		//Atom state_atom = gdk_x11_get_xatom_by_name_for_display(displayGdk, "_NET_WM_STATE");
		//Atom focused_atom = gdk_x11_get_xatom_by_name_for_display(displayGdk, "_NET_WM_STATE_FOCUSED");

		//XChangeProperty(display, w, state_atom, XaAtom.XA_ATOM_, 32, PropMode.Replace, cast(guchar*)&focused_atom, 1);
		//// end of setting window to NORMAL (must be before the call to gtk_window_present(window))
	}


	void update_from_canvas() {
		//assert(item_view !is null);
		//item_view.sync_with_session();
		item_view.sync_with_canvas(canvas);
		plot_widget.sync_with_canvas(canvas);
	}	
	void close() {
		gtk_window_close(cast(GtkWindow*)window);
	}
	extern(C) static void hide_callback(GtkWidget*, gpointer user_data) {
		import fairy;
		string name = *(cast(string*)user_data);
		try {
			if ((name in Gtk4NativeGui.main_windows) !is null) Gtk4NativeGui.main_windows.remove(name);
			fairy.session.close_window(name);
		} catch (Exception e) {
			// nothing
			// we land here if the close was executed from command line 
			// then fairy.sesssion.close_window is executed once called from command line
			// and again if the window gets a Hide-notification
		}
	}
	extern(C) static void realize_callback(GtkWidget* window, gpointer user_data) {
		auto canvas = cast(CanvasProperties*)user_data;
		if (set_window_position(cast(GtkWindow*)window, canvas.xpos, canvas.ypos)) {
			//import std.stdio;
			//writeln("++worked");
		} else {
			//import std.stdio;
			//writeln("not worked");
		}
	}

}


struct MyItemView {
	struct Tree
	{
		string fullname;
		bool expanded;
		Tree[string] children;
		Tree* find_node(string fullname) {
			Tree* find_helper(Tree* node, string[] parts) {
				//import std.stdio;
				//writeln("find_helper ", fullname, "   ", parts);
				if (parts.length == 0) return node;
				auto child = parts[0] in node.children;
				if (child is null) return null;
				//writeln(" recurse down into child ", child.fullname);
				return find_helper(child, parts[1..$]);
			}
			import std.stdio;
			import std.array;
			auto parts = fullname.split('/');
			//writeln("find ", fullname, "  in node ", this.fullname);
			if (parts[0] != this.fullname) return null;
			return find_helper(&this, parts[1..$]);
		}
		void print(int depth = 0) {
			import std.array, std.algorithm;
			if (children.length == 0) return;
			foreach(child_name; children.byKey.array.sort) {
				import std.stdio;
				foreach(i;0..depth) write("   ");
				writeln(child_name, "    ", children[child_name].fullname);
				children[child_name].print(depth+1);
			}
		}
		void add_helper(string[] parts) {
			if (parts.length == 0) return;
			if ((parts[0] in children) is null) 
				children[parts[0]] = Tree(fullname~'/'~parts[0]);
			if (parts.length == 1) return;
			children[parts[0]].add_helper(parts[1..$]);
		}
		void add(string fullname) {
			//import std.stdio;
			//writeln("Tree.add(", fullname, ")");
			import std.algorithm, std.range;
			add_helper(fullname.split('/'));
		}

		// return true if the last child was removed
		bool remove_helper(string[] parts) {
			if (parts.length == 0) return true;
			auto child = parts[0] in children;
			if (child !is null && child.remove_helper(parts[1..$])) children.remove(parts[0]);
			if (children.length == 0) return true;
			return false;
		}
		void remove(string fullname) {
			import std.algorithm, std.range;
			remove_helper(fullname.split('/'));
		}
	}
	auto root_node = new Tree("fairy");

	import fairy, item;
	import std.datetime, std.datetime.stopwatch;
	StopWatch time_since_last_refresh_string_list;
	bool refresh_string_list_is_sceduled;
	extern(C) static gboolean scheculed_refresh_string_list(gpointer user_data) {
		MainWindow main_window = cast(MainWindow)user_data;
		main_window.item_view.refresh_string_list();
		main_window.item_view.time_since_last_refresh_string_list.reset();
		main_window.item_view.refresh_string_list_is_sceduled = false;
		return false; // execute only once
	}
	void addItem(string fullname, Item item) {
		root_node.add(fullname);
		import core.time;
		if (time_since_last_refresh_string_list.peek.total!"msecs" > 250) {
			refresh_string_list();
			main_window.item_view.time_since_last_refresh_string_list.reset();
		} else {
			if (!refresh_string_list_is_sceduled) {
				refresh_string_list_is_sceduled = true;
				g_timeout_add(250, &scheculed_refresh_string_list, cast(gpointer)main_window);
			}
		}
	}
	void removeItem(string fullname) {
		root_node.remove(fullname);
		refresh_string_list();
		import std.algorithm;
		if (main_window.canvas.itemnames.canFind(fullname)) {
			string[] itemnames;
			foreach(itemname; main_window.canvas.itemnames) {
				if (itemname != fullname) {
					itemnames ~= itemname;
				}
			}
			main_window.canvas.itemnames = itemnames;
		}
		gtk_widget_queue_draw(cast(GtkWidget*)main_window.plot_widget.drawing_area);
	}

	void refresh_string_list(bool expand_parents_of_selected = true) {
		import std.stdio, std.array, std.algorithm;
		// remember the expansion state (iterate over all items in the list)
		for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)treelistmodel); ++i) {
			GtkTreeListRow* row = gtk_tree_list_model_get_row(treelistmodel, i);
			if (gtk_tree_list_row_is_expandable(row)) {
				auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
				const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
				import std.conv;
				auto fullname = str.to!string;
				auto node = root_node.find_node(fullname);
				if (node !is null) node.expanded = gtk_tree_list_row_get_expanded(row)?true:false;
				//writeln("row ", i,  "(", fullname, "): ", gtk_tree_list_row_get_expanded(row));
			}
		}

		// this expands all parents of all shown items in the item_view
		// the purpose is that when a session is opened, it is obvious which items are shown in the item_view 
		// this is a nice feature but in combination with elderpt creating a lot of histograms this slows 
		// down the startup of elderpt significantly => TODO find out why and improve it! Deacitvate it for now.
		
		if (expand_parents_of_selected)
		{
			foreach(itemname; main_window.canvas.itemnames) {
				auto fullitemname = ["fairy"] ~ itemname.split('/');
				while (fullitemname.length > 0) {
					import std.conv;
					auto node = root_node.find_node(fullitemname.join('/').to!string);
					if (node !is null) node.expanded = true;
					fullitemname = fullitemname[0..$-1];
				}
			}
		}


		// clear the string list
		gtk_string_list_splice(string_list, 
			                   0, g_list_model_get_n_items(cast(GListModel*)string_list),
			                   null);
		// refill the string list
		foreach (child_name; root_node.children.byKey.array.sort) {
			gtk_string_list_append(string_list, root_node.children[child_name].fullname.toStringz);
		}

		// apply the expansion state (iterate over all items in the list)
		for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)treelistmodel); ++i) {
			GtkTreeListRow* row = gtk_tree_list_model_get_row(treelistmodel, i);
			if (gtk_tree_list_row_is_expandable(row)) {
				auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
				const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
				import std.conv;
				auto fullname = str.to!string;
				if (root_node.find_node(fullname).expanded) {
					gtk_tree_list_row_set_expanded(row,true);
				}
				//writeln("row ", i,  "(", fullname, "): ", gtk_tree_list_row_get_expanded(row));
			}
		}
	}


	GtkStringList*       string_list;
	ulong string_list_signal_setup, string_list_signal_bind, string_list_signal_unbind, string_list_signal_teardown;
	GtkTreeListModel*    treelistmodel;
	GtkSelectionModel*   selection_model;
	GtkListItemFactory*  signal_list_item_factory;
	GtkColumnViewColumn* col1;
	GtkColumnView*       col_view;
	GtkScrolledWindow*   scrolled_window;

	// the actions
	GSimpleAction* show_all_selected;
	GSimpleAction* hide_all_selected;
	GSimpleAction* reset_all_selected;
	GSimpleAction* expand_all_recursive;
	GSimpleAction* remove_all_selected;
	GSimpleAction* itemname_to_clipboard;
	GSimpleAction* hist2d_projection_x;
	GSimpleAction* hist2d_projection_y;

	GMenu*           menu;        // the menu structure
	GtkPopoverMenu*  popup;       // the widget
	GtkGestureClick* right_click; // the action that makes the popup widget appear

	MainWindow main_window; // reference to main_window we live in

	this(MainWindow window) {
		main_window = window;
		string_list = gtk_string_list_new(null); // this implements GListModel
		time_since_last_refresh_string_list = StopWatch(AutoStart.yes);

		// sync with session
		import fairy;
		import std.stdio, std.array, std.algorithm;
		foreach (item_name; session.items.byKey) {
			//import std.stdio;
			//writeln("MainWindow this root_node.add(", item_name, ")");
			root_node.add(item_name);
		}
		//writeln("=========== print root node ==========");
		//root_node.print();
		//writeln("=========== print root node ==========");
		foreach (child_name; root_node.children.byKey.array.sort) {
			gtk_string_list_append(string_list, root_node.children[child_name].fullname.toStringz);
		}

		//gtk_string_list_append(string_list, "item1");
		//gtk_string_list_append(string_list, "item2");
		gboolean passthrough;
		gboolean autoexpand;
		treelistmodel = cast(GtkTreeListModel*)gtk_tree_list_model_new(cast(GListModel*)string_list,
		                                                               passthrough=false, 
		                                                               autoexpand=false,
		                                                               &treelist_listmodel_create,
		                                                               cast(void*)main_window,
		                                                               null);
		selection_model = cast(GtkSelectionModel*)gtk_multi_selection_new(cast(GListModel*)treelistmodel);
		signal_list_item_factory    = gtk_signal_list_item_factory_new();
		string_list_signal_setup    = g_signal_connect(signal_list_item_factory, "setup",    &signal_list_item_factory_setup,    cast(void*)main_window);
		string_list_signal_bind     = g_signal_connect(signal_list_item_factory, "bind",     &signal_list_item_factory_bind,     cast(void*)main_window);
		string_list_signal_unbind   = g_signal_connect(signal_list_item_factory, "unbind",   &signal_list_item_factory_unbind,   cast(void*)main_window);
		string_list_signal_teardown = g_signal_connect(signal_list_item_factory, "teardown", &signal_list_item_factory_teardown, cast(void*)main_window);
		col1 = cast(GtkColumnViewColumn*)gtk_column_view_column_new("Items", signal_list_item_factory);
		col_view = cast(GtkColumnView*)gtk_column_view_new(selection_model);
		gtk_column_view_append_column(col_view, col1);
		scrolled_window = cast(GtkScrolledWindow*)gtk_scrolled_window_new();
		gtk_scrolled_window_set_child(scrolled_window, cast(GtkWidget*)col_view);
		gtk_widget_set_size_request (cast(GtkWidget*)scrolled_window, 100, 100);


		//static extern(C) void show_selected_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
		//	import std.stdio;
		//	writeln("show selected");
		//	MainWindow main_window = cast(MainWindow)user_data;
		//	//GtkBitset* selected = gtk_selection_model_get_selection(cast(GtkSelectionModel*)main_window.item_view.selection_model);
		//	//auto n_selected = gtk_bitset_get_size(selected);
		//	//writeln("n_selected = ", n_selected);
		//	//for (int j = 0; j < n_selected; ++j) {
		//	//	int i = gtk_bitset_get_nth(selected, j);
		//	//	GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
		//	for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
		//		GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
		//		//writeln("expbandable ", gtk_tree_list_row_is_expandable(row));
		//		//if (gtk_tree_list_row_is_expandable(row)) {
		//		//	gtk_tree_list_row_set_expanded(row,true);
		//			if (gtk_selection_model_is_selected(cast(GtkSelectionModel*)main_window.item_view.selection_model, i)) {
		//				auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
		//				const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
		//				import std.conv;
		//				auto fullname = str.to!string;
		//				writeln("fullname ", fullname);
		//				import ui;
		//				ui.show(fullname[6..$], main_window.name, "true");
		//			}

		//			//main_window.item_view.root_node.find_node(fullname).expanded = true;
		//		//}
		//	}
		//	//main_window.item_view.refresh_string_list();
		//	//g_object_unref(cast(GObject*)selected);
		//}
		static extern(C) void show_all_selected_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			MainWindow main_window = cast(MainWindow)user_data;
			for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
				GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
				if (gtk_selection_model_is_selected(cast(GtkSelectionModel*)main_window.item_view.selection_model, i)) {
					auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
					const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
					import std.conv;
					auto fullname = str.to!string;
					import ui;
					ui.show(fullname[6..$], main_window.name, "all");
				}
			}
		}
		static extern(C) void hide_all_selected_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			MainWindow main_window = cast(MainWindow)user_data;
			for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
				GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
				if (gtk_selection_model_is_selected(cast(GtkSelectionModel*)main_window.item_view.selection_model, i)) {
					auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
					const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
					import std.conv;
					auto fullname = str.to!string;
					import ui;
					ui.show(fullname[6..$], main_window.name, "none");
				}
			}
		}
		static extern(C) void reset_all_selected_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			MainWindow main_window = cast(MainWindow)user_data;
			for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
				GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
				if (gtk_selection_model_is_selected(cast(GtkSelectionModel*)main_window.item_view.selection_model, i)) {
					auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
					const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
					import std.conv;
					auto fullname = str.to!string;
					fullname = fullname[6..$];
					import ui;
					if (fairy.session.items.byKey.canFind(fullname)) ui.reset(fullname);
				}
			}
		}
		static extern(C) void expand_all_recursive_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			MainWindow main_window = cast(MainWindow)user_data;
			for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
				GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
				if (gtk_tree_list_row_is_expandable(row)) {
					gtk_tree_list_row_set_expanded(row,true);
				}
			}
		}
		static extern(C) void remove_all_selected_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			MainWindow main_window = cast(MainWindow)user_data;
			for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
				GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
				if (gtk_selection_model_is_selected(cast(GtkSelectionModel*)main_window.item_view.selection_model, i)) {
					auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
					const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
					import std.conv;
					auto fullname = str.to!string;
					fullname = fullname[6..$];
					import fairy;
					if (fairy.session.items.byKey.canFind(fullname)) Gtk4NativeGui.removed ~= fullname;
				}
			}
			immutable ulong refresh_period_ms = 1;
			g_timeout_add(refresh_period_ms, &Gtk4NativeGui.remove_callback, null);

		}


		static extern(C) void itemname_to_clipboard_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			MainWindow main_window = cast(MainWindow)user_data;

			GdkClipboard *clipboard = gdk_display_get_clipboard(gdk_display_get_default());

			for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
				GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
				if (gtk_selection_model_is_selected(cast(GtkSelectionModel*)main_window.item_view.selection_model, i)) {
					auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
					const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
					import std.conv;
					auto fullname = str.to!string;
					fullname = fullname[6..$];
					gdk_clipboard_set_text(clipboard,fullname.toStringz);
				}
			}
		}

		static extern(C) void hist2d_projection_xy_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data, char xy) {
			MainWindow main_window = cast(MainWindow)user_data;

			for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
				GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
				if (gtk_selection_model_is_selected(cast(GtkSelectionModel*)main_window.item_view.selection_model, i)) {
					import std.stdio;
					auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(row);
					const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);
					import std.conv;
					auto fullname = str.to!string;
					fullname = fullname[6..$];
					import fairy, ui;
					if (session.items.byKey.canFind(fullname)) {
						import histogram, gate;
						auto source = cast(Hist2ProjectionSource)session.items[fullname].item;
						if (source !is null) {
						//writeln("found selected projection source: ", fullname);
							auto gatename = fullname ~ "_"~xy~"_gate";
							auto projname = fullname ~ "_"~xy~"_projection";
							int dim = (xy=='x')?1:0;
							auto left  = main_window.canvas.transform[dim].min; 
							auto right = main_window.canvas.transform[dim].max;
							auto w = right-left;
							left += 3*w/8;
							right -= 3*w/8; 
							import cmdline;
							xy = (xy=='x')?'y':'x';
							string windowname;
							foreach(n  ;0..100) {
								windowname = "projection"~n.to!string;
								if ((windowname in Gtk4NativeGui.main_windows) is null) break;
							}
							string command =
								"gate1d "~gatename~" "~left.to!string~" "~right.to!string~" "~xy~"\n"~
								"hist2projector "~projname~" "~fullname~" "~gatename~"\n"~
								"win       "~windowname~"\n"~
								"show      "~projname~" "~windowname~"\n"~
								"winpoll   "~windowname~"\n"~
								"autoscale "~windowname~" y"~"\n"~
								"winfit    "~windowname~"\n"~
								"colorbar  "~windowname~"\n"~
								"show      "~gatename~" "~main_window.name;
							thisTid.send(cmdline.Command(command, thisTid));									
						}
					}
				}
			}
		}
		static extern(C) void hist2d_projection_x_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			hist2d_projection_xy_activate_callback(self, parameter, user_data, 'x');
		}
		static extern(C) void hist2d_projection_y_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
			hist2d_projection_xy_activate_callback(self, parameter, user_data, 'y');
		}


		//// for some reasond this crashes
		//static extern(C) void collapse_all_recursive_activate_callback(GSimpleAction* self, GVariant* parameter, gpointer user_data) {
		//	MainWindow main_window = cast(MainWindow)user_data;
		//	//for (int i = g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel)-1; i>=0; --i) {
		//	for (int i = 0; i < g_list_model_get_n_items(cast(GListModel*)main_window.item_view.treelistmodel); ++i) {
		//		GtkTreeListRow* row = gtk_tree_list_model_get_row(main_window.item_view.treelistmodel, i);
		//		if (gtk_tree_list_row_is_expandable(row)) {
		//			gtk_tree_list_row_set_expanded(row,false); 
		//		}
		//	}
		//}

		// define window level actions
		//show_selected = cast(GSimpleAction*)g_simple_action_new("show_selected", null);
		//g_signal_connect(show_selected, "activate", &show_selected_activate_callback, cast(void*)main_window);
		//g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)show_selected);

		show_all_selected = cast(GSimpleAction*)g_simple_action_new("show_all_selected", null);
		g_signal_connect(show_all_selected, "activate", &show_all_selected_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)show_all_selected);

		hide_all_selected = cast(GSimpleAction*)g_simple_action_new("hide_all_selected", null);
		g_signal_connect(hide_all_selected, "activate", &hide_all_selected_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)hide_all_selected);

		reset_all_selected = cast(GSimpleAction*)g_simple_action_new("reset_all_selected", null);
		g_signal_connect(reset_all_selected, "activate", &reset_all_selected_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)reset_all_selected);

		expand_all_recursive = cast(GSimpleAction*)g_simple_action_new("expand_all_recursive", null);
		g_signal_connect(expand_all_recursive, "activate", &expand_all_recursive_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)expand_all_recursive);

		remove_all_selected = cast(GSimpleAction*)g_simple_action_new("remove_all_selected", null);
		g_signal_connect(remove_all_selected, "activate", &remove_all_selected_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)remove_all_selected);

		itemname_to_clipboard = cast(GSimpleAction*)g_simple_action_new("itemname_to_clipboard", null);
		g_signal_connect(itemname_to_clipboard, "activate", &itemname_to_clipboard_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)itemname_to_clipboard);

		hist2d_projection_y = cast(GSimpleAction*)g_simple_action_new("hist2d_projection_y", null);
		g_signal_connect(hist2d_projection_y, "activate", &hist2d_projection_y_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)hist2d_projection_y);

		hist2d_projection_x = cast(GSimpleAction*)g_simple_action_new("hist2d_projection_x", null);
		g_signal_connect(hist2d_projection_x, "activate", &hist2d_projection_x_activate_callback, cast(void*)main_window);
		g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)hist2d_projection_x);


		//collapse_all_recursive = cast(GSimpleAction*)g_simple_action_new("collapse_all_recursive", null);
		//g_signal_connect(collapse_all_recursive, "activate", &collapse_all_recursive_activate_callback, cast(void*)main_window);
		//g_action_map_add_action(cast(GActionMap*)main_window.window, cast(GAction*)collapse_all_recursive);

		// build the popup menu contents
		menu = cast(GMenu*)g_menu_new();
		//g_menu_append(menu, "show only selected","win.show_selected");
		g_menu_append(menu, "show selected",     "win.show_all_selected");
		g_menu_append(menu, "hide selected",     "win.hide_all_selected");
		g_menu_append(menu, "reset selected",    "win.reset_all_selected");
		g_menu_append(menu, "expand all",        "win.expand_all_recursive");
		g_menu_append(menu, "remove selected",   "win.remove_all_selected");
		g_menu_append(menu, "copy to clipboard", "win.itemname_to_clipboard");
		g_menu_append(menu, "hist2d project y",  "win.hist2d_projection_y");
		g_menu_append(menu, "hist2d project x",  "win.hist2d_projection_x");

		//g_menu_append(menu, "collapse all",    "win.collapse_all_recursive");
		popup = cast(GtkPopoverMenu*)gtk_popover_menu_new_from_model(cast(GMenuModel*)menu);

		// create the gesture that makes the popup appear
		right_click = cast(GtkGestureClick*)gtk_gesture_click_new();
		gtk_widget_set_parent(cast(GtkWidget*)popup, cast(GtkWidget*)col_view);		
		gtk_gesture_single_set_button(cast(GtkGestureSingle*)right_click, GdkButton.SECONDARY);
		extern(C) static void col_view_right_click_callback(GtkGestureClick* self, int nPress,
		                                                    gdouble x, gdouble y, gpointer user_data) {
			MainWindow main_window = cast(MainWindow)user_data;
			gtk_widget_set_visible(cast(GtkWidget*)main_window.item_view.popup, true);
			auto rect = GdkRectangle(cast(int)x, cast(int)y, 4,4);
			gtk_popover_set_pointing_to(cast(GtkPopover*)main_window.item_view.popup, &rect);
			gtk_popover_set_has_arrow(cast(GtkPopover*)main_window.item_view.popup, false);
			gtk_popover_set_position(cast(GtkPopover*)main_window.item_view.popup, GTK_POS_BOTTOM );
		}
		g_signal_connect(right_click, "pressed", &col_view_right_click_callback, cast(void*)main_window);
		// connect the gesture to the col_view widget
		gtk_widget_add_controller(cast(GtkWidget*)col_view, cast(GtkEventController*)right_click);

	

	}
	

	static extern(C) GListModel* treelist_listmodel_create(void* item, void* user_data) 
	{
		MainWindow main_window = cast(MainWindow)user_data;
		Tree* root_node = main_window.item_view.root_node;

		// extract fullname (stored as string_object inside of item)
		auto str_obj = cast(GtkStringObject*)(item);
		import std.conv;
		auto str = gtk_string_object_get_string(str_obj).to!string;

		// prepare the new string_list
		GtkStringList* string_list = gtk_string_list_new(null); // this implements GListModel
		auto node = root_node.find_node(str);
		if (node !is null) {
			import std.array, std.algorithm;
			foreach(child_name; (*node).children.byKey.array.sort) {
				gtk_string_list_append(string_list, node.children[child_name].fullname.toStringz);
			}
		}
		return cast(GListModel*)string_list;
	}

	extern(C) static void signal_list_item_factory_setup(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		import std.stdio;
		//writeln("setup");
		MainWindow main_window = cast(MainWindow)user_data;
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
	extern(C) static void signal_list_item_factory_teardown(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		import std.stdio;
		//writeln("teardown");
		MainWindow main_window = cast(MainWindow)user_data;
		gtk_list_item_set_child((cast(GtkListItem*)object), null);
	}

	class TreeViewRowData {
		MainWindow main_window;
		string fullname;
		GtkCheckButton* checkbutton;
		ulong signal_checked;
		this(MainWindow window, string itemname, GtkCheckButton* ckbutton) {
			main_window = window;
			fullname = itemname;
			checkbutton = ckbutton;
		}
	}
	TreeViewRowData[GtkListItem*] treeview_row_data;

	void sync_with_canvas(CanvasProperties *canvas) {
		foreach(list_item, ref rowdata; treeview_row_data) {
			import std.algorithm;
			string item_name = rowdata.fullname[6..$]~'/';
			bool do_check = false; // if only one of the children is not checked set this to false
			// set of all children of fullname in session
			auto n_in_session = session.items.byKey.filter!(itemname=>itemname.startsWith(item_name) || itemname == item_name[0..$-1]).count;
			// set of all children of fullname in canvas
			auto n_in_canvas = main_window.canvas.itemnames.filter!(itemname=>itemname.startsWith(item_name) || itemname == item_name[0..$-1]).count;
			if (n_in_canvas && n_in_canvas == n_in_session) do_check = true;
			g_signal_handler_disconnect(cast(GObject*)rowdata.checkbutton, rowdata.signal_checked);
			gtk_check_button_set_active(rowdata.checkbutton, do_check);
			rowdata.signal_checked = g_signal_connect(rowdata.checkbutton, "toggled", &tree_view_checkbutton_toggle, cast(void*)rowdata);


			//if (canvas.itemnames.canFind(rowdata.fullname[6..$])) {
			//	gtk_check_button_set_active(rowdata.checkbutton, true);
			//} else {
			//	gtk_check_button_set_active(rowdata.checkbutton, false);
			//}
		}
	}

	extern(C) static void tree_view_checkbutton_toggle(GtkCheckButton* self, gpointer user_data) {
		import fairy,ui; 
		TreeViewRowData data = cast(TreeViewRowData)user_data;
		auto itemname = data.fullname[6..$];
		ui.show(itemname, data.main_window.name, gtk_check_button_get_active(self)?"all":"none");
	}

	extern(C) static void signal_list_item_factory_bind(GtkSignalListItemFactory* self, GObject* item, gpointer user_data) 
	{
		auto list_item   = cast(GtkListItem*)item;
		auto main_window = cast(MainWindow)user_data;
		Tree* root_node = main_window.item_view.root_node;

		// get checkbutton to connect the "toggled" signal
		// and also the string of the string_list to show the correct label
		auto expander = cast(GtkTreeExpander*)gtk_list_item_get_child(list_item);
		auto box = cast(GtkBox*)gtk_tree_expander_get_child(expander);
		auto checkbutton = cast(GtkCheckButton*)gtk_widget_get_first_child(cast(GtkWidget*)box);
		auto label = cast(GtkLabel*)gtk_widget_get_next_sibling(cast(GtkWidget*)checkbutton);

		 // extract the string get the content (string) of the list model row
		auto tree_list_row = cast(GtkTreeListRow*)gtk_list_item_get_item(list_item);
		auto str_obj  = cast(GtkStringObject*)gtk_tree_list_row_get_item(tree_list_row);
		const char* str = gtk_string_object_get_string(cast(GtkStringObject*)str_obj);

		// format the label string
		char[64] buf;
		import core.stdc.stdio;
		import std.array, std.string, std.conv;
		auto fullname = str.to!string;
		snprintf(buf.ptr,64,"%s", fullname.split('/')[$-1].toStringz);
		//snprintf(buf.ptr,64,"%s -> %d", fullname.split('/')[$-1].toStringz, gtk_list_item_get_position(list_item));
		gtk_label_set_text(label, buf.ptr);
		gtk_tree_expander_set_list_row(cast(GtkTreeExpander*)expander, tree_list_row);
		
		// decide if the expander has to be shown (only if there are children)
		auto node = root_node.find_node(fullname);
		//if (node.children.length) gtk_tree_expander_set_hide_expander(cast(GtkTreeExpander*)expander, false);
		gtk_tree_expander_set_hide_expander(cast(GtkTreeExpander*)expander, node.children.length?false:true);

		import std.algorithm;
		string item_name = fullname[6..$]~'/';
		bool do_check = false; // if only one of the children is not checked set this to false
		// set of all children of fullname in session
		auto n_in_session = session.items.byKey.filter!(itemname=>itemname.startsWith(item_name) || itemname == item_name[0..$-1]).count;
		// set of all children of fullname in canvas
		auto n_in_canvas = main_window.canvas.itemnames.filter!(itemname=>itemname.startsWith(item_name) || itemname == item_name[0..$-1]).count;
		if (n_in_canvas && n_in_canvas == n_in_session) do_check = true;
		gtk_check_button_set_active(checkbutton, do_check);
		//if (main_window.canvas.itemnames.canFind(fullname[6..$])) {
		//	gtk_check_button_set_active(checkbutton, true);
		//}

		// make storage for checkbutton data and remember the signal to be able to disconnect it later
		main_window.item_view.treeview_row_data[list_item] = new TreeViewRowData(main_window, fullname, checkbutton);
		main_window.item_view.treeview_row_data[list_item].signal_checked = g_signal_connect(checkbutton, "toggled", &tree_view_checkbutton_toggle, cast(void*)main_window.item_view.treeview_row_data[list_item]);
	}

	extern(C) static void signal_list_item_factory_unbind(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		auto list_item   = cast(GtkListItem*)object;
		auto main_window = cast(MainWindow)user_data;
		// get checkbutton do disconnect the signal
		auto expander      = cast(GtkTreeExpander*)gtk_list_item_get_child    (list_item);
		auto box           = cast(GtkBox*)         gtk_tree_expander_get_child(expander);
		auto checkbutton   = cast(GtkCheckButton*) gtk_widget_get_first_child (cast(GtkWidget*)box);
		// disconnect the signal
		g_signal_handler_disconnect(cast(GObject*)checkbutton, main_window.item_view.treeview_row_data[list_item].signal_checked);
		main_window.item_view.treeview_row_data.remove(list_item);
	}


}


struct MyPlotWidget {

	string window_name;

	GtkBox* main_box;
	
	GtkDrawingArea *drawing_area;
		GtkEventControllerMotion* motion_controller;
		GtkEventControllerScroll* scroll_controller;
		GtkEventControllerKey*    key_controller;
		GtkGestureClick* left_click;
		GtkGestureClick* mid_click;
		GtkGestureClick* right_click;
	
	GtkSeparator* separator;

	GtkScrolledWindow* controls_scrolled_window;

		GtkBox*         controls_box;

			GtkCheckButton* check_autorefresh;
			GtkButton*      button_refresh;

			GtkSeparator*   sep1;
			
			GtkBox* box_fit_log;
			GtkBox* box_fit; GtkLabel*  label_fit;      GtkCheckButton* check_fit_x, check_fit_y, check_fit_z, check_fit_zoom;
			GtkBox* box_log; GtkLabel*  label_log;      GtkCheckButton* check_log_x, check_log_y, check_log_z;

			GtkSeparator*   sep2;

			GtkBox* box_grid_nums;
			GtkBox* box_grid; GtkLabel* label_grid;      GtkCheckButton* check_grid_x, check_grid_y,  check_grid_top,  check_xlabel,   check_fill;
			GtkBox* box_nums; GtkLabel* label_nums;      GtkCheckButton* check_nums_x, check_nums_y,  check_nums_top,  check_ylabel,   check_stat;

			GtkSeparator*   sep3;

			GtkBox* box_colorbar_overlay;
				GtkCheckButton* check_colorbar;
				GtkCheckButton* radio_overlay;

			GtkSpinButton* spin_n_columns;

			GtkBox* box_rowmajor_colmajor;
				GtkCheckButton* radio_rowmajor;
				GtkCheckButton* radio_colmajor;

			GtkSeparator*   sep4;

			GtkDrawingArea* mouse_pos;


	CanvasProperties* canvas; 
	CairoBackend cairo_backend;

	void sync_with_canvas(CanvasProperties *canvas) {
		gtk_check_button_set_active(check_autorefresh, canvas.autorefresh);
		gtk_check_button_set_active(check_fit_x,       canvas.autoscale[0]);
		gtk_check_button_set_active(check_fit_y,       canvas.autoscale[1]);
		gtk_check_button_set_active(check_fit_z,       canvas.autoscale[2]);
		gtk_check_button_set_active(check_fit_zoom,    canvas.zoom);
		gtk_check_button_set_active(check_log_x,       canvas.transform[0].logscale);
		gtk_check_button_set_active(check_log_y,       canvas.transform[1].logscale);
		gtk_check_button_set_active(check_log_z,       canvas.transform[2].logscale);
		gtk_check_button_set_active(check_grid_x,      canvas.grid[0]);
		gtk_check_button_set_active(check_grid_y,      canvas.grid[1]);
		gtk_check_button_set_active(check_grid_top,    canvas.grid_ontop);
		gtk_check_button_set_active(check_fill,        canvas.filled);
		gtk_check_button_set_active(check_nums_x,      canvas.numbers[0]);
		gtk_check_button_set_active(check_nums_y,      canvas.numbers[1]);
		gtk_check_button_set_active(check_nums_top,    canvas.numbers_ontop);
		gtk_check_button_set_active(check_stat,        canvas.stats);
		gtk_check_button_set_active(check_colorbar,    canvas.color_bar);
		gtk_spin_button_set_value(spin_n_columns, canvas.columns_or_rows);
		if (canvas.display_mode == DisplayMode.overlay) gtk_check_button_set_active(radio_overlay,  true);
		if (canvas.display_mode == DisplayMode.rows)    gtk_check_button_set_active(radio_rowmajor, true);
		if (canvas.display_mode == DisplayMode.columns) gtk_check_button_set_active(radio_colmajor, true);
	}

	extern(C)
	static void mousePosDrawFunc(GtkDrawingArea* drawingArea, cairo_t* cr, int width, int height, void* userData) {
		//import std.stdio;
		//writeln("mousePosDrawFunc");
		CairoBackend backend = (cast(CairoBackend)userData);
		GtkAllocation size;
		gtk_widget_get_allocation(cast(GtkWidget*)backend.drawing_area, &size);
		cairo_set_source_rgba(cr, 0,0,0,1);

		cairo_set_font_size(cr, 14);
		static char[256] buffer;
		import core.stdc.stdio;

		snprintf(buffer.ptr, buffer.length, "x = %.9g", backend.mouse_pos[0]);
		cairo_move_to(cr, 20,20);
		cairo_show_text(cr, buffer.ptr);
		cairo_stroke(cr);			

		snprintf(buffer.ptr, buffer.length, "y = %.9g", backend.mouse_pos[1]);
		cairo_move_to(cr, 180,20);
		cairo_show_text(cr, buffer.ptr);
		cairo_stroke(cr);			

		snprintf(buffer.ptr, buffer.length, "z = %.9g", backend.mouse_pos[2]);
		cairo_move_to(cr, 340,20);
		cairo_show_text(cr, buffer.ptr);
		cairo_stroke(cr);			

		if (backend.mouse_value !is double.init) {
			snprintf(buffer.ptr, buffer.length, "value = %.9g", backend.mouse_value);
			cairo_move_to(cr, 20,40);
			cairo_show_text(cr, buffer.ptr);
			cairo_stroke(cr);			
		}

		if (backend.mouse_itemname !is null) {
			import std.string;
			snprintf(buffer.ptr, buffer.length, "%s", backend.mouse_itemname.toStringz);
			cairo_move_to(cr, 180,40);
			cairo_show_text(cr, buffer.ptr);
			cairo_stroke(cr);			
		}
	}

	extern(C) 
	static void drawFunc(GtkDrawingArea* drawingArea, cairo_t* cr, int width, int height, void* userData) {
		CairoBackend backend = (cast(CairoBackend)userData);
		GtkAllocation size;
		gtk_widget_get_allocation(cast(GtkWidget*)backend.drawing_area, &size);
		//gtk_widget_get_allocation(cast(GtkWidget*)drawingArea, &size);

		backend.set_cr(cr, size.width, size.height);
		backend.canvas.width = size.width;
		backend.canvas.height = size.height;
		backend.painter.draw_content();
	}
	extern(C) 
	static void destroyNotify(void *data) {
	}

	// mouse motion
	extern(C)
	static void drawing_area_motion_callback(GtkEventControllerMotion* self,
	                                         gdouble x, gdouble y, gpointer user_data) {
		bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
		bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
		CairoBackend cairo_backend = cast(CairoBackend)user_data;
		//import std.stdio;
		//writeln("motion ", ctrl, " ", gtk_event_controller_get_current_event_state(cast(GtkEventController*)self));
		cairo_backend.painter.mouse_motion(x,y,cairo_backend,ctrl,shift);
	}
	// mouse enter
	extern(C) static void drawing_area_enter_callback(GtkEventControllerMotion* self,
	                                         gdouble x, gdouble y, gpointer user_data) {
		CairoBackend cairo_backend = cast(CairoBackend)user_data;
		//import std.stdio;
		//writeln("enter");
		gtk_widget_grab_focus(cast(GtkWidget*)cairo_backend.drawing_area);
	}
	// mouse leaving
	extern(C) static void drawing_area_leave_callback(GtkEventControllerMotion* self,
	                                         gdouble x, gdouble y, gpointer user_data) {
		CairoBackend cairo_backend = cast(CairoBackend)user_data;
		//import std.stdio;
		//writeln("leave");
		//cairo_backend.painter.mouse_leaving(cairo_backend);
	}

	// mouse wheel
	extern(C)
	static void drawing_area_scroll_callback(GtkEventControllerScroll* self,
	                                         gdouble dx, gdouble dy, gpointer user_data) {
		bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
		bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
		CairoBackend cairo_backend = cast(CairoBackend)user_data;
		cairo_backend.painter.scroll(dx,dy,ctrl,shift);
	}


	// keyboard shortcut
	extern(C)
	static void drawing_area_key_pressed_callback(GtkEventControllerKey* self,
	                                              guint keyval, guint keycode, GdkModifierType state, gpointer user_data) {
		import ui;
		string name = *(cast(string*)user_data);
		switch(keyval) {
			case '1': .. case '9': gtk_spin_button_set_value(Gtk4NativeGui.main_windows[name].plot_widget.spin_n_columns, keyval-'0'); break;
			case 'u': ui.winrefresh(name);                                                                                             break;
			case 'p': ui.winpoll(name);                                                                                                break;
			case 'q': ui.winzoom(name,1*1.2);                                                                                          break;
			case 'e': ui.winzoom(name,1/1.1666666666);                                                                                 break;
			case 'a': ui.winmove(name,'x',-0.2);                                                                                       break;
			case 'd': ui.winmove(name,'x',+0.2);                                                                                       break;
			case 's': ui.winmove(name,'y',-0.2);                                                                                       break;
			case 'w': ui.winmove(name,'y',+0.2);                                                                                       break;
			case 'o': ui.overlay(name);                                                                                                break;
			case 'b': ui.colorbar(name);                                                                                               break;
			case 'c': gtk_check_button_set_active(Gtk4NativeGui.main_windows[name].plot_widget.radio_colmajor, true);                  break;
			case 'r': gtk_check_button_set_active(Gtk4NativeGui.main_windows[name].plot_widget.radio_rowmajor, true);                  break;
			case 'z': ui.autoscale(name, 'z', "toggle");                                                                               break;
			case 'x': ui.autoscale(name, 'x', "toggle");                                                                               break;
			case 'y': ui.autoscale(name, 'y', "toggle");                                                                               break;
			case 'l': ui.logscale (name, Gtk4NativeGui.main_windows[name].plot_widget.canvas.dim==2?'z':'y', "toggle");                break;
			case 'f': ui.winfit(name);                                                                                                 break;
			case 'm': ui.winautozoom(name, "toggle");                      break;
			case 't': ui.winshowstats(name, "toggle");                     break;
			case 'i': ui.windrawfilled(name, "toggle");                    break;
			default: {}
		}
	}


	this(string name, CanvasProperties *canvas_properties) {
		import ui;
		import std.stdio;
		//writeln("MyPlotWidget constructor");
		window_name  = name.dup;
		drawing_area = cast(GtkDrawingArea*)gtk_drawing_area_new();
		gtk_widget_set_can_focus(cast(GtkWidget*)drawing_area, true);
		gtk_widget_set_focusable(cast(GtkWidget*)drawing_area, true);
		mouse_pos    = cast(GtkDrawingArea*)gtk_drawing_area_new();

		canvas        = canvas_properties;
		cairo_backend = new CairoBackend(drawing_area, canvas, mouse_pos);

		main_box = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
		controls_box = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
		controls_scrolled_window = cast(GtkScrolledWindow*)gtk_scrolled_window_new();
		gtk_scrolled_window_set_propagate_natural_width(controls_scrolled_window, true);
		gtk_scrolled_window_set_propagate_natural_height(controls_scrolled_window, true);
		gtk_scrolled_window_set_child(controls_scrolled_window, cast(GtkWidget*)controls_box);

		check_autorefresh = cast(GtkCheckButton*)gtk_check_button_new_with_label("auto\nrefr.");
		extern(C) static void check_autorefresh_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.winpoll(*(cast(string*)user_data), gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		g_signal_connect(check_autorefresh, "toggled", &check_autorefresh_toggled, cast(void*)&window_name);
		gtk_check_button_set_active(check_autorefresh, canvas.autorefresh);

		button_refresh = cast(GtkButton*)gtk_button_new_with_label("refr.");
		// reduce padding top and bottom from button
			//GtkCssProvider* provider = gtk_css_provider_new();
			//gtk_css_provider_load_from_data(provider, "#custom_button { border: none; margin: 0px; padding-top: 0px; padding-bottom: 0px; min-height: 10px; height: 10px; }", -1);
			//GdkDisplay* display = gdk_display_get_default();
			//gtk_style_context_add_provider_for_display(display, cast(GtkStyleProvider*)provider, 800/+GTK_STYLE_PROVIDER_PRIORITY_USER+/);
			//// Set the button's CSS name to the custom style (ID selector)
			//gtk_widget_set_name(cast(GtkWidget*)button_refresh, "custom_button");

		gtk_widget_set_size_request(cast(GtkWidget*)button_refresh,20,20);
		extern(C) static void button_refresh_clicked(GtkButton* self,  gpointer user_data) {
			ui.winrefresh(*(cast(string*)user_data)); 
		}
		g_signal_connect(button_refresh, "clicked", &button_refresh_clicked, cast(void*)&window_name);

		gtk_box_append(controls_box, cast(GtkWidget*)button_refresh);
		gtk_box_append(controls_box, cast(GtkWidget*)check_autorefresh);

		sep1 = cast(GtkSeparator*)gtk_separator_new(GTK_ORIENTATION_VERTICAL);
		gtk_box_append(controls_box, cast(GtkWidget*)sep1);

		// fit (autoscale) for all 3 axis
		label_fit = cast(GtkLabel*)gtk_label_new("fit:");
		check_fit_x = cast(GtkCheckButton*)gtk_check_button_new_with_label("X");
		check_fit_y = cast(GtkCheckButton*)gtk_check_button_new_with_label("Y");
		check_fit_z = cast(GtkCheckButton*)gtk_check_button_new_with_label("Z");
		check_fit_zoom = cast(GtkCheckButton*)gtk_check_button_new_with_label("zm");
		gtk_check_button_set_active(check_fit_x, canvas.autoscale[0]);
		gtk_check_button_set_active(check_fit_y, canvas.autoscale[1]);
		gtk_check_button_set_active(check_fit_z, canvas.autoscale[2]);
		gtk_check_button_set_active(check_fit_zoom, canvas.zoom);
		extern(C) static void check_fit_x_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.autoscale(*(cast(string*)user_data), 'x', gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_fit_y_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.autoscale(*(cast(string*)user_data), 'y', gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_fit_z_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.autoscale(*(cast(string*)user_data), 'z', gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_fit_zoom_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.winautozoom(*(cast(string*)user_data), gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		g_signal_connect(check_fit_x, "toggled", &check_fit_x_toggled, cast(void*)&window_name);
		g_signal_connect(check_fit_y, "toggled", &check_fit_y_toggled, cast(void*)&window_name);
		g_signal_connect(check_fit_z, "toggled", &check_fit_z_toggled, cast(void*)&window_name);
		g_signal_connect(check_fit_zoom, "toggled", &check_fit_zoom_toggled, cast(void*)&window_name);

		// logscale for all 3 axis
		label_log = cast(GtkLabel*)gtk_label_new("log:");
		check_log_x = cast(GtkCheckButton*)gtk_check_button_new_with_label("X");
		check_log_y = cast(GtkCheckButton*)gtk_check_button_new_with_label("Y");
		check_log_z = cast(GtkCheckButton*)gtk_check_button_new_with_label("Z");
		gtk_check_button_set_active(check_log_x, canvas.transform[0].logscale);
		gtk_check_button_set_active(check_log_y, canvas.transform[1].logscale);
		gtk_check_button_set_active(check_log_z, canvas.transform[2].logscale);
		extern(C) static void check_log_x_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.logscale(*(cast(string*)user_data), 'x', gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_log_y_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.logscale(*(cast(string*)user_data), 'y', gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_log_z_toggled(GtkToggleButton* self,  gpointer user_data) {
			ui.logscale(*(cast(string*)user_data), 'z', gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		g_signal_connect(check_log_x, "toggled", &check_log_x_toggled, cast(void*)&window_name);
		g_signal_connect(check_log_y, "toggled", &check_log_y_toggled, cast(void*)&window_name);
		g_signal_connect(check_log_z, "toggled", &check_log_z_toggled, cast(void*)&window_name);

		box_fit = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
		box_log = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
		box_fit_log = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
		gtk_box_append(box_fit_log, cast(GtkWidget*)box_fit);
		gtk_box_append(box_fit_log, cast(GtkWidget*)box_log);

		gtk_widget_set_size_request(cast(GtkWidget*)label_fit, 30,0);
		gtk_box_append(box_fit, cast(GtkWidget*)label_fit);
		gtk_box_append(box_fit, cast(GtkWidget*)check_fit_x);
		gtk_box_append(box_fit, cast(GtkWidget*)check_fit_y);
		gtk_box_append(box_fit, cast(GtkWidget*)check_fit_z);
		gtk_box_append(box_fit, cast(GtkWidget*)check_fit_zoom);

		gtk_widget_set_size_request(cast(GtkWidget*)label_log, 30,0);
		gtk_box_append(box_log, cast(GtkWidget*)label_log);
		gtk_box_append(box_log, cast(GtkWidget*)check_log_x);
		gtk_box_append(box_log, cast(GtkWidget*)check_log_y);
		gtk_box_append(box_log, cast(GtkWidget*)check_log_z);

		gtk_box_append(controls_box, cast(GtkWidget*)box_fit_log);

		sep2 = cast(GtkSeparator*)gtk_separator_new(GTK_ORIENTATION_VERTICAL);
		gtk_box_append(controls_box, cast(GtkWidget*)sep2);



		// grid for all 3 axis
		label_grid = cast(GtkLabel*)gtk_label_new("grid:");
		check_grid_x = cast(GtkCheckButton*)gtk_check_button_new_with_label("X");
		check_grid_y = cast(GtkCheckButton*)gtk_check_button_new_with_label("Y");
		check_grid_top = cast(GtkCheckButton*)gtk_check_button_new_with_label("top");
		check_xlabel = cast(GtkCheckButton*)gtk_check_button_new_with_label("xlab");
		check_ylabel = cast(GtkCheckButton*)gtk_check_button_new_with_label("ylab");
		check_fill = cast(GtkCheckButton*)gtk_check_button_new_with_label("fill");
		check_stat = cast(GtkCheckButton*)gtk_check_button_new_with_label("st");
		gtk_check_button_set_active(check_grid_x, canvas.grid[0]);
		gtk_check_button_set_active(check_grid_y, canvas.grid[1]);
		gtk_check_button_set_active(check_grid_top, canvas.grid_ontop);
		gtk_check_button_set_active(check_xlabel, canvas.axislabel[0]);
		gtk_check_button_set_active(check_ylabel, canvas.axislabel[1]);
		gtk_check_button_set_active(check_fill, canvas.filled);
		gtk_check_button_set_active(check_stat, canvas.stats);
		extern(C) static void check_grid_x_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.grid(*(cast(string*)user_data), "x", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_grid_y_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.grid(*(cast(string*)user_data), "y", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_grid_top_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.grid(*(cast(string*)user_data), "top", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_xlabel_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.label(*(cast(string*)user_data), "x", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_ylabel_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.label(*(cast(string*)user_data), "y", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_fill_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.windrawfilled(*(cast(string*)user_data), gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_stat_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.winshowstats(*(cast(string*)user_data), gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		g_signal_connect(check_grid_x,   "toggled", &check_grid_x_toggled,   cast(void*)&window_name);
		g_signal_connect(check_grid_y,   "toggled", &check_grid_y_toggled,   cast(void*)&window_name);
		g_signal_connect(check_grid_top, "toggled", &check_grid_top_toggled, cast(void*)&window_name);
		g_signal_connect(check_xlabel,   "toggled", &check_xlabel_toggled,   cast(void*)&window_name);
		g_signal_connect(check_ylabel,   "toggled", &check_ylabel_toggled,   cast(void*)&window_name);
		g_signal_connect(check_fill,     "toggled", &check_fill_toggled,     cast(void*)&window_name);
		g_signal_connect(check_stat,     "toggled", &check_stat_toggled,     cast(void*)&window_name);

		// numbers for all 3 axis
		label_nums = cast(GtkLabel*)gtk_label_new("nums:");
		check_nums_x = cast(GtkCheckButton*)gtk_check_button_new_with_label("X");
		check_nums_y = cast(GtkCheckButton*)gtk_check_button_new_with_label("Y");
		check_nums_top = cast(GtkCheckButton*)gtk_check_button_new_with_label("top");
		gtk_check_button_set_active(check_nums_x, canvas.numbers[0]);
		gtk_check_button_set_active(check_nums_y, canvas.numbers[1]);
		gtk_check_button_set_active(check_nums_top, canvas.numbers_ontop);
		extern(C) static void check_nums_x_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.numbers(*(cast(string*)user_data), "x", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_nums_y_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.numbers(*(cast(string*)user_data), "y", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		extern(C) static void check_nums_top_toggled(GtkToggleButton* self, gpointer user_data) {
			ui.numbers(*(cast(string*)user_data), "top", gtk_check_button_get_active(cast(GtkCheckButton*)self)?"true":"false");
		}
		g_signal_connect(check_nums_x, "toggled", &check_nums_x_toggled, cast(void*)&window_name);
		g_signal_connect(check_nums_y, "toggled", &check_nums_y_toggled, cast(void*)&window_name);
		g_signal_connect(check_nums_top, "toggled", &check_nums_top_toggled, cast(void*)&window_name);

		box_grid = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
		box_nums = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
		box_grid_nums = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
		gtk_box_append(box_grid_nums, cast(GtkWidget*)box_grid);
		gtk_box_append(box_grid_nums, cast(GtkWidget*)box_nums);

		gtk_widget_set_size_request(cast(GtkWidget*)label_grid, 50,0);
		gtk_box_append(box_grid, cast(GtkWidget*)label_grid);
		gtk_box_append(box_grid, cast(GtkWidget*)check_grid_x);
		gtk_box_append(box_grid, cast(GtkWidget*)check_grid_y);
		gtk_box_append(box_grid, cast(GtkWidget*)check_grid_top);
		gtk_box_append(box_grid, cast(GtkWidget*)check_xlabel);
		gtk_box_append(box_grid, cast(GtkWidget*)check_fill);

		gtk_widget_set_size_request(cast(GtkWidget*)label_nums, 50,0);
		gtk_box_append(box_nums, cast(GtkWidget*)label_nums);
		gtk_box_append(box_nums, cast(GtkWidget*)check_nums_x);
		gtk_box_append(box_nums, cast(GtkWidget*)check_nums_y);
		gtk_box_append(box_nums, cast(GtkWidget*)check_nums_top);
		gtk_box_append(box_nums, cast(GtkWidget*)check_ylabel);
		gtk_box_append(box_nums, cast(GtkWidget*)check_stat);

		gtk_box_append(controls_box, cast(GtkWidget*)box_grid_nums);


		sep3 = cast(GtkSeparator*)gtk_separator_new(GTK_ORIENTATION_VERTICAL);
		gtk_box_append(controls_box, cast(GtkWidget*)sep3);


		check_colorbar = cast(GtkCheckButton*)gtk_check_button_new_with_label("colorbar");
		gtk_check_button_set_active(check_colorbar, canvas.color_bar);
		radio_overlay = cast(GtkCheckButton*)gtk_check_button_new_with_label("overlay");
		radio_rowmajor = cast(GtkCheckButton*)gtk_check_button_new_with_label("rows");
		radio_colmajor = cast(GtkCheckButton*)gtk_check_button_new_with_label("columns");
		gtk_check_button_set_group(radio_rowmajor, radio_overlay);
		gtk_check_button_set_group(radio_colmajor, radio_overlay);

		if (canvas.display_mode == DisplayMode.overlay) gtk_check_button_set_active(radio_overlay, true);
		if (canvas.display_mode == DisplayMode.rows)    gtk_check_button_set_active(radio_rowmajor, true);
		if (canvas.display_mode == DisplayMode.columns) gtk_check_button_set_active(radio_colmajor, true);


		box_colorbar_overlay = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_VERTICAL,0);
		gtk_box_append(box_colorbar_overlay, cast(GtkWidget*)check_colorbar);
		gtk_box_append(box_colorbar_overlay, cast(GtkWidget*)radio_overlay);

		spin_n_columns = cast(GtkSpinButton*)gtk_spin_button_new_with_range(1,50,1);
		
		box_rowmajor_colmajor = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_VERTICAL,0);
		gtk_box_append(box_rowmajor_colmajor, cast(GtkWidget*)radio_rowmajor);
		gtk_box_append(box_rowmajor_colmajor, cast(GtkWidget*)radio_colmajor);

		extern(C) static void check_colorbar_toggled(GtkCheckButton* self, gpointer user_data) {
			string name = *(cast(string*)user_data);
			ui.colorbar(name, gtk_check_button_get_active(self)?"true":"false");
		}
		g_signal_connect(check_colorbar, "toggled", &check_colorbar_toggled, cast(void*)&window_name);

		extern(C) static void radio_overlay_toggled(GtkCheckButton* self, gpointer user_data) {
			string name = *(cast(string*)user_data);
			if (gtk_check_button_get_active(self)) ui.overlay(name);
		}
		g_signal_connect(radio_overlay, "toggled", &radio_overlay_toggled, cast(void*)&window_name);

		extern(C) static void radio_rowmajor_toggled(GtkCheckButton* self, gpointer user_data) {
			string name = *(cast(string*)user_data);
			if (gtk_check_button_get_active(self)) ui.rows(name, cast(int)gtk_spin_button_get_value(Gtk4NativeGui.main_windows[name].plot_widget.spin_n_columns));
		}
		g_signal_connect(radio_rowmajor, "toggled", &radio_rowmajor_toggled, cast(void*)&window_name);

		extern(C) static void radio_colmajor_toggled(GtkCheckButton* self, gpointer user_data) {
			string name = *(cast(string*)user_data);
			if (gtk_check_button_get_active(self)) ui.columns(name, cast(int)gtk_spin_button_get_value(Gtk4NativeGui.main_windows[name].plot_widget.spin_n_columns));
		}
		g_signal_connect(radio_colmajor, "toggled", &radio_colmajor_toggled, cast(void*)&window_name);




		gtk_spin_button_set_value(spin_n_columns, canvas.columns_or_rows);

		gtk_box_append(controls_box, cast(GtkWidget*)box_colorbar_overlay);
		gtk_box_append(controls_box, cast(GtkWidget*)spin_n_columns);
		gtk_box_append(controls_box, cast(GtkWidget*)box_rowmajor_colmajor);


		extern(C) static void spin_n_columns_changed(GtkSpinButton* self, gpointer user_data) {
			string name = *(cast(string*)user_data);
			if (Gtk4NativeGui.main_windows[name].plot_widget.canvas.display_mode == DisplayMode.rows)    ui.rows   (name, cast(int)gtk_spin_button_get_value(self));
			if (Gtk4NativeGui.main_windows[name].plot_widget.canvas.display_mode == DisplayMode.columns) ui.columns(name, cast(int)gtk_spin_button_get_value(self));
		}
		g_signal_connect(spin_n_columns, "value-changed", &spin_n_columns_changed, cast(void*)&window_name);

		sep4 = cast(GtkSeparator*)gtk_separator_new(GTK_ORIENTATION_VERTICAL);
		gtk_box_append(controls_box, cast(GtkWidget*)sep4);


		gtk_widget_set_size_request(cast(GtkWidget*)mouse_pos, 600, 20);
		gtk_drawing_area_set_draw_func(mouse_pos, &mousePosDrawFunc, cast(void*)cairo_backend, null);
		gtk_box_append(controls_box, cast(GtkWidget*)mouse_pos);
		import std.string;
		gtk_widget_set_hexpand(cast(GtkWidget*)drawing_area, true);
		gtk_widget_set_vexpand(cast(GtkWidget*)drawing_area, true);
		gtk_box_append(main_box, cast(GtkWidget*)drawing_area);
		gtk_widget_set_size_request(cast(GtkWidget*)drawing_area, 100, 50);
		gtk_drawing_area_set_draw_func(drawing_area, &drawFunc, cast(void*)cairo_backend, &destroyNotify);
		separator = cast(GtkSeparator*)gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
		gtk_box_append(main_box, cast(GtkWidget*)separator);
		gtk_box_append(main_box, cast(GtkWidget*)controls_scrolled_window);


		// attach motion controller to drawing_area widget
		motion_controller = cast(GtkEventControllerMotion*) gtk_event_controller_motion_new();
		g_signal_connect(motion_controller, "motion", &drawing_area_motion_callback, cast(void*)cairo_backend);
		g_signal_connect(motion_controller, "enter", &drawing_area_enter_callback, cast(void*)cairo_backend);
		g_signal_connect(motion_controller, "leave", &drawing_area_leave_callback, cast(void*)cairo_backend);
		gtk_widget_add_controller(cast(GtkWidget*)drawing_area, cast(GtkEventController*)motion_controller);

		// attach scroll controller to drawing_area widget
		scroll_controller = cast(GtkEventControllerScroll*) gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL | GTK_EVENT_CONTROLLER_SCROLL_HORIZONTAL);
		g_signal_connect(scroll_controller, "scroll", &drawing_area_scroll_callback, cast(void*)cairo_backend);
		gtk_widget_add_controller(cast(GtkWidget*)drawing_area, cast(GtkEventController*)scroll_controller);

		key_controller = cast(GtkEventControllerKey*)gtk_event_controller_key_new();
		g_signal_connect(key_controller, "key-pressed", &drawing_area_key_pressed_callback, cast(void*)&window_name);
		gtk_widget_add_controller(cast(GtkWidget*)drawing_area, cast(GtkEventController*)key_controller);



		// left mouse button
		extern(C) static void drawing_area_left_click_callback(GtkGestureClick* self, int nPress,
		                                              gdouble x, gdouble y, gpointer user_data) {
			bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
			bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
			CairoBackend cairo_backend = cast(CairoBackend)user_data;
			cairo_backend.painter.left_button_pressed(nPress,x,y,cairo_backend,ctrl,shift);
		}
		extern(C) static void drawing_area_left_release_callback(GtkGestureClick* self, int nPress,
		                                              gdouble x, gdouble y, gpointer user_data) {
			bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
			bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
			CairoBackend cairo_backend = cast(CairoBackend)user_data;
			cairo_backend.painter.left_button_released(nPress,x,y,ctrl,shift);
		}
		left_click = cast(GtkGestureClick*)gtk_gesture_click_new();
		gtk_gesture_single_set_button(cast(GtkGestureSingle*)left_click, GdkButton.PRIMARY);
		g_signal_connect(left_click, "pressed", &drawing_area_left_click_callback, cast(void*)cairo_backend);
		g_signal_connect(left_click, "released", &drawing_area_left_release_callback, cast(void*)cairo_backend);
		gtk_widget_add_controller(cast(GtkWidget*)drawing_area, cast(GtkEventController*)left_click);

		// middle mouse button
		extern(C) static void drawing_area_mid_click_callback(GtkGestureClick* self, int nPress,
		                                              gdouble x, gdouble y, gpointer user_data) {
			bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
			bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
			CairoBackend cairo_backend = cast(CairoBackend)user_data;
			cairo_backend.painter.mid_button_pressed(nPress,x,y,cairo_backend,ctrl,shift);
		}
		extern(C) static void drawing_area_mid_release_callback(GtkGestureClick* self, int nPress,
		                                              gdouble x, gdouble y, gpointer user_data) {
			bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
			bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
			CairoBackend cairo_backend = cast(CairoBackend)user_data;
			cairo_backend.painter.mid_button_released(nPress,x,y,ctrl,shift);
		}
		mid_click = cast(GtkGestureClick*)gtk_gesture_click_new();
		gtk_gesture_single_set_button(cast(GtkGestureSingle*)mid_click, GdkButton.MIDDLE);
		g_signal_connect(mid_click, "pressed", &drawing_area_mid_click_callback, cast(void*)cairo_backend);
		g_signal_connect(mid_click, "released", &drawing_area_mid_release_callback, cast(void*)cairo_backend);
		gtk_widget_add_controller(cast(GtkWidget*)drawing_area, cast(GtkEventController*)mid_click);

		// right mouse button
		extern(C) static void drawing_area_right_click_callback(GtkGestureClick* self, int nPress,
		                                              gdouble x, gdouble y, gpointer user_data) {
			bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
			bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
			CairoBackend cairo_backend = cast(CairoBackend)user_data;
			GtkAllocation size;
			gtk_widget_get_allocation(cast(GtkWidget*)cairo_backend.drawing_area, &size);
			cairo_backend.painter.canvas.width  = size.width;
			cairo_backend.painter.canvas.height = size.height;
			cairo_backend.painter.right_button_pressed(nPress,x,y,ctrl,shift);
		}
		extern(C) static void drawing_area_right_release_callback(GtkGestureClick* self, int nPress,
		                                              gdouble x, gdouble y, gpointer user_data) {
			bool ctrl  = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_CONTROL_MASK) != 0;
			bool shift = (gtk_event_controller_get_current_event_state(cast(GtkEventController*)self) & GDK_SHIFT_MASK  ) != 0;
			CairoBackend cairo_backend = cast(CairoBackend)user_data;
			cairo_backend.painter.right_button_released(nPress,x,y,ctrl,shift);
		}
		right_click = cast(GtkGestureClick*)gtk_gesture_click_new();
		gtk_gesture_single_set_button(cast(GtkGestureSingle*)right_click, GdkButton.SECONDARY);
		g_signal_connect(right_click, "pressed", &drawing_area_right_click_callback, cast(void*)cairo_backend);
		g_signal_connect(right_click, "released", &drawing_area_right_release_callback, cast(void*)cairo_backend);
		gtk_widget_add_controller(cast(GtkWidget*)drawing_area, cast(GtkEventController*)right_click);

	}
}








class CairoBackend : BackendInterface
{
	GtkDrawingArea *drawing_area;
	CanvasProperties *canvas;
	GtkDrawingArea *mouse_pos_drawing_area;
	CanvasPainter painter;
	this (GtkDrawingArea *area, CanvasProperties *canvas_properties, GtkDrawingArea* mpda) {
		drawing_area = area;
		canvas       = canvas_properties;
		mouse_pos_drawing_area = mpda;
		painter      = CanvasPainter(canvas, this);
	}

	double[3] mouse_pos;
	double    mouse_value;
	string    mouse_itemname;

	cairo_t* cr;
	int width, height;
	void set_cr(cairo_t* c, int w, int h) {
		cr = c;
		width = w;
		height = h;
	}

	override bool inverted_y_direction() {
		return true;
	}
	override bool text_with_border() {
		return true;
	}

	override void initialize() {
	}

	override void finish() {
	}

	override void reset_clip() {
		cairo_reset_clip(cr);
		cairo_rectangle(cr, 0,0, width, height);		
		cairo_clip(cr);
	}
	override void set_clip(double x1, double y1, double x2, double y2) {
		cairo_reset_clip(cr);
		cairo_rectangle(cr, x1,y1, x2-x1, y2-y1);		
		cairo_clip(cr);
	}
	override void clear(double r, double g, double b) {
		cairo_save(cr);
		cairo_set_source_rgba(cr, r,g,b,1);
		cairo_paint(cr);
		cairo_restore(cr);		
	}
	override void set_color(double r, double g, double b, double a = 1) {
		cairo_set_source_rgba(cr, r,g,b,a);
	}
	double line_width;
	override void set_line_width(double w) {
		line_width = w;
		cairo_set_line_width(cr, w);
	}
	override double get_line_width() {
		return line_width;
	}
	override void vertical_line(double x, double y1, double y2) {
		cairo_move_to(cr, x, y1);
		cairo_line_to(cr, x, y2);
	}
	override void horizontal_line(double y, double x1, double x2) {
		cairo_move_to(cr, x1, y);
		cairo_line_to(cr, x2, y);
	}
	override void line(double x1, double y1, double x2, double y2) {
		cairo_move_to(cr, x1, y1);
		cairo_line_to(cr, x2, y2);
	}
	override void rectangle(double x1, double y1, double x2, double y2)
	{
		cairo_rectangle(cr, x1,y1, x2-x1, y2-y1);
	}
	override void polygon(double[2][] xys) {
		foreach(i,xy;xys) {
			if (!i) cairo_move_to(cr, xy[0], xy[1]);
			else    cairo_line_to(cr, xy[0], xy[1]);
		}
		cairo_line_to(cr, xys[0][0], xys[0][1]);
	}
	override void fill() {
		cairo_fill(cr);
	}
	override void stroke() {
		cairo_stroke(cr);
	}
	struct Bitmap {
		uint[] data;
		cairo_surface_t* surface;
		cairo_pattern_t* pattern;
		int w,h;
		int stride;
	}
	Bitmap[ulong] bitmaps;
	ulong bitmap_counter = 0;
	@trusted
	override ulong    create_bitmap(int w, int h) {
		ulong handle = ++bitmap_counter;

		Bitmap bmp;
		auto stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
		bmp.data = new uint[](w*h);
		bmp.w = w;
		bmp.h = h;
		bmp.stride = stride;		

		bmp.surface = cairo_image_surface_create_for_data(cast(ubyte*)bmp.data.ptr, CAIRO_FORMAT_ARGB32, w, h, stride);
		bmp.pattern = cairo_pattern_create_for_surface(bmp.surface);
		cairo_pattern_set_filter(bmp.pattern, CAIRO_FILTER_NEAREST);

		bitmaps[handle] = bmp;
		return handle;
	}
	override void   destroy_bitmap(ulong handle) {
		bitmaps[handle].data = null;
		cairo_pattern_destroy(bitmaps[handle].pattern);
		cairo_surface_destroy(bitmaps[handle].surface);
		bitmaps.remove(handle);
	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		return bitmaps[handle].data;
	}
	override void    access_bitmap_done(ulong handle) {
		bitmaps[handle].surface.destroy;
		bitmaps[handle].pattern.destroy;
		bitmaps[handle].surface = cairo_image_surface_create_for_data (cast(ubyte*)bitmaps[handle].data.ptr, CAIRO_FORMAT_ARGB32, bitmaps[handle].w, bitmaps[handle].h, bitmaps[handle].stride);
		bitmaps[handle].pattern = cairo_pattern_create_for_surface(bitmaps[handle].surface);
		cairo_pattern_set_filter(bitmaps[handle].pattern, CAIRO_FILTER_NEAREST);
	}
	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                                  double dx, double dy, double dw, double dh) {
		cairo_save(cr);
			cairo_translate(cr, dx,dy);
			cairo_scale(cr, dw/sw, dh/sh);
			cairo_translate(cr,-sx,-sy);
			cairo_rectangle(cr, sx,sy, sw,sh);
			cairo_set_source(cr, bitmaps[handle].pattern);
			cairo_fill(cr);
		cairo_restore(cr);
	}

	override void need_redraw() {
		gtk_widget_queue_draw(cast(GtkWidget*)drawing_area);
	}

	override void show_mouse_pos(double x, double y, double z) {
		mouse_pos[0] = x;
		mouse_pos[1] = y;
		mouse_pos[2] = z;
		gtk_widget_queue_draw(cast(GtkWidget*)mouse_pos_drawing_area);
	}
	override void show_value(double value, string itemname) {
		mouse_itemname = itemname;
		mouse_value    = value;
	}
	override void set_text_size(int s) {
		cairo_set_font_size(cr, s);
	}

	override void text_extent(string str, out double w, out double h) {
		//cairo_text_extents (cairo_t *cr, const char *utf8, cairo_text_extents_t *extents);.
		cairo_text_extents_t cte;
		import std.string, std.typecons;
		auto strz = cast(char*)str.dup.toStringz;
		cairo_text_extents(cr, strz, &cte);
		w=cte.width;
		h=cte.height;
	}
	override void text(double x, double y, string str) {
		import std.string, std.typecons;
		auto strz = cast(char*)str.dup.toStringz;
		cairo_text_extents_t cte;
		cairo_text_extents(cr, strz, &cte);
		cairo_move_to(cr, x, y); 
		cairo_show_text(cr, strz);
	}

}
