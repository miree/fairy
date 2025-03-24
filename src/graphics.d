module graphics;
@safe:

interface Gui {
	void add_window(string name, ref CanvasProperties canvas);
	void close_window(string name);
	void redraw_window(string name);
	void save_window(string name);
	void add_item(string name);
	void remove_item(string name);
	void update_from_canvas(string name);
	void loop();
}

interface BackendInterface {
	bool inverted_y_direction(); // true if the y-coordinates go from top to bottom
	bool text_with_border(); // true if black text should be rendered with a white border

	void initialize();   // must be called before anything else
	void finish(); // must be called after anything else

	void reset_clip();
	void set_clip(double x1, double y1, double x2, double y2);

	void clear(double r, double g, double b);
	void set_color(double r, double g, double b, double a = 1); // a is alpha
	
	// line drawing
	void set_line_width(double w);
	double get_line_width();
	void vertical_line(double x, double y1, double y2);
	void horizontal_line(double y, double x1, double x2);
	void line(double x1, double y1, double x2, double y2);
	void rectangle(double x1, double y1, double x2, double y2);
	void polygon(double[2][] xys);
	void fill();
	void stroke();

	// bitmap drawing
	@trusted
	ulong  create_bitmap(int w, int h);
	void   destroy_bitmap(ulong handle);
	@trusted
	uint[] access_bitmap_data(ulong handle);
	void   access_bitmap_done(ulong handle);
	void draw_bitmap(ulong handle, double sx, double sy, double sw, double sh,
		                         double dx, double dy, double dw, double dh);

	// text drawing 
	void set_text_size(int s);
	void text_extent(string str, out double w, out double h);
	void text(double x, double y, string str); 

	void need_redraw();
	void show_mouse_pos(double x, double y, double z);
	void show_value(double value, string itemname);
}

void set_global_text_size(int size) {
	global_text_size = size;
}
private int global_text_size = 20;

interface Visual {
	Visualizer create_visualizer(BackendInterface backend, Visualizer old = null);
	ulong getVersion();
	void overrideVersion(ulong);
}


class Visualizer
{
import transform;
public:
	this (ulong itemversion, ulong dim = 0) {
		item_version = itemversion;
		dimension = dim;
	}
	double getValue(double x, double y) {
		return double.init;
	}

	bool get_leftright(out double[2] leftright, in Transform[3] t)  {
		return false;
	}
	bool get_bottomtop_in_leftright(out double[2] bottomtop, 
		                             in double[2] leftright, 
		                             in Transform[3] box) 
	{
		return false;
	}
	bool get_zminmax_in_leftright_bottomtop(out double[2] zminmax, 
		                                     in double[2] leftright, 
		                                     in double[2] bottomtop, 
		                                     in Transform[3] t) 
	{
		return false;
	}	

	void draw(BackendInterface gi, in Transform[3] t) 
	{}

	final ulong getVersion() {
		return item_version;
	}
	final ulong getDim() {
		return dimension; // zero means "not decisive" for the draw area
	}

protected:
	void requestRedraw() { // this is meant to be called by the derived Visualizer if their internal selection state changes
		require_redraw = true;
	}

private:
	ulong item_version;
	ulong dimension;
	bool require_redraw;
}

enum DisplayMode { overlay, rows, columns }
import serializeJSON;


import transform;
struct CanvasProperties {
	@SERIALIZE int          width            = 600;
	@SERIALIZE int          height           = 400;
	@SERIALIZE int          xpos             = -1;
	@SERIALIZE int          ypos             = -1;
	@SERIALIZE int          text_size        = 0;
	@SERIALIZE bool[2]      grid             = [true,true];
	@SERIALIZE bool         grid_ontop       = false;
	@SERIALIZE bool[2]      numbers          = [true,true];
	@SERIALIZE bool         numbers_ontop    = true;
	@SERIALIZE bool         color_bar        = true;
	@SERIALIZE int          dim              = 1;
	@SERIALIZE DisplayMode  display_mode     = DisplayMode.overlay;
	@SERIALIZE int          columns_or_rows  = 1;
	@SERIALIZE double       color_key_width  = 0.05; // percent of canvas width
	@SERIALIZE bool[3]      autoscale        = [false,false,false];
	@SERIALIZE bool         autorefresh      = false;
	@SERIALIZE string[]     itemnames        = [];
	@SERIALIZE Transform[3] transform;

	bool fit_content = false;
	bool refresh     = false;
	//bool[3] autoscale_backup;
	//bool restore_autoscale_backup = false;
	int len() {
		if (itemnames !is null && itemnames.length != 0) return cast(int)itemnames.length;
		return 1;
	}
	int rows() {
		with(DisplayMode) final switch(display_mode) {
			case overlay: return 1;
			case rows:    return columns_or_rows;
			case columns: for (int result = 1;; ++result) if (result*columns_or_rows >= len()) return result;
		}
	}
	int columns() {
		with(DisplayMode) final switch(display_mode) {
			case overlay: return 1;
			case columns: return columns_or_rows;
			case rows: for (int result = 1;; ++result) if (result*columns_or_rows >= len()) return result;
		}
	}
}

unittest {
	import std.json;
	import serializeJSON;
	import std.stdio;

	CanvasProperties canvas;
	JSONValue json;
	serialize(canvas,json);
	json.toString(JSONOptions.specialFloatLiterals).writeln;
}


struct CanvasPainter {
	CanvasProperties *canvas;
	BackendInterface backend;

	Transform[3][] grid_transforms; // remember the transform settings for each section in grid mode
	Transform[3]   mouse_transform; // the transformation box where the mouse cursor is located in

	double mouse_pos_x;
	double mouse_pos_y;
	bool   mouse_moved; // to detect if mouse movement happened between mouse button click an release events
	bool   left_mouse_move; // indicates that the left mouse button was clicked on a movable interactive elememnt

	// variables for selection box
	double start_selection_x;
	double start_selection_y;
	bool draw_selection_box; // indicates that the left mouse button was NOT clicket on a movable interactive element (in this case a selection box is drawn)
	double current_selection_x;
	double current_selection_y;

	bool translating_ongoing   = false;
	bool scaling_ongoing       = false;
	bool z_translating_ongoing = false;
	bool z_scaling_ongoing     = false;

	import interactive;
	BoundingBox select_or_drag; // when the left mouse button is clicked near an interactive element, it may be grabed directly (click and drag),
	                            // or it may be selected (click an release). The click event sets this variable "select_or_drag" to the interactive
	                            // element. In the following motion or release event it is decided which of the two actions is executed.
	double canvas_drag_start_x; // if a click and drag is performed, this is the starting point of the drag operation in canvas coordinates
	double canvas_drag_start_y; // if a click and drag is performed, this is the starting point of the drag operation in canvas coordinates



	this(CanvasProperties *c, BackendInterface b) {
		assert(c !is null);
		assert(b !is null);
		canvas = c;
		backend = b;
	}

	Visualizer[string] visualizers;

	//void resize(int w, int h) {
	//	canvas.width  = w;
	//	canvas.height = h;
	//}



	// min is the smallest value larger than 0
	//bool set_log(int dim, double min) {
	//	assert(dim >= 0 && dim < 3);
	//	return canvas.transform[dim].set_logscale(min);
	//}
	//bool set_lin(int dim) {
	//	assert(dim >= 0 && dim < 3);
	//	return canvas.transform[dim].set_linscale();
	//}




	void draw_grid() {
		if (canvas.grid[0]) vertical_grid(backend, canvas);
		if (canvas.grid[1]) horizontal_grid(backend, canvas);
	}

	void draw_grid_numbers() {
		if (canvas.numbers[0]) vertical_grid_numbers(backend, canvas);
		if (canvas.numbers[1]) horizontal_grid_numbers(backend, canvas);			
	}

	static void get_rgb(double c, out uint rgb) {
		// grayscale
		//uint i = cast(uint)(255*c);
		//rgb = 0xff000000 | (i<<16) | (i<<8) | (i<<0);

		// bluish color
		rgb = 0xff000000;
		if (c>1.0) c = 1.0;
		if (c<0.0) c = 0.0;
		c *= 3;
		if (c < 1.0) { // back to blue
			rgb |= cast(uint)(0xff*c);
			return;
		}
		rgb = 0xff0000ff;
		if (c < 2.0)  { // blue to lightblue
			c -= 1.0; 
			rgb |=  (cast(uint)(0x0000ff00*c) & 0x0000ff00) ; 
			return;
		}
		rgb = 0xff00ffff; // lightblue to white
		c -= 2.0;
		rgb |= cast(uint)(0xff*c)<<16;
	}

	void draw_colorkey() {
		long N=50;
		foreach(i;0..N) {
			double x1 = canvas.transform[0].world2canvas(canvas.transform[0].min+(canvas.transform[0].max-canvas.transform[0].min)*(1.0-canvas.color_key_width));
			double x2 = canvas.transform[0].world2canvas(canvas.transform[0].max);
			double y1 = canvas.transform[1].world2canvas(canvas.transform[1].min+(canvas.transform[1].max-canvas.transform[1].min)*(i+0)/N);
			double y2 = canvas.transform[1].world2canvas(canvas.transform[1].min+(canvas.transform[1].max-canvas.transform[1].min)*(i+1)/N);
			uint rgb;
			double c = 1.0*i/N;
			import color;
			color.get_rgb(c,rgb);
			rgb &= 0x00ffffff;
			backend.set_color((rgb>>16)/255.0,((rgb&0xffff)>>8)/255.0,((rgb&0xff)/255.0));
			backend.set_line_width(2);
			backend.rectangle(x1,y1, x2,y2-1);
			backend.fill();	

		}
	}

	bool fit_content_x() {
		import std.algorithm;
		auto old = canvas.transform[0];
		double left,right;
		foreach(name, ref vis; visualizers) {
			double[2] lr; 
			if (!vis.get_leftright(lr,canvas.transform)) continue;
			left =(left  is double.init)?lr[0]:min(left,lr[0]);
			right=(right is double.init)?lr[1]:max(right,lr[1]);
		}
		if (left !is double.init && right !is double.init) {
			canvas.transform[0].set_minmax(left,right);
			canvas.transform[0].scale=1; // eliminate all ongoing transformations in x-direction
			canvas.transform[0].delta=0; // eliminate all ongoing transformations in x-direction
		}
		if (old.min != canvas.transform[0].min || old.max != canvas.transform[0].max ||
			old.scale != canvas.transform[0].scale || old.delta != canvas.transform[0].delta) {
			return true;
		}
		return false;
	}

	bool fit_content_y() {
		import std.algorithm;
		auto old = canvas.transform[1];
		double bottom,top;
		double left = canvas.transform[0].min;
		double right= canvas.transform[0].max;
		foreach(ref vis; visualizers.byValue) {
			double[2] bt;
			if (!vis.get_bottomtop_in_leftright(bt, [left,right], canvas.transform)) continue;
			bottom = (bottom is double.init)?bt[0]:min(bottom,bt[0]);
			top    = (top    is double.init)?bt[1]:max(top   ,bt[1]);
		}
		if (bottom !is double.init && top !is double.init) {
			if (bottom == top) {
				bottom = bottom-0.5;
				top    = top   +0.5;
			}
			canvas.transform[1].set_minmax(bottom,top);		
			canvas.transform[1].scale=1; // eliminate all ongoing transformations in y-direction
			canvas.transform[1].delta=0; // eliminate all ongoing transformations in y-direction
		}
		if (old.min != canvas.transform[1].min || old.max != canvas.transform[1].max ||
			old.scale != canvas.transform[1].scale || old.delta != canvas.transform[1].delta) {
			return true;
		}
		return false;
	}

	bool fit_content_z() {
		import std.algorithm;
		auto old = canvas.transform[2];
		double zmin, zmax;
		double left = canvas.transform[0].min;
		double right= canvas.transform[0].max;
		double bottom = canvas.transform[1].min;
		double top    = canvas.transform[1].max;
		int i = 0;
		foreach(ref vis; visualizers.byValue) {
			double[2] z12;
			if (!vis.get_zminmax_in_leftright_bottomtop(z12, [left,right], [bottom,top], canvas.transform)) continue;
			double z1 = z12[0];
			double z2 = z12[1];
			//import std.stdio; writeln("inside fit_content_z ", z1," " ,z2);
			zmin = (zmin is double.init)?z1:(zmin is double.init)?z1:min(zmin,z1);
			zmax = (zmax is double.init)?z2:(zmax is double.init)?z2:max(zmax,z2);
		}
		//import std.stdio; writeln("inside fit_content_z ", z1," " ,z2);
		if (zmin !is double.init && zmax !is double.init) {
			canvas.transform[2].set_minmax(zmin,zmax);		
			canvas.transform[2].scale=1; // eliminate all ongoing transformations in z-direction
			canvas.transform[2].delta=0; // eliminate all ongoing transformations in z-direction
		}
		if (old.min != canvas.transform[2].min || old.max != canvas.transform[2].max ||
			old.scale != canvas.transform[2].scale || old.delta != canvas.transform[2].delta) {
			return true;
		}
		return false;
	}

	void draw_selection_box_helper() {
		backend.set_line_width(3);
		backend.set_color(0.9,0.9,0.9);
		backend.rectangle(start_selection_x, start_selection_y,
			             mouse_pos_x, mouse_pos_y);
		backend.stroke();
		backend.set_line_width(1);
		backend.set_color(0,0,0);
		backend.rectangle(start_selection_x, start_selection_y,
			             mouse_pos_x, mouse_pos_y);
		backend.stroke();
	}

	void draw_content() {
		// make sure that visualizers for each itemname are available
		import std.algorithm;
		auto removed_visualizer_names = visualizers.byKey.filter!(n=>!canvas.itemnames.canFind(n));
		foreach(n;removed_visualizer_names) {
			visualizers.remove(n);
		}
		string[] items_with_visualizer;
		foreach(itemname; canvas.itemnames) {
			import fairy;
			try {
				if ((itemname in visualizers) is null) { // try to get the visualizer
					visualizers[itemname] = fairy.session.get_visual_item(itemname).create_visualizer(backend);
				} else if (canvas.refresh) {
					if (visualizers[itemname].getVersion < fairy.session.get_visual_item(itemname).getVersion) {
						visualizers[itemname] = fairy.session.get_visual_item(itemname).create_visualizer(backend, visualizers[itemname]);
					}
				}
				items_with_visualizer ~= itemname;
			} catch (Exception e) { // cannot get visualizer
				import std.stdio;
				writeln("cannot create visualizer for item " ~ itemname ~ ": " ~ e.msg);
			}
		}
		canvas.itemnames = items_with_visualizer;
		canvas.refresh = false;

		if (canvas.fit_content) {
			fit_content_x();
			fit_content_y();
			fit_content_z();
			canvas.fit_content = false;
		} else {
			if (canvas.autoscale[0]) fit_content_x();
			if (canvas.autoscale[1]) fit_content_y();
			if (canvas.autoscale[2]) fit_content_z();
		}

		backend.initialize();
		backend.set_clip(0,0,canvas.width, canvas.height);
		backend.clear(0.9, 0.9, 0.9);
		backend.set_text_size(global_text_size);
		if (canvas.text_size > 0) {
			backend.set_text_size(canvas.text_size);
		}

		if (canvas.display_mode == DisplayMode.overlay) {

			canvas.transform[0].update_coefficients(0, 1, canvas.width);
			canvas.transform[1].update_coefficients(0, 1, canvas.height, backend.inverted_y_direction);
			canvas.transform[2].update_coefficients(0, 1, 1);
			grid_transforms.length = 1;
			grid_transforms[0] = canvas.transform;
			import std.stdio;

			if (!canvas.grid_ontop)    draw_grid();
			if (!canvas.numbers_ontop) draw_grid_numbers();
			foreach(idx, itemname; canvas.itemnames) {
				import fairy;
				try {
					//if ((itemname in visualizers) is null) { // try to get the visualizer
					//	visualizers[itemname] = fairy.session.get_visual_item(itemname).create_visualizer(backend);
					//}
					if (canvas.dim == 0 && idx == 0) {
						canvas.dim = cast(int)visualizers[itemname].getDim;
					}
					visualizers[itemname].draw(backend, canvas.transform);
				} catch (Exception e) {
					writeln("cannot draw ", itemname , " because ", e.msg);
				}
			}
			if (canvas.grid_ontop)    draw_grid();
			if (canvas.numbers_ontop) draw_grid_numbers();
			if (canvas.color_bar) {
				draw_colorkey();
				color_grid_numbers(backend, canvas, canvas.color_key_width);
			}	
			if (draw_selection_box) draw_selection_box_helper();
			
			// help debugging BoundingBoxes in the selection process
			//if (select_or_drag.valid) {
			//	double cx1 = canvas.transform[0].world2canvas(select_or_drag.x1);
			//	double cy1 = canvas.transform[1].world2canvas(select_or_drag.y1);
			//	double cx2 = canvas.transform[0].world2canvas(select_or_drag.x2);
			//	double cy2 = canvas.transform[1].world2canvas(select_or_drag.y2);
			//	import std.stdio;
			//	writeln("bounding box: ", cx1, " ", cy1, "    ", cx2, " ", cy2);
			//	backend.set_color(0,0.5,0);
			//	backend.set_line_width(2);
			//	backend.rectangle(cx1,cy1,cx2,cy2); 
			//	backend.stroke();
			//}
		} else { 
			// grid mode
			// find number of rows and columns
			int rows    = canvas.rows;
			int columns = canvas.columns;

			grid_transforms.length = rows*columns;
			grid_transforms[0] = canvas.transform;

			foreach(row; 0..rows) {
				foreach(column; 0..columns) {

					uint idx = column * rows + row;
					if (canvas.display_mode == DisplayMode.columns) {
						idx = row * columns + column;
					}

					backend.set_clip(     column *canvas.width/columns,      row *canvas.height/rows, 
						             (1.0+column)*canvas.width/columns, (1.0+row)*canvas.height/rows);

					import std.stdio;
					if (idx < canvas.itemnames.length) {
						string itemname = canvas.itemnames[idx];
						Visualizer visualizer;
						if (itemname !is null) {
							//if ((itemname in visualizers) is null) {
							//	import fairy;
							//	visualizers[itemname] = fairy.session.get_visual_item(itemname).create_visualizer(backend);
							//}
							visualizer = visualizers[itemname];
							if (canvas.dim == 0 && idx == 0) {
								canvas.dim = cast(int)visualizer.getDim;
							}
							double left,right, bottom,top, zmin,zmax;
							double[2] lr;
							if (canvas.autoscale[0] && visualizer.get_leftright(lr,canvas.transform)) {
								left = lr[0];
								right = lr[1];
								canvas.transform[0].set_minmax(left,right);
							}
							if (left  is double.init) left = canvas.transform[0].min;
							if (right is double.init) right= canvas.transform[0].max;
							double[2] bt;
							if (canvas.autoscale[1] && visualizer.get_bottomtop_in_leftright(bt, [left,right], canvas.transform)) {
								bottom = bt[0];
								top = bt[1];
								if (bottom == top) {
									bottom = bottom-0.5;
									top    = top   +0.5;
								}								
								canvas.transform[1].scale=1; // eliminate all ongoing transformations in y-direction
								canvas.transform[1].delta=0; // eliminate all ongoing transformations in y-direction
								canvas.transform[1].set_minmax(bottom,top);
							} else {
								bottom = canvas.transform[1].min;
								top    = canvas.transform[1].max;
							}
							double[2] zminmax;
							if (canvas.autoscale[2] && visualizer.get_zminmax_in_leftright_bottomtop(zminmax, [left,right], [bottom,top], canvas.transform)) {
								canvas.transform[2].scale=1; // eliminate all ongoing transformations in z-direction
								canvas.transform[2].delta=0; // eliminate all ongoing transformations in z-direction
								canvas.transform[2].set_minmax(zminmax[0], zminmax[1]);
							}
						}
					}

					canvas.transform[0].update_coefficients(column, columns, canvas.width);
					canvas.transform[1].update_coefficients(row,    rows,    canvas.height , backend.inverted_y_direction);
					canvas.transform[2].update_coefficients(0, 1, 1);
					grid_transforms[idx][] = canvas.transform[];
					double x1 =      column  * cast(double)canvas.width  / columns;
					double y1 =         row  * cast(double)canvas.height / rows;
					double x2 = (1.0+column) * cast(double)canvas.width  / columns;
					double y2 = (1.0+   row) * cast(double)canvas.height / rows;
					backend.set_clip(x1,y1, x2,y2);

					if (!canvas.grid_ontop)    draw_grid();
					if (!canvas.numbers_ontop) draw_grid_numbers();

					if (idx < canvas.itemnames.length) {
						string itemname = canvas.itemnames[idx];
						import fairy;
						try {
							//if ((itemname in visualizers) is null) { // try to get the visualizer
							//	visualizers[itemname] = fairy.session.get_visual_item(itemname).create_visualizer(backend);
							//}
							visualizers[itemname].draw(backend, canvas.transform);
						} catch (Exception e) {
							import std.stdio;
							writeln("cannot draw ", itemname , " because ", e.msg);
						}
					}

					if (canvas.grid_ontop)    draw_grid();
					if (canvas.numbers_ontop) draw_grid_numbers();

					if (canvas.color_bar) {
						draw_colorkey();
						color_grid_numbers(backend, canvas, canvas.color_key_width);
					}	
					if (draw_selection_box) draw_selection_box_helper();
				}
			}

			backend.set_clip(0,0,canvas.width,canvas.height);
			backend.set_color(0.2,0.2,0.2);
			backend.set_line_width(2);
			foreach(row;    1..rows) {
				backend.horizontal_line(row*(canvas.height-1)/rows,0,canvas.width);
				backend.stroke();
			}
			foreach(column; 1..columns) {
				backend.vertical_line(column*(canvas.width-1)/columns,0,canvas.height);
				backend.stroke();
			}

		}		

		backend.finish();

		// mouse motion is called here to update the mouse_value display 
		//  this falsely sets the "mouse_moved" variable to true even if the mouse was not moved.
		//  quick-fix remember the variable and restore it after the function returns.
		bool mm = mouse_moved;
		mouse_motion(mouse_pos_x, mouse_pos_y, backend);
		mouse_moved = mm;
	}

	void iterate_grid_transforms(double x, double y, void delegate(double x, double y, double z, bool inside, string itemname, in Transform[3] t) @safe callback ) {
		string mouse_itemname = null;
			//import std.stdio;
			//writeln("iterate_grid_transforms ", grid_transforms.length);
		foreach( idx, transform ; grid_transforms) {
			import std.math;
			double x_world = transform[0].canvas2world(x);
			double y_world = transform[1].canvas2world(y);
			double z_world = transform[2].canvas2world((y_world - transform[1].min)/transform[1].width);
			if (idx >= 0 && idx < canvas.itemnames.length) {
				mouse_itemname  = canvas.itemnames[idx];
			} else {
				mouse_itemname = null;
			}
			if (x_world > transform[0].min && x_world < transform[0].max &&
				y_world > transform[1].min && y_world < transform[1].max) {
				//mouse_transform = t;
				callback(transform[0].exp(x_world), transform[1].exp(y_world), transform[2].exp(z_world), true, mouse_itemname, transform);
			} else {
				callback(transform[0].exp(x_world), transform[1].exp(y_world), transform[2].exp(z_world), false, mouse_itemname, transform);
			}
		}

	}

	void mouse_motion(double x, double y, BackendInterface backend, bool ctrl = false, bool shift = false) {
		mouse_pos_x = x;
		mouse_pos_y = y;
		mouse_moved = true;

		backend.show_value(double.init, null); // this clears the show_value field
		if (!draw_selection_box && !select_or_drag.valid) {
			// this section handles 
			//   1) the display of the mouse potition in the GUI
			//   2) display the value that is returned by the item where the mouse pointer hovers
			//   3) highlight one element of interactive items when the mouse pointer is close enough 
			if (canvas.display_mode != DisplayMode.overlay) { 
				// grid mode
				iterate_grid_transforms(x,y,(double x_world, double y_world, double z_world, bool inside, string itemname, in Transform[3] t) {
					//import std.stdio;
					//writeln("inside ", inside, "   ", itemname);
					if (inside)  {
						mouse_transform = t;
						backend.show_mouse_pos(x_world, y_world, z_world);
						if (itemname !is null) {
							if (highlight([itemname], visualizers, x_world, y_world, canvas.transform)) backend.need_redraw();
							backend.show_value(visualizers[itemname].getValue(x_world, y_world), itemname);						
						}	
					} else {
						if (itemname !is null && un_highlight(itemname, visualizers)) backend.need_redraw();
					}
				});
			} else { 
				// overlay mode
				iterate_grid_transforms(x,y,(double x_world, double y_world, double z_world, bool inside, string itemname, in Transform[3] t) {
					if (inside) {
						mouse_transform = t;
						backend.show_mouse_pos(x_world, y_world, z_world);
						if (highlight(canvas.itemnames, visualizers, x_world, y_world, canvas.transform)) backend.need_redraw();
						import std.algorithm, std.array, std.typecons;
						// make a list of typles (itemname, value) which only contains not-NaN values
						auto values = canvas.itemnames.map!(name=>tuple(name,name in visualizers)).filter!(tup=>tup[1])
						                              .map!(tup=>tuple(tup[0],(*tup[1]).getValue(x_world,y_world)))
						                              .filter!(tup=>tup[1] !is double.init);
						if (!values.empty) {
							backend.show_value(values.front[1], values.front[0]);
						} else {
							//backend.show_value(double.init, null);
						}
					} 
				});
			}
		}

		//drawer.show_mouse_pos(transform.transform_canvas2world_x(x), transform.transform_canvas2world_y(y));
		with (canvas.transform[0]) {
			if (scaling_ongoing)     scale_ongoing(x, -0.01);
			if (translating_ongoing) translate_ongoing(x);
			if (scaling_ongoing || translating_ongoing) {
				backend.need_redraw();
				//import std.stdio; writeln("need_redraw 1");
			}
		}
		with (canvas.transform[1]) {
			if (scaling_ongoing)     scale_ongoing(y, +0.01);
			if (translating_ongoing) translate_ongoing(y);
			if (scaling_ongoing || translating_ongoing) {
				backend.need_redraw();
				//import std.stdio; writeln("need_redraw 1");
			}
		}
		with (canvas.transform[2]) {
			if (z_scaling_ongoing)     scale_ongoing(y, +0.01);
			if (z_translating_ongoing) {
				if (backend.inverted_y_direction) translate_ongoing(-y/(canvas.height/canvas.rows));
				else                              translate_ongoing(y/(canvas.height/canvas.rows));
			}
			if (z_scaling_ongoing || z_translating_ongoing) {
				backend.need_redraw();
			}
		}
		if (select_or_drag.valid) {
			if (canvas.display_mode == DisplayMode.overlay) {
				foreach(itemname; canvas.itemnames) {
					auto vis = itemname in visualizers;
					if (vis) {
						auto interact = cast(Interactive)(*vis);
						if (interact) {
							long handle = -1;
							if (interact is select_or_drag.item) handle = select_or_drag.handle;
							//import std.stdio;
							//writeln("mouse_motion drag overlay ", ctrl);
							interact.drag(handle, canvas_drag_start_x, canvas_drag_start_y, x,y, grid_transforms[0], ctrl, shift);
						}
					}
				}
			} else {
				ulong grid_idx = 0;
				foreach(idx, transform; grid_transforms) {
					if (idx >= 0 && idx < canvas.itemnames.length) {
						auto vis = canvas.itemnames[idx] in visualizers;
						if (vis) {
							auto interact = cast(Interactive)(*vis);
							if (interact && (interact is select_or_drag.item)) {
								grid_idx = idx;
							}
						}
					}
				}
				import std.stdio;
				writeln("mouse_motion drag gridmode");
				select_or_drag.item.drag(select_or_drag.handle, canvas_drag_start_x, canvas_drag_start_y, x,y, grid_transforms[grid_idx], ctrl, shift);
			}
			backend.need_redraw();
		}
		if (draw_selection_box) {
			current_selection_x = x;
			current_selection_y = y;
			backend.need_redraw();
			//import std.stdio; writeln("need_redraw 2");
		}
	}

	void right_button_pressed(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("right click ", nPress, " ",  x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		double x_world = mouse_transform[0].canvas2world(x);
		//writeln("x:", x, " y:",y, "  x_world:",x_world, " y_world:",y_world);	
		if (canvas.color_bar &&
			x_world <= mouse_transform[0].max && 
			x_world >= mouse_transform[0].max - mouse_transform[0].width*canvas.color_key_width) {
			//writeln("right click in z-colorbar");
			if (z_translating_ongoing) {
				canvas.transform[2].translate_finish();
				z_translating_ongoing = false;
			} else {
				canvas.transform[2].scale_start(y, canvas.rows, canvas.height, true);
				z_scaling_ongoing = true;
			}
		} else {
			if (translating_ongoing) {
				canvas.transform[0].translate_finish();
				canvas.transform[1].translate_finish();
				backend.need_redraw();
				translating_ongoing = false;
			} else {
				canvas.transform[0].scale_start(x, canvas.columns,  canvas.width, false);
				canvas.transform[1].scale_start(y, canvas.rows,     canvas.height, true);
				scaling_ongoing = true;
			}
		}
	}
	void right_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		//import std.stdio;
		//writeln("right release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift, " z_scaling_ongoing=", z_scaling_ongoing);
		if (scaling_ongoing) {
			canvas.transform[0].scale_finish();
			canvas.transform[1].scale_finish();
			backend.need_redraw();
			scaling_ongoing = false;		
		} 
		if (z_scaling_ongoing) {
			canvas.transform[2].scale_finish();
			z_scaling_ongoing = false;
		} 
	}

	void mid_button_pressed(int nPress, double x, double y, BackendInterface backend, bool ctrl = false, bool shift = false) {
		//import std.stdio;
		//writeln("middle click ", nPress, " ",  x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		double x_world = mouse_transform[0].canvas2world(x);
		if (canvas.color_bar &&
			x_world <= mouse_transform[0].max && 
			x_world >= mouse_transform[0].max - mouse_transform[0].width*canvas.color_key_width) {
			if (z_scaling_ongoing) {
				canvas.transform[2].scale_finish();
				z_scaling_ongoing = false;
			} else {
				if (backend.inverted_y_direction) canvas.transform[2].translate_start(-y/(canvas.height/canvas.rows), canvas.rows, canvas.height);
				else                              canvas.transform[2].translate_start(y/(canvas.height/canvas.rows), canvas.rows, canvas.height);
				z_translating_ongoing = true;
			}
		} else {
			if (scaling_ongoing) {
				canvas.transform[0].scale_finish();
				canvas.transform[1].scale_finish();
				backend.need_redraw();
				scaling_ongoing = false;		
			} else {
				canvas.transform[0].translate_start(x, canvas.columns,  canvas.width);
				canvas.transform[1].translate_start(y, canvas.rows,     canvas.height);
				translating_ongoing = true;
			}
		}
	}
	void mid_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("middle release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		if (translating_ongoing) {
			canvas.transform[0].translate_finish();
			canvas.transform[1].translate_finish();
			backend.need_redraw();
			translating_ongoing = false;
		} 
		if (z_translating_ongoing) {
			canvas.transform[2].translate_finish();
			z_translating_ongoing = false;
		}
	}


	void left_button_pressed(int nPress, double x, double y, BackendInterface backend, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//mouse_pos_x = x;
		//mouse_pos_y = y;
		//writeln("left click ", nPress, " ",  x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		start_selection_x = x;
		start_selection_y = y;

		// invalidate the select_or_drag variable
		select_or_drag = BoundingBox();

		if (canvas.display_mode != DisplayMode.overlay) { 
			// grid mode
			iterate_grid_transforms(x,y,(double x_world, double y_world, double z_world, bool inside, string itemname, in Transform[3] t) {
				if (inside && itemname !is null)  {
					auto best_bbox = best_matching_bbox([itemname], visualizers, x_world, y_world, canvas.transform);
					if (best_bbox.valid) {
						//writeln("select or drag on ", itemname);
						select_or_drag = best_bbox;
						canvas_drag_start_x = x;
						canvas_drag_start_y = y;
					}
				} 
			});
		} else { 
			// overlay mode
			iterate_grid_transforms(x,y,(double x_world, double y_world, double z_world, bool inside, string itemname, in Transform[3] t) {
				if (inside) {
					auto best_bbox = best_matching_bbox(canvas.itemnames, visualizers, x_world, y_world, canvas.transform);
					if (best_bbox.valid) {
						foreach(name; canvas.itemnames) {
							if (cast(Interactive)visualizers[name] is best_bbox.item) {
								//writeln("select or drag on ", name);
							} 
						}
						select_or_drag = best_bbox;
						canvas_drag_start_x = x;
						canvas_drag_start_y = y;
					}
				} 
			});
		}
		// only draw selection box if the click was outside of an interactive element
		if (!select_or_drag.valid) draw_selection_box = true;
		mouse_moved = false;
	}
	void left_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		//import std.stdio;
		//writeln("left release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift, "    mouse_moved=", mouse_moved);

		// dragging interactive elements
		if (mouse_moved && select_or_drag.valid) {
			bool end = true;
			if (canvas.display_mode == DisplayMode.overlay) {
				foreach(itemname; canvas.itemnames) {
					auto vis = itemname in visualizers;
					if (vis) {
						auto interact = cast(Interactive)(*vis);
						if (interact) {
							long handle = -1;
							if (interact is select_or_drag.item) handle = select_or_drag.handle;
							interact.drag(handle, canvas_drag_start_x, canvas_drag_start_y, x,y, grid_transforms[0], ctrl, shift, end);
						}
					}
				}
			} else {
				ulong grid_idx = 0;
				foreach(idx, transform; grid_transforms) {
					if (idx >= 0 && idx < canvas.itemnames.length) {
						auto vis = canvas.itemnames[idx] in visualizers;
						if (vis) {
							auto interact = cast(Interactive)(*vis);
							if (interact && (interact is select_or_drag.item)) {
								grid_idx = idx;
							}
						}
					}
				}
				select_or_drag.item.drag(select_or_drag.handle, canvas_drag_start_x, canvas_drag_start_y, x,y, grid_transforms[grid_idx], ctrl, shift, end);
			}

			//select_or_drag.item.drag(select_or_drag.handle, canvas_drag_start_x, canvas_drag_start_y, x,y, canvas.transform, end);
		} 
		// selection via box
		if (mouse_moved && draw_selection_box) {
			if (canvas.display_mode != DisplayMode.overlay) {
				// grid mode
				foreach(idx, transform; grid_transforms) {
					if (idx >= 0 && idx < canvas.itemnames.length) {
						auto vis = canvas.itemnames[idx] in visualizers;
						if (vis && cast(Interactive)(*vis)) {
							(cast(Interactive)(*vis)).select_box(start_selection_x,start_selection_y, x,y, transform, ctrl, shift);
						}
					}
				}
			} else {
				// overlay mode
				import std.algorithm;
				canvas.itemnames.map!(n=>visualizers[n]).filter!(vis=>vis)
				                .map!(vis=>cast(Interactive)(vis)).filter!(i=>i)
				                .each!((interactive) {
				                	interactive.select_box(start_selection_x, start_selection_y, x,y, grid_transforms[0], ctrl, shift);
				                });
			}
		}
		// select if on an interactive element or deselect all if not on an interactive element
		if (!mouse_moved) {
			import std.algorithm;
			if (select_or_drag.valid) {
				if (ctrl) {
					select_or_drag.item.select(select_or_drag.handle, true, shift);
				} else {
					select_one(select_or_drag, canvas.itemnames, visualizers, shift);
				}
			} else {
				select_one(BoundingBox(), canvas.itemnames, visualizers); // unselect all if mouse was not over an interactive element
			}
		}
		select_or_drag = BoundingBox();
		backend.need_redraw();
		draw_selection_box = false;
	}

	/////////////////////////////////////////////////////////
	// scrolling functions (mouse wheel)
	/////////////////////////////////////////////////////////
	void scroll(double dx, double dy, bool ctrl = false, bool shift = false) {
		import std.stdio;
		if (dx) {
			double amount = dx*(ctrl?0.02:0.2)*canvas.width/canvas.columns;
			//writeln("amount=", amount);
			canvas.transform[0].translate_one_step(mouse_pos_x, canvas.columns, canvas.width, mouse_pos_x+amount);
		}
		if (dy) {

			double amount = dy*(ctrl?5:50);
			double x_world = mouse_transform[0].canvas2world(mouse_pos_x);
			if (x_world <= mouse_transform[0].max && 
				x_world >= mouse_transform[0].max - mouse_transform[0].width*canvas.color_key_width) {
				canvas.transform[2].scale_one_step(mouse_pos_y, canvas.rows, canvas.height, amount, 0.01, true);
			} else {
				canvas.transform[0].scale_one_step(mouse_pos_x, canvas.columns, canvas.width,  amount,  0.01, false);
				canvas.transform[1].scale_one_step(mouse_pos_y, canvas.rows,    canvas.height, amount,  0.01, true);
			}
			//transform.scale_one_step(mouse_pos_x, mouse_pos_y, width, height, amount, amount, draw_color_bar?color_key_width:0.0);
		}
		if (dx || dy) {
			backend.need_redraw();
		}

		//writeln("scroll " , dx , " " , dy, "    ctrl=", ctrl, "    shift=",shift);
	}
}


void vertical_grid(BackendInterface backend_interface, CanvasProperties *canvas) {
	if (canvas.transform[0].logscale) {
		vertical_grid_log(backend_interface, canvas);
		return;
	}

	for (int i = 0; i < 3; ++i) {
		double c = 0.7-0.2*i;
		backend_interface.set_color(c,c,c);
		backend_interface.set_line_width(1);

		double width = canvas.transform[0].width*1000/(canvas.width/canvas.columns);
		double oom = 1; // order of magnitude X
		while (oom < width) oom *= 10;
		while (oom > width) oom /= 10;
		oom /= 10;
		for (int n = 0; n < i; ++n) oom *= 10;

		double left   = canvas.transform[0].min;
		double right  = canvas.transform[0].max;
		double bottom = canvas.transform[1].world2canvas(canvas.transform[1].min);
		double top    = canvas.transform[1].world2canvas(canvas.transform[1].max);

		double xpos = (cast(long)(left  /oom))*oom;
		while(xpos < right)
		{
			backend_interface.vertical_line(canvas.transform[0].world2canvas(xpos), 0, canvas.height);
			xpos += oom;
		}
		backend_interface.stroke();
	}
}
void horizontal_grid(BackendInterface backend_interface, CanvasProperties *canvas) {
	if (canvas.transform[1].logscale) {
		horizontal_grid_log(backend_interface, canvas);
		return;
	}
	for (int i = 0; i < 3; ++i) {
		double c = 0.7-0.2*i;
		backend_interface.set_color(c,c,c);
		backend_interface.set_line_width(1);

		double height = canvas.transform[1].width*1000/(canvas.height/canvas.rows);
		double oom = 1; // order of magnitude 
		while (oom < height) oom *= 10;
		while (oom > height) oom /= 10;
		oom /= 10;
		for (int n = 0; n < i; ++n) oom *= 10;

		double left  = canvas.transform[0].world2canvas(canvas.transform[0].min);
		double right = canvas.transform[0].world2canvas(canvas.transform[0].max);
		double bottom  = canvas.transform[1].min;
		double top     = canvas.transform[1].max;

		double ypos = (cast(long)(bottom  /oom))*oom;
		while(ypos < top)
		{
			backend_interface.horizontal_line(canvas.transform[1].world2canvas(ypos), left, right);
			ypos += oom;
		}
		backend_interface.stroke();
	}
}



void vertical_grid_log(BackendInterface backend_interface, CanvasProperties *canvas) {
	import std.math;

	// vertical lines
	double log_left = log(10.0)*cast(long)(canvas.transform[0].min/log(10.0));
	double bottom = canvas.transform[1].min;
	double top    = canvas.transform[1].max;
	backend_interface.set_line_width(1);
	do {
		double color = 0.5;
		backend_interface.set_color(color, color, color);
		backend_interface.vertical_line(canvas.transform[0].world2canvas(log_left), 0, canvas.height);
		backend_interface.stroke();
		color = 0.8;
		backend_interface.set_color(color, color, color);
		foreach(i ; 2..10) {
			backend_interface.vertical_line(canvas.transform[0].world2canvas(log_left+log(cast(double)i)), 0, canvas.height);
		}
		backend_interface.stroke();
		log_left += log(10.0);
	} while (log_left <= canvas.transform[0].max);
}
private void horizontal_grid_log(BackendInterface backend_interface, CanvasProperties *canvas) {
	import std.math;

	// vertical lines
	double log_bottom = log(10.0)*cast(long)(canvas.transform[1].min/log(10.0));
	double left = canvas.transform[0].min;
	double right = canvas.transform[0].max;
	backend_interface.set_line_width(1);
	do {
		double color = 0.5;
		backend_interface.set_color(color, color, color);
		backend_interface.horizontal_line(canvas.transform[1].world2canvas(log_bottom), 0, canvas.width);
		backend_interface.stroke();
		color = 0.8;
		backend_interface.set_color(color, color, color);
		foreach(i ; 2..10) {
			backend_interface.horizontal_line(canvas.transform[1].world2canvas(log_bottom+log(cast(double)i)), 0, canvas.width);
		}
		backend_interface.stroke();
		log_bottom += log(10.0);
	} while (log_bottom <= canvas.transform[1].max);
}

void draw_number_label_x(BackendInterface backend_interface, CanvasProperties *canvas, double x, double y, string text) {
	double we, he;
	backend_interface.text_extent(text, we,he);
	//backend_interface.set_color(0.9,0.9,0.9);
	//backend_interface.rectangle(canvas.transform[0].world2canvas(x)-we/2, canvas.transform[1].world2canvas(y)-he, 
	//                            canvas.transform[0].world2canvas(x)+we/2, canvas.transform[1].world2canvas(y));
	//backend_interface.fill();
	double xpos = canvas.transform[0].world2canvas(x)-we/2;
	double ypos = canvas.transform[1].world2canvas(y);
	if (backend_interface.text_with_border()) {
		backend_interface.set_color(0.9,0.9,0.9);
		backend_interface.text(xpos-1, ypos-1, text);
		backend_interface.text(xpos-1, ypos+1, text);
		backend_interface.text(xpos+1, ypos-1, text);
		backend_interface.text(xpos+1, ypos+1, text);
		backend_interface.stroke();
	}
	backend_interface.set_color(0,0,0);
	backend_interface.text(xpos, ypos, text);
	backend_interface.stroke();
}
void vertical_grid_numbers(BackendInterface backend_interface, CanvasProperties *canvas)
{
	if (canvas.transform[0].logscale) {
		vertical_grid_numbers_log(backend_interface, canvas);
		return;
	}
	import std.math, std.algorithm;
	import std.stdio;
	double left  = canvas.transform[0].min;
	double right = canvas.transform[0].max;
	double bottom = canvas.transform[1].min;
	double oom_delta = log(right-left)/log(10.0); // order of magnitude for the dx value

	//writeln("vertical_grid_numbers");
	next_scaling: foreach (scaling; [0.1,0.2,0.5,1.0,2.0,5.0,10.0]) {
		double dx = exp(log(10.0)*floor(oom_delta))*scaling;
		double xmin = dx*floor(left/dx);
		double xmax = dx* ceil(right/dx);
		// check if there is any overlap between number labels
		//writeln("s min max dx   ", scaling, " ", xmin, " ", xmax, " ", dx);
		double last_text_right = canvas.transform[0].world2canvas(xmin);
		for(double x=xmin; x<(xmax+dx/2); x+=dx) {
			import std.conv;
			double tw, th; // text width and height
			if (x<dx/2 && x>(-dx/2)) x = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
			backend_interface.text_extent(x.to!string, tw, th);
			double text_left = canvas.transform[0].world2canvas(x);
			double text_right = text_left + tw*1.4;
			if (last_text_right > text_left) continue next_scaling;
			last_text_right = text_right;
		}
		// no collision was found -> draw the numbers
		for(double x=xmin; x<(xmax+dx/2); x+=dx) {
			import std.conv;
			if (x<dx/2 && x>(-dx/2)) x = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
			draw_number_label_x(backend_interface, canvas, x,bottom, x.to!string);
		}
		break;
	}
}

void vertical_grid_numbers_log(BackendInterface backend_interface, CanvasProperties *canvas) 
{
	import std.stdio, std.math, std.conv;

	double left  = canvas.transform[0].min;
	double right = canvas.transform[0].max;
	double bottom = canvas.transform[1].min;

	next_scaling: for(double dx=1.0; ;dx+=1.0) {
		//writeln("next_scaling ", dx);
		double xmin = dx*floor(left/log(10.0)/dx);
		double xmax = dx*ceil(right/log(10.0)/dx);
		//writeln(xmin, " / ", xmax, " / ", dx);
		double last_text_right;
		for (double x0=xmin; x0<(xmax+dx/2); x0+=dx) {
			double x = x0*log(10.0);
			double tw, th; // text width and height
			backend_interface.text_extent(exp(x).to!string, tw, th);
			//writeln("=>",exp(x).to!string);
			double text_left = canvas.transform[0].world2canvas(x);
			double text_right = text_left + tw*1.2;
			if (last_text_right !is double.init && last_text_right > text_left) continue next_scaling;
			last_text_right = text_right;
		}
		for(double x0=xmin; x0<(xmax-dx/2); x0+=dx) {
			double x = x0*log(10.0); // log(10^(x0)) = log(exp(x0*log(10)))
			draw_number_label_x(backend_interface, canvas, x,bottom, exp(x).to!string);
			//draw_number_label_x(backend_interface,t, x,bottom, exp(x).to!string);
			if (dx > 1.5) continue;
			double x2 = (x0+dx)*log(10.0);
			double tw, th;
			backend_interface.text_extent(exp(x).to!string, tw, th);
			last_text_right = canvas.transform[0].world2canvas(x)+tw*1.4;
			double end = canvas.transform[0].world2canvas(x2);

			for (int i = 1; i < 10; ++i) {
				double xx  = exp(x0*log(10.0));
				double xxi = xx*(1.0+i);
				double xi = log(xxi);
				backend_interface.text_extent(xxi.to!string, tw,th);
				double text_left = canvas.transform[0].world2canvas(xi);
				double text_right = text_left + tw*1.4;
				if (last_text_right < text_left && text_right < end) {
					draw_number_label_x(backend_interface, canvas, xi,bottom, xxi.to!string);
					//draw_number_label_x(backend_interface, t, xi,bottom, xxi.to!string);
					last_text_right = text_right;
				} 
			}
		}
		break;
	}
}


void draw_number_label_y(BackendInterface backend_interface, CanvasProperties *canvas, double x, double y, string text) {
	double we, he;
	backend_interface.text_extent(text, we,he);
	//backend_interface.rectangle(canvas.transform[0].world2canvas(x)   , canvas.transform[1].world2canvas(y)-he/2, 
	//	                        canvas.transform[0].world2canvas(x)+we, canvas.transform[1].world2canvas(y)+he/2);
	//backend_interface.fill();
	double xpos = canvas.transform[0].world2canvas(x);
	double dy = backend_interface.inverted_y_direction?(+he/2):(-he/2);
	double ypos = canvas.transform[1].world2canvas(y)+dy;
	if (backend_interface.text_with_border()) {
		backend_interface.set_color(0.9,0.9,0.9);
		backend_interface.text(xpos-1, ypos-1, text);
		backend_interface.text(xpos-1, ypos+1, text);
		backend_interface.text(xpos+1, ypos-1, text);
		backend_interface.text(xpos+1, ypos+1, text);
		backend_interface.stroke();
	}
	backend_interface.set_color(0,0,0);
	backend_interface.text(xpos, ypos, text);
	backend_interface.stroke();
}
void horizontal_grid_numbers(BackendInterface backend_interface, CanvasProperties *canvas)
{
	if (canvas.transform[1].logscale) {
		horizontal_grid_numbers_log(backend_interface, canvas);
		return;
	}
	import std.math, std.algorithm;
	import std.stdio;
	double bottom = canvas.transform[1].min;
	double top    = canvas.transform[1].max;
	double left  = canvas.transform[0].min;
	double oom_delta = log(top-bottom)/log(10.0); // order of magnitude for the dy value

	next_scaling: foreach (scaling; [0.1,0.2,0.5,1.0,2.0,5.0,10.0]) {
		double dy = exp(log(10.0)*floor(oom_delta))*scaling;
		double ymin = dy*floor(bottom/dy);
		double ymax = dy* ceil(top/dy);
		// check if there is any overlap between number labels
		double last_text_top = -canvas.transform[1].world2canvas(ymin);
		for(double y=ymin; y<(ymax+dy/2); y+=dy) {
			import std.conv;
			double tw, th; // text width and height
			if (y<dy/2 && y>(-dy/2)) y = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
			backend_interface.text_extent(y.to!string, tw, th);
			double text_bot = -canvas.transform[1].world2canvas(y);
			double text_top = text_bot + th*1.4;
			if (last_text_top > text_bot) continue next_scaling;
			last_text_top = text_top;
		}
		// no collision was found -> draw the numbers
		for(double y=ymin; y<(ymax+dy/2); y+=dy) {
			import std.conv;
			if (y<dy/2 && y>(-dy/2)) y = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
			draw_number_label_y(backend_interface, canvas, left,y, y.to!string);
		}
		break;
	}
}


void horizontal_grid_numbers_log(BackendInterface backend_interface, CanvasProperties *canvas) 
{
	import std.stdio, std.math, std.conv;

	double bottom  = canvas.transform[1].min;
	double top = canvas.transform[1].max;
	double left = canvas.transform[0].min;

	next_scaling: for(double dy=1.0; ;dy+=1.0) {
		//writeln("next_scaling ", dy);
		double ymin = dy*floor(bottom/log(10.0)/dy);
		double ymax = dy*ceil(top/log(10.0)/dy);
		//writeln(ymin, " / ", ymax, " / ", dy);
		double last_text_top;
		for (double y0=ymin; y0<(ymax+dy/2); y0+=dy) {
			double y = y0*log(10.0);
			double tw, th; // text width and height
			backend_interface.text_extent(exp(y).to!string, tw, th);
			//writeln("=>",exp(x).to!string);
			double text_bot = -canvas.transform[1].world2canvas(y);
			double text_top = text_bot + th*1.4;
			if (last_text_top !is double.init && last_text_top > text_bot) continue next_scaling;
			last_text_top = text_top;
		}
		for(double y0=ymin; y0<(ymax-dy/2); y0+=dy) {
			double y = y0*log(10.0); // log(10^(y0)) = log(exp(y0*log(10)))
			draw_number_label_y(backend_interface, canvas, left, y, exp(y).to!string);
			if (dy > 1.5) continue;
			double y2 = (y0+dy)*log(10.0);
			double tw, th;
			backend_interface.text_extent(exp(y).to!string, tw, th);
			last_text_top = -canvas.transform[1].world2canvas(y)+th*1.4;
			double end = -canvas.transform[1].world2canvas(y2);

			for (int i = 1; i < 10; ++i) {
				double yy  = exp(y0*log(10.0));
				double yyi = yy*(1.0+i);
				double yi = log(yyi);
				backend_interface.text_extent(yyi.to!string, tw,th);
				double text_bot = -canvas.transform[1].world2canvas(yi);
				double text_top = text_bot + th*1.4;
				if (last_text_top < text_bot && text_top < end) {
					draw_number_label_y(backend_interface, canvas, left, yi, yyi.to!string);
					last_text_top = text_top;
				} 
			}
		}
		break;
	}
}

void draw_number_label_z(BackendInterface backend_interface, CanvasProperties *canvas, double x, double y, string text) {
	double we, he;
	backend_interface.text_extent(text, we,he);
	//backend_interface.rectangle(canvas.transform[0].world2canvas(x)-we-1, canvas.transform[1].world2canvas(y)-thmax/2+1, 
	//	             canvas.transform[0].world2canvas(x)-1      , canvas.transform[1].world2canvas(y)+thmax/2+1);
	//backend_interface.fill();
	double xpos = canvas.transform[0].world2canvas(x)-we;
	double dy = backend_interface.inverted_y_direction?(+he/2):(-he/2);
	double ypos = canvas.transform[1].world2canvas(y)+dy;
	if (backend_interface.text_with_border()) {
		backend_interface.set_color(0.9,0.9,0.9);
		backend_interface.text(xpos-1, ypos-1, text);
		backend_interface.text(xpos-1, ypos+1, text);
		backend_interface.text(xpos+1, ypos-1, text);
		backend_interface.text(xpos+1, ypos+1, text);
		backend_interface.stroke();
	}
	backend_interface.set_color(0,0,0);
	backend_interface.text(xpos, ypos, text);
	backend_interface.stroke();
}
void color_grid_numbers(BackendInterface backend_interface, CanvasProperties *canvas, double color_key_width)
{
	if (canvas.transform[2].logscale) {
		color_grid_numbers_log(backend_interface, canvas, color_key_width);
		return;
	}
	import std.math, std.algorithm;
	import std.stdio;
	double left   = canvas.transform[0].min;
	double right  = canvas.transform[0].max;
	double bottom = canvas.transform[1].min;
	double top    = canvas.transform[1].max;
	double Zmin   = canvas.transform[2].min;
	double Zmax   = canvas.transform[2].max;
	double oom_delta = log(Zmax-Zmin)/log(10.0); // order of magnitude for the dy value

	//writeln("zmin,zmax ", Zmin, ",", Zmax);
	next_scaling: foreach (scaling; [0.1,0.2,0.5,1.0,2.0,5.0,10.0]) {
		double dz = exp(log(10.0)*floor(oom_delta))*scaling;
		double zmin = dz*floor(Zmin/dz);
		double zmax = dz* ceil(Zmax/dz);
		// check if there is any overlap between number labels
		double ymin = bottom+(top-bottom)*canvas.transform[2].world2canvas(zmin);
		//double ymax = bottom+(top-bottom)*canvas.transform[].world2canvas(zmax);
		double last_text_top = -canvas.transform[1].world2canvas(ymin);
		double twmax=0;
		double thmax=0;
		for(double z=zmin; z<(zmax+dz/2); z+=dz) {

			import std.conv;
			if (z<dz/2 && z>(-dz/2)) z = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
			double tw, th; // text width and height
			backend_interface.text_extent(z.to!string, tw, th);
			if (tw > twmax) twmax = tw;
			if (th > thmax) thmax = th;
			double y = bottom+(top-bottom)*canvas.transform[2].world2canvas(z);
			double text_bot = -canvas.transform[1].world2canvas(y);
			double text_top = text_bot + th*1.4;
			if (last_text_top > text_bot) continue next_scaling;
			last_text_top = text_top;
		}
		// no collision was found -> draw the numbers
		for(double z=zmin; z<(zmax+dz/2); z+=dz) {
			import std.conv;
			if (z<dz/2 && z>(-dz/2)) z = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
			double y = bottom+(top-bottom)*canvas.transform[2].world2canvas(z);
			draw_number_label_z(backend_interface, canvas, right-color_key_width*(right-left),y, z.to!string);
		}
		break;
	}
}

void color_grid_numbers_log(BackendInterface backend_interface, CanvasProperties *canvas, double color_key_width) 
{
	import std.stdio, std.math, std.conv;

	double left   = canvas.transform[0].min;
	double right  = canvas.transform[0].max;
	double bottom = canvas.transform[1].min;
	double top    = canvas.transform[1].max;
	double Zmin   = canvas.transform[2].min;
	double Zmax   = canvas.transform[2].max;

	next_scaling: for(double dz=1.0; ;dz+=1.0) {
		//writeln("next_scaling ", dy);
		double zmin = dz*floor(Zmin/log(10.0)/dz);
		double zmax = dz*ceil(Zmax/log(10.0)/dz);
		//writeln(ymin, " / ", ymax, " / ", dy);
		double last_text_top;
		double twmax=0;
		double thmax=0;
		for (double z0=zmin; z0<(zmax+dz/2); z0+=dz) {
			double z = z0*log(10.0);
			double tw, th; // text width and height
			backend_interface.text_extent(exp(z).to!string, tw, th);
			//writeln("=>",exp(x).to!string);
			if (tw > twmax) twmax = tw;
			if (th > thmax) thmax = th;
			double y = bottom+(top-bottom)*canvas.transform[2].world2canvas(z);
			double text_bot = -canvas.transform[1].world2canvas(y);
			double text_top = text_bot + th*1.4;
			if (last_text_top !is double.init && last_text_top > text_bot) continue next_scaling;
			last_text_top = text_top;
		}
		for(double z0=zmin; z0<(zmax-dz/2); z0+=dz) {
			double z = z0*log(10.0); // log(10^(y0)) = log(exp(y0*log(10)))
			double y = bottom+(top-bottom)*canvas.transform[2].world2canvas(z);
			draw_number_label_z(backend_interface, canvas, right-color_key_width*(right-left),y, exp(z).to!string);
			if (dz > 1.5) continue;
			double z2 = (z0+dz)*log(10.0);
			double y2 = bottom+(top-bottom)*canvas.transform[2].world2canvas(z2);
			double tw, th;
			backend_interface.text_extent(exp(z).to!string, tw, th);
			last_text_top = -canvas.transform[1].world2canvas(y)+th*1.4;
			double end = -canvas.transform[1].world2canvas(y2);

			for (int i = 1; i < 10; ++i) {
				double zz  = exp(z0*log(10.0));
				double zzi = zz*(1.0+i);
				double zi = log(zzi);
				double yi = bottom+(top-bottom)*canvas.transform[2].world2canvas(zi);
				backend_interface.text_extent(zzi.to!string, tw,th);
				double text_bot = -canvas.transform[1].world2canvas(yi);
				double text_top = text_bot + th*1.4;
				if (last_text_top < text_bot && text_top < end) {
					draw_number_label_z(backend_interface, canvas, right-color_key_width*(right-left),yi, zzi.to!string);
					last_text_top = text_top;
				} 
			}
		}
		break;
	}
}

