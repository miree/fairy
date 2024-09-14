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
		auto window = name in main_windows;
		if (window !is null) {
			int width, height;
			gtk_window_get_default_size(window.window, 
			                            &window.canvas.width, 
			                            &window.canvas.height);
		}
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
	GtkApplication*   application;
	CanvasProperties* canvas;

	GtkWindow* window;
	GtkFrame* frame;
	GtkPaned* paned;
	MyItemView item_view;
	MyPlotWidget plot_widget;

	string name; 
	this (string window_name, CanvasProperties* canvas_properties, GtkApplication* app)
	{
		name = window_name;
		application = app;
		canvas      = canvas_properties;


		window      = cast(GtkWindow*)gtk_application_window_new(app);
		gtk_window_set_default_size(window, canvas.width, canvas.height);
		frame       = cast(GtkFrame*)gtk_frame_new(null);
		paned       = cast(GtkPaned*)gtk_paned_new(GTK_ORIENTATION_HORIZONTAL);
		item_view  = MyItemView(this);
		plot_widget = MyPlotWidget("plot_widget", canvas_properties);

		gtk_frame_set_child (cast(GtkFrame*)frame, cast(GtkWidget*)paned);

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
		// need access to root_node (stored as user_data)
		Tree* root_node = cast(Tree*)user_data;

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

class CairoBackend : BackendInterface
{
	GtkDrawingArea *drawing_area;
	CanvasProperties *canvas;
	CanvasPainter painter;
	this (GtkDrawingArea *area, CanvasProperties *canvas_properties) {
		drawing_area = area;
		canvas       = canvas_properties;
		painter      = CanvasPainter(canvas);
	}

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
	override void set_color(double r, double g, double b) {
		cairo_set_source_rgba(cr, r,g,b,1);
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
	void rectangle(double x1, double y1, double x2, double y2)
	{
		cairo_rectangle(cr, x1,y1, x2-x1, y2-y1);
	}
	override void fill() {
		cairo_fill(cr);
	}
	override void stroke() {
		cairo_stroke(cr);
	}
	struct Bitmap {
		uint[] data;
		//ImageSurface surface;
		//Pattern pattern;
		cairo_surface_t* surface;
		cairo_pattern_t* pattern;
		int w,h;
		int stride;
	}
	Bitmap[ulong] bitmaps;
	ulong bitmap_counter = 0;
	@trusted
	override ulong    create_bitmap(int w, int h) {
		//import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		ulong handle = ++bitmap_counter;

		Bitmap bmp;
		//auto stride = ImageSurface.formatStrideForWidth(CairoFormat.ARGB32, w);
		auto stride = cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, w);
		bmp.data = new uint[](w*h);
		bmp.w = w;
		bmp.h = h;
		bmp.stride = stride;		

		//bmp.surface = ImageSurface.createForData(cast(ubyte*)bmp.data.ptr, CairoFormat.ARGB32, w, h, stride);
		//bmp.pattern = Pattern.createForSurface(bmp.surface);
		//bmp.pattern.setFilter(CairoFilter.NEAREST);
		bmp.surface = cairo_image_surface_create_for_data(cast(ubyte*)bmp.data.ptr, CAIRO_FORMAT_ARGB32, w, h, stride);
		bmp.pattern = cairo_pattern_create_for_surface(bmp.surface);
		cairo_pattern_set_filter(bmp.pattern, CAIRO_FILTER_NEAREST);

		bitmaps[handle] = bmp;
		return handle;
	}
	override void   destroy_bitmap(ulong handle) {
		//import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		bitmaps[handle].data = null;
		//bitmaps[handle].pattern.destroy;
		//bitmaps[handle].surface.destroy;
		cairo_pattern_destroy(bitmaps[handle].pattern);
		cairo_surface_destroy(bitmaps[handle].surface);
		bitmaps.remove(handle);
	}
	@trusted
	override uint[] access_bitmap_data(ulong handle) {
		//import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		return bitmaps[handle].data;
	}
	override void    access_bitmap_done(ulong handle) {
		//import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		bitmaps[handle].surface.destroy;
		bitmaps[handle].pattern.destroy;
		//bitmaps[handle].surface = ImageSurface.createForData(cast(ubyte*)bitmaps[handle].data.ptr, CairoFormat.ARGB32, bitmaps[handle].w, bitmaps[handle].h, bitmaps[handle].stride);
		//bitmaps[handle].pattern = Pattern.createForSurface(bitmaps[handle].surface);
		//bitmaps[handle].pattern.setFilter(CairoFilter.NEAREST);
		bitmaps[handle].surface = cairo_image_surface_create_for_data (cast(ubyte*)bitmaps[handle].data.ptr, CAIRO_FORMAT_ARGB32, bitmaps[handle].w, bitmaps[handle].h, bitmaps[handle].stride);
		bitmaps[handle].pattern = cairo_pattern_create_for_surface(bitmaps[handle].surface);
		cairo_pattern_set_filter(bitmaps[handle].pattern, CAIRO_FILTER_NEAREST);
	}
	override void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                                  double dx, double dy, double dw, double dh) {
		//import cairo.ImageSurface, cairo.Pattern;//, gdk.Cairo;
		cairo_save(cr);
			cairo_translate(cr, dx,dy);
			cairo_scale(cr, dw/sw, dh/sh);
			cairo_translate(cr,-sx,-sy);
			cairo_rectangle(cr, sx,sy, sw,sh);
			//cairo_set_source(cr, bitmaps[handle].pattern.getPatternStruct());
			cairo_set_source(cr, bitmaps[handle].pattern);
			cairo_fill(cr);
		cairo_restore(cr);
	}

	override void need_redraw() {
		gtk_widget_queue_draw(cast(GtkWidget*)drawing_area);
		//queueDraw();
	}

	override void show_mouse_pos(double x, double y, double z) {
		//updateMousePosLabel(x,y);
	}
	override void show_value(double value, string itemname) {
		//updateValue(value, itemname);
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

struct MyPlotWidget {
	GtkBox *main_box;
	GtkScrolledWindow* controls_scrolled_window;
	GtkDrawingArea *drawing_area;
	GtkSeparator *separator;
	GtkBox *controls_box;
	GtkLabel *dummy;


	CanvasProperties* canvas; 
	CairoBackend cairo_backend;

	extern(C) 
	static void drawFunc(GtkDrawingArea* drawingArea, cairo_t* cr, int width, int height, void* userData) {
		GtkAllocation size;
		gtk_widget_get_allocation(cast(GtkWidget*)drawingArea, &size);

		CairoBackend backend = cast(CairoBackend)userData;

		//auto plot_widget = cast(MyPlotWidget*)userData;
		//cairo_set_source_rgba(cr, 1,0,0,1); // r g b a
		//cairo_set_line_width(cr, 5.0);
		//cairo_move_to(cr, 0, 0);
		//cairo_line_to(cr, size.width, size.height);
		//cairo_stroke(cr);



		backend.set_cr(cr, size.width, size.height);
		//plot_widget.backend.set_cr(cr, size.width, size.height);
		backend.canvas.width = size.width;
		backend.canvas.height = size.height;
		backend.painter.draw_content();
	}
	extern(C) 
	static void destroyNotify(void *data) {
	}

	this(string name, CanvasProperties *canvas_properties) {

		canvas        = canvas_properties;
		cairo_backend = new CairoBackend(drawing_area, canvas);
		cairo_backend.painter.backend = cairo_backend;

		main_box = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
		controls_box = cast(GtkBox*)gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
		controls_scrolled_window = cast(GtkScrolledWindow*)gtk_scrolled_window_new();
		gtk_scrolled_window_set_propagate_natural_width(controls_scrolled_window, true);
		gtk_scrolled_window_set_propagate_natural_height(controls_scrolled_window, true);
		gtk_scrolled_window_set_child(controls_scrolled_window, cast(GtkWidget*)controls_box);


		dummy = cast(GtkLabel*)gtk_label_new("dummy");
		gtk_box_append(controls_box, cast(GtkWidget*)dummy);
		import std.string;
		drawing_area = cast(GtkDrawingArea*)gtk_drawing_area_new();
		gtk_widget_set_hexpand(cast(GtkWidget*)drawing_area, true);
		gtk_widget_set_vexpand(cast(GtkWidget*)drawing_area, true);
		gtk_box_append(main_box, cast(GtkWidget*)drawing_area);
		gtk_widget_set_size_request(cast(GtkWidget*)drawing_area, 100, 50);
		gtk_drawing_area_set_draw_func(drawing_area, &drawFunc, cast(void*)cairo_backend, &destroyNotify);
		separator = cast(GtkSeparator*)gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
		gtk_box_append(main_box, cast(GtkWidget*)separator);
		gtk_box_append(main_box, cast(GtkWidget*)controls_scrolled_window);
	}
}