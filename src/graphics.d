module graphics;
@safe:


interface BackendInterface {
	void init();   // must be called before anything else
	void finish(); // must be called after anything else

	void reset_clip();
	void set_clip(double x1, double y1, double x2, double y2);

	void clear(double r, double g, double b);
	void set_color(double r, double g, double b);
	
	// line drawing
	void set_line_width(double w);
	double get_line_width();
	void vertical_line(double x, double y1, double y2);
	void horizontal_line(double y, double x1, double x2);
	void line(double x1, double y1, double x2, double y2);
	void rectangle(double x1, double y1, double x2, double y2);
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

	bool get_leftright(out double[2] leftright, in Transform t)  {
		return false;
	}
	bool get_bottomtop_in_leftright(out double[2] bottomtop, 
		                             in double[2] leftright, 
		                             in Transform box) 
	{
		return false;
	}
	bool get_zminmax_in_leftright_bottomtop(out double[2] zminmax, 
		                                     in double[2] leftright, 
		                                     in double[2] bottomtop, 
		                                     in Transform t) 
	{
		return false;
	}	

	void draw(BackendInterface gi, in Transform t) 
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
struct Canvas {
	@SERIALIZE int          width            = 600;
	@SERIALIZE int          height           = 400;
	@SERIALIZE int          xpos             = -1;
	@SERIALIZE int          ypos             = -1;
	@SERIALIZE int          text_size        = 0;
	@SERIALIZE bool[2]      grid             = [true,true];
	@SERIALIZE bool         grid_ontop       = true;
	@SERIALIZE bool[2]      numbers          = [true,true];
	@SERIALIZE bool         numbers_ontop    = true;
	@SERIALIZE bool         color_bar        = true;
	@SERIALIZE int          dim              = 1;
	@SERIALIZE DisplayMode  display_mode     = DisplayMode.overlay;
	@SERIALIZE int          columns_or_rows  = 1;
	@SERIALIZE double       color_key_width  = 0.05; // percent of canvas width
	@SERIALIZE bool[3]      autoscale        = [false,false,false];
	@SERIALIZE bool         autorefresh      = false;
	@SERIALIZE Transform[3] transform;

	int columns = 1;
	int rows    = 1;
}

unittest {
	import std.json;
	import serializeJSON;
	import std.stdio;

	Canvas canvas;
	JSONValue json;
	serialize(canvas,json);
	json.toString(JSONOptions.specialFloatLiterals).writeln;
}


struct DrawArea {
	Canvas *canvas;

	//struct NameVisualizer {
	//	string name;
	//	Visualizer visualizer;
	//}

	//NameVisualizer[] visualizers;

	void resize(int w, int h) {
		canvas.width  = w;
		canvas.height = h;
	}



	// min is the smallest value larger than 0
	bool set_log(int dim, double min) {
		assert(dim >= 0 && dim < 3);
		return canvas.transform[dim].set_logscale(min);
	}
	bool set_lin(int dim) {
		assert(dim >= 0 && dim < 3);
		return canvas.transform[dim].set_linscale();
	}




	void draw_grid(BackendInterface backend_interface) {
		if (canvas.grid[0]) vertical_grid(backend_interface, canvas);
		if (canvas.grid[1]) horizontal_grid(backend_interface, canvas);
	}
/+
	void draw_grid_numbers() {
		//if (draw_nums_vertical)	  vertical_grid_numbers(drawer, transform);
		//if (draw_nums_horizontal) horizontal_grid_numbers(drawer, transform);			
	}

	void fit_content_x() {
		import std.algorithm;
		double left,right;
		foreach(ref vis; visualizers.map!(nv=>nv.visualizer)) {
					double l,r; 
					if (!vis.get_leftright(l,r,transform)) continue;
					left =(left  is double.init)?l:min(left,l);
					right=(right is double.init)?r:max(right,r);
		}
		if (left !is double.init && right !is double.init) {
			canvas.transformX.set_minmax(left,right);
		}
	}

	void fit_content_y() {
		import std.algorithm;
		double bottom,top;
		double left = transform.getLeft();
		double right= transform.getRight();
		foreach(ref vis; visualizers.map!(nv=>nv.visualizer)) {
			double b,t;
			if (!vis.getBottomTopInLeftRight(b,t, left,right, transform)) continue;
			bottom = (bottom is double.init)?b:min(bottom,b);
			top    = (top    is double.init)?t:max(top   ,t);
		}
		if (bottom !is double.init && top !is double.init) {
			canvas.transformY.set_minmax(bottom,top);		
		}
	}

	void fit_content_z() {
		import std.algorithm;
		double zmin, zmax;
		double left = transform.getLeft();
		double right= transform.getRight();
		double bottom = transform.getBottom();
		double top    = transform.getTop();
		foreach(ref vis; visualizers.map!(nv=>nv.visualizer)) {
			double z1, z2;
			if (!vis.getZminZmaxInLeftRightBottomTop(z1,z2, left,right, bottom,top, transform)) continue;
			//import std.stdio; writeln("inside fit_content_z ", z1," " ,z2);
			zmin = (z1 is double.init)?z1:(zmin is double.init)?z1:min(zmin,z1);
			zmax = (z2 is double.init)?z2:(zmax is double.init)?z2:min(zmax,z2);
		}
		//import std.stdio; writeln("inside fit_content_z ", z1," " ,z2);
		if (zmin !is double.init && zmax !is double.init) {
			canvas.transformY.set_minmax(zmin,zmax);		
		}
	}

	void draw_selection_box_helper() {
		drawer.set_line_width(3);
		drawer.set_color(0.9,0.9,0.9);
		drawer.rectangle(start_selection_x, start_selection_y,
			             mouse_pos_x, mouse_pos_y);
		drawer.stroke();
		drawer.set_line_width(1);
		drawer.set_color(0,0,0);
		drawer.rectangle(start_selection_x, start_selection_y,
			             mouse_pos_x, mouse_pos_y);
		drawer.stroke();
	}

	void draw_content() {
		// nested functions

		drawer.init();
		drawer.set_clip(0,0,width,height);
		drawer.clear(0.9, 0.9, 0.9);

		// text size
		drawer.set_text_size(global_text_size);
		if (window_text_size > 0) {
			drawer.set_text_size(window_text_size);
		}


		if (overlay) {

			// find min left and max right of all visualizers
			if (autoscale_x) fit_content_x();
			if (autoscale_y) fit_content_y();
			if (autoscale_z) {
				import std.stdio;

				fit_content_z();
				//writeln("fit_content_z ", transform._zmin, " " , transform._zmax);
			}

			transform.setRowsColumns(1,1);
			transform.update_coefficients(0,0, width,height);
			grid_transforms.length = 1;
			grid_transforms[0] = transform;

			if (!draw_grid_ontop) draw_grid();
			if (!draw_nums_ontop) draw_grid_numbers();
			foreach(n_v; visualizers) {
				n_v.visualizer.draw(drawer,transform);
			}
			if (draw_grid_ontop) draw_grid();
			if (draw_nums_ontop) draw_grid_numbers();
			//draw_grid_numbers();

			if (draw_color_bar) {
				draw_colorkey(drawer, transform, color_key_width);
				color_grid_numbers(drawer, transform, color_key_width);
			}	

			//if (dim == 2) {
			//	draw_colorkey(drawer, transform, color_key_width);
			//}

			if (draw_selection_box) draw_selection_box_helper();

		} else { 
			// grid mode
			// find number of rows and columns
			int rows = columns_or_rows;
			int columns = 1;
			while (columns*rows < visualizers.length) { 
				++columns; 
			}
			if (row_major) {
				import std.algorithm;
				swap(columns, rows);
			}


			//drawer.set_color(0.2,0.2,0.2);
			//drawer.set_line_width(2);
			//foreach(row;    1..rows) {
			//	drawer.horizontal_line(row*(height-1)/rows,0,width);
			//	drawer.stroke();
			//}
			//foreach(column; 1..columns) {
			//	drawer.vertical_line(column*(width-1)/columns,0,height);
			//	drawer.stroke();
			//}

			transform.setRowsColumns(rows, columns);

			grid_transforms.length = rows*columns;
			grid_transforms[0] = transform;

			foreach(row; 0..rows) {
				foreach(column; 0..columns) {

					uint idx = column * rows + row;
					if (row_major) {
						idx = row * columns + column;
					}

					transform._content_idx = -1;
					if (idx < visualizers.length) {
						transform._content_idx = idx;
						double left,right, bottom,top, zmin,zmax;
						if (autoscale_x && visualizers[idx].visualizer.get_leftright(left,right,transform)) {
							canvas.transformX.set_minmax(left,right);
						}
						if (left  is double.init) left = transform.getLeft();
						if (right is double.init) right= transform.getRight();
						if (autoscale_y && visualizers[idx].visualizer.getBottomTopInLeftRight(bottom,top, left,right, transform)) {
							canvas.transformY.set_minmax(bottom,top);
						} else {
							bottom = transform.getBottom();
							top    = transform.getTop();
						}
						if (autoscale_z) {
							//import std.stdio;writeln("autoscale_z");
							if (visualizers[idx].visualizer.getZminZmaxInLeftRightBottomTop(zmin,zmax, left,right, bottom,top, transform)) {
								canvas.transformY.set_minmax(zmin,zmax);
							}
						}
					}

					transform.update_coefficients(row, column, width, height);
					grid_transforms[idx] = transform;

					drawer.set_clip(     column *width/columns,      row *height/rows, 
						            (1.0+column)*width/columns, (1.0+row)*height/rows);

					if (!draw_grid_ontop) draw_grid();
					if (!draw_nums_ontop) draw_grid_numbers();
					if (idx < visualizers.length) {
						visualizers[idx].visualizer.draw(drawer,transform);
					}
					if (draw_grid_ontop) draw_grid();
					if (draw_nums_ontop) draw_grid_numbers();
					//draw_grid_numbers();

					if (draw_color_bar) {
						draw_colorkey(drawer, transform, color_key_width);
						color_grid_numbers(drawer, transform, color_key_width);
					}	

					if (draw_selection_box) draw_selection_box_helper();
				}
			}

			drawer.set_clip(0,0,width,height);
			drawer.set_color(0.2,0.2,0.2);
			drawer.set_line_width(2);
			foreach(row;    1..rows) {
				drawer.horizontal_line(row*(height-1)/rows,0,width);
				drawer.stroke();
			}
			foreach(column; 1..columns) {
				drawer.vertical_line(column*(width-1)/columns,0,height);
				drawer.stroke();
			}

		}		

		drawer.finish();

	}

	void mouse_motion(double x, double y, bool ctrl = false, bool shift = false) {
		mouse_pos_x = x;
		mouse_pos_y = y;

		// determine mouse position and update the mouse_pos label
		foreach( idx, transform ; grid_transforms) {
			import std.math;
			double x_world = transform.transform_canvas2world_x(x);
			double y_world = transform.transform_canvas2world_y(y);
			double z_world = transform.transform_canvas2world_z((y_world - transform.getBottom())/transform.getHeight());

			if (x_world > transform.getLeft()   && x_world < transform.getRight() &&
				y_world > transform.getBottom() && y_world < transform.getTop()) {
				mouse_transform = transform;
				if (transform._logx) {
					x_world = exp(x_world);
				}
				if (transform._logy) {
					y_world = exp(y_world);
				}
				if (transform._logz) {
					z_world = exp(z_world);
				}

				drawer.show_mouse_pos(x_world, y_world, z_world);
				if (!overlay) {
					if (transform._content_idx >= 0) {
						auto value = visualizers[cast(uint)transform._content_idx].visualizer.getValue(x_world, y_world);
						drawer.show_value(value, visualizers[cast(uint)transform._content_idx].name);
					} else {
						drawer.show_value(double.init, "");
					}
				} else {
					double last_not_nan_value;
					string itemname;
					foreach(v; visualizers) {
						//import std.stdio;writeln(v.name);
						auto value = v.visualizer.getValue(x_world, y_world);
						if (value !is double.init) {
							last_not_nan_value = value;
							itemname = v.name;
						}
					}
					drawer.show_value(last_not_nan_value, itemname);
				}
			}
		}

		//drawer.show_mouse_pos(transform.transform_canvas2world_x(x), transform.transform_canvas2world_y(y));
		with (transform) {
			if (scaling.active)     scale_ongoing(x, y);
			if (translating.active) translate_ongoing(x, y);
			if (scaling.active || translating.active) {
				drawer.need_redraw();
				//import std.stdio; writeln("need_redraw 1");
			}
		}
		if (draw_selection_box) {
			current_selection_x = x;
			current_selection_y = y;
			drawer.need_redraw();
			//import std.stdio; writeln("need_redraw 2");
		}
	}

	void right_button_pressed(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("right click ", nPress, " ",  x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		transform.scale_start(x,y, width,height, draw_color_bar?color_key_width:0.0);
	}
	void right_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("right release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		transform.scale_finish(x,y);
		drawer.need_redraw();
	}

	void mid_button_pressed(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("middle click ", nPress, " ",  x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		transform.translate_start(x,y,width,height, draw_color_bar?color_key_width:0.0);
		
	}
	void mid_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("middle release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		transform.translate_finish(x,y);
		drawer.need_redraw();
	}

	void left_button_pressed(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("left click ", nPress, " ",  x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		start_selection_x = x;
		start_selection_y = y;
		draw_selection_box = true;
	}
	void left_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("left release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		draw_selection_box = false;
		drawer.need_redraw();
	}
	/////////////////////////////////////////////////////////
	// scrolling functions (mouse wheel)
	/////////////////////////////////////////////////////////
	void scroll(double dx, double dy, bool ctrl = false, bool shift = false) {
		import std.stdio;
		if (dx) {
			double amount = dy*(ctrl?-5:-50);
			transform.translate_one_step(mouse_pos_x, mouse_pos_y, width, height, amount, 0, draw_color_bar?color_key_width:0.0);
		}
		if (dy) {
			double amount = dy*(ctrl?-5:-50);
			transform.scale_one_step(mouse_pos_x, mouse_pos_y, width, height, amount, amount, draw_color_bar?color_key_width:0.0);
		}
		if (dx || dy) {
			drawer.need_redraw();
		}

		//writeln("scroll ", x , " " , y , "       " , dx , " " , dy, "    width=",size.width, " height=",size.height, "     ctrl=", ctrl, "    shift=",shift);
	}
+/
}


void vertical_grid(BackendInterface backend_interface, Canvas *canvas) {
	//if (canvas.transform[0].logscale) {
	//	//vertical_grid_log(canvas);
	//	return;
	//}

	import std.stdio;
	backend_interface.set_color(1,0,0);
	backend_interface.set_line_width(4);
	backend_interface.vertical_line(canvas.width/2,0,canvas.height);
	backend_interface.stroke();

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
void horizontal_grid(BackendInterface backend_interface, Canvas *canvas) {
	//if (canvas.transform[1].logscale) {
	//	//horizontal_grid_log(canvas);
	//	return;
	//}
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

/+


void vertical_grid_log(Draw drawer, in Transform t) {
	import std.math;

	// vertical lines
	double log_left = log(10.0)*cast(long)(t.getLeft()/log(10.0));
	double bottom = t.getBottom;
	double top    = t.getTop;
	drawer.set_line_width(1);
	do {
		double color = 0.5;
		drawer.set_color(color, color, color);
		vertical_line(drawer, t, log_left, bottom, top);
		drawer.stroke();
		color = 0.8;
		drawer.set_color(color, color, color);
		foreach(i ; 2..10) {
			vertical_line(drawer, t, log_left+log(cast(double)i), bottom, top);
		}
		drawer.stroke();
		log_left += log(10.0);
	} while (log_left <= t.getRight);
}
private void horizontal_grid_log(Draw drawer, in Transform t) {
	import std.math;

	// vertical lines
	double log_bottom = log(10.0)*cast(long)(t.getBottom()/log(10.0));
	double left = t.getLeft;
	double right = t.getRight;
	drawer.set_line_width(1);
	do {
		double color = 0.5;
		drawer.set_color(color, color, color);
		horizontal_line(drawer, t, log_bottom, left, right);
		drawer.stroke();
		color = 0.8;
		drawer.set_color(color, color, color);
		foreach(i ; 2..10) {
			horizontal_line(drawer, t, log_bottom+log(cast(double)i), left, right);
		}
		drawer.stroke();
		log_bottom += log(10.0);
	} while (log_bottom <= t.getTop);
}
+/