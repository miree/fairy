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
		foreach(window; main_windows) {
			import std.stdio;
			writeln("MainWindow.add_item(",name,")");
			window.item_view.addItem(name, null);
		}
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

	MyItemView item_view;

	string name; 
	this (string window_name, CanvasProperties* canvas_properties, GtkApplication* app)
	{
		name = window_name;
		application = app;
		window      = cast(GtkWindow*)gtk_application_window_new(app);
		canvas      = canvas_properties;

		item_view  = MyItemView(this);


		gtk_window_set_title(window, name.toStringz);
		gtk_window_set_child(window, cast(GtkWidget*)item_view.scrolled_window);
		gtk_window_present(window);
	}
}


struct MyItemView {
	struct Tree
	{
		string fullname;
		Tree[string] children;
		Tree* find_helper(Tree* node, string[] parts) {
			import std.stdio;
			writeln("find_helper ", fullname, "   ", parts);
			if (parts.length == 0) return node;
			auto child = parts[0] in node.children;
			if (child is null) return null;
			writeln(" recurse down into child ", child.fullname);
			return find_helper(child, parts[1..$]);
		}
		Tree* find_node(string fullname) {
			import std.stdio;
			import std.array;
			auto parts = fullname.split('/');
			writeln("find ", fullname, "  in node ", this.fullname);
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
			import std.stdio;
			writeln("Tree.add(", fullname, ")");
			import std.algorithm, std.range;
			add_helper(fullname.split('/'));
		}
	}
	auto root_node = new Tree("fairy");

	import fairy, item;
	void addItem(string fullname, Item item) {
		root_node.add(fullname);
	}


	GtkStringList* string_list;
	GtkTreeListModel* treelistmodel;
	GtkSelectionModel* selection_model;
	GtkListItemFactory *signal_list_item_factory;
	GtkColumnViewColumn* col1;
	GtkColumnView* col_view;
	GtkScrolledWindow *scrolled_window;

	MainWindow *main_window;

	this(ref MainWindow window) {
		main_window = &window;
		string_list = gtk_string_list_new(null); // this implements GListModel
		
		// sync with session
		import fairy;
		import std.stdio, std.array, std.algorithm;
		foreach (item_name; session.items.byKey) {
			import std.stdio;
			writeln("MainWindow this root_node.add(", item_name, ")");
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
		                                                               cast(void*)root_node,
		                                                               null);
		selection_model = cast(GtkSelectionModel*)gtk_multi_selection_new(cast(GListModel*)treelistmodel);
		signal_list_item_factory = gtk_signal_list_item_factory_new();
		g_signal_connect(signal_list_item_factory, "setup",    &signal_list_item_factory_setup,    cast(void*)root_node);
		g_signal_connect(signal_list_item_factory, "bind",     &signal_list_item_factory_bind,     cast(void*)root_node);
		g_signal_connect(signal_list_item_factory, "unbind",   &signal_list_item_factory_unbind,   cast(void*)root_node);
		g_signal_connect(signal_list_item_factory, "teardown", &signal_list_item_factory_teardown, cast(void*)root_node);
		col1 = cast(GtkColumnViewColumn*)gtk_column_view_column_new("Items", signal_list_item_factory);
		col_view = cast(GtkColumnView*)gtk_column_view_new(selection_model);
		gtk_column_view_append_column(col_view, col1);
		scrolled_window = cast(GtkScrolledWindow*)gtk_scrolled_window_new();
		gtk_scrolled_window_set_child(scrolled_window, cast(GtkWidget*)col_view);
		gtk_widget_set_size_request (cast(GtkWidget*)scrolled_window, 100, 100);
	}

	static extern(C) GListModel* treelist_listmodel_create(void* item, void* user_data) 
	{
		Tree* root_node = cast(Tree*)user_data;
		//MyItemView* itemview = cast(MyItemView*)user_data;
		import std.stdio, std.conv;
		auto str_obj = cast(GtkStringObject*)(item);
		auto str = gtk_string_object_get_string(str_obj).to!string;
		import core.stdc.string;
		GtkStringList* string_list = gtk_string_list_new(null); // this implements GListModel

		import std.stdio, std.array, std.algorithm, std.string;
		writeln("listmodel_create trying to find node ", str);
		//writeln("========= print tree" );
		//root_node.print();
		//writeln("========= print tree done" );
		auto node = root_node.find_node(str);
		if (node is null) {
			writeln("error: found null");
		} else {
			//writeln("found child node ", (*node).fullname, " with children ", (*node).children.byKey.array.sort);
			foreach(child_name; (*node).children.byKey.array.sort) {
				gtk_string_list_append(string_list, node.children[child_name].fullname.toStringz);
			}
		}

		//if (str == "item1") {
		//	gtk_string_list_append(string_list, "item1_a");
		//	gtk_string_list_append(string_list, "item1_b");
		//	gtk_string_list_append(string_list, "item1_c");
		//} else if (str == "item2") {
		//	gtk_string_list_append(string_list, "item2_x");
		//	gtk_string_list_append(string_list, "item2_y");
		//	gtk_string_list_append(string_list, "item2_z");
		//} else if (str == "item1_a") {
		//	char[100] buf;
		//	import core.stdc.stdio;
		//	foreach(i;0..1000) {
		//		snprintf(buf.ptr,100,"item1_%d",i);
		//		gtk_string_list_append(string_list, buf.ptr);
		//	}
		//}
		return cast(GListModel*)string_list;
	}


	extern(C) static void signal_list_item_factory_setup(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		Tree* root_node = cast(Tree*)user_data;
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
		Tree* root_node = cast(Tree*)user_data;
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
		import std.array, std.string;
		if (root_node.find_node(str.to!string).children.length) gtk_tree_expander_set_hide_expander(cast(GtkTreeExpander*)expander, false);
		else gtk_tree_expander_set_hide_expander(cast(GtkTreeExpander*)expander, true);
		snprintf(buf.ptr,64,"%s -> %d", str.to!string.split('/')[$-1].toStringz, gtk_list_item_get_position(list_item));
		gtk_label_set_text(label, buf.ptr);
		gtk_tree_expander_set_list_row(cast(GtkTreeExpander*)expander, tree_list_row);
	}

	extern(C) static void signal_list_item_factory_unbind(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		Tree* root_node = cast(Tree*)user_data;
		import std.stdio;
		import std.conv;
		auto item = cast(GtkListItem*)object;
		writeln("unbind "~gtk_list_item_get_position(item).to!string);
	}

	extern(C) static void signal_list_item_factory_teardown(GtkSignalListItemFactory* self, GObject* object, gpointer user_data) 
	{
		MyItemView* itemview = cast(MyItemView*)user_data;
		import std.stdio;
		writeln("teardown");
	}

}