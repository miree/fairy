module graphics;
@safe:


interface BackendInterface {
	bool inverted_y_direction(); // true if the y-coordinates go from top to bottom

	void initialize();   // must be called before anything else
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
struct CanvasProperties {
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
	@SERIALIZE string[]     itemnames        = [];
	@SERIALIZE Transform[3] transform;

	int rows() {
		with(DisplayMode) final switch(display_mode) {
			case overlay: return 1;
			case rows:    return columns_or_rows;
			case columns: return cast(int)itemnames.length/columns_or_rows;
		}
	}
	int columns() {
		with(DisplayMode) final switch(display_mode) {
			case overlay: return 1;
			case rows:    return cast(int)itemnames.length/columns_or_rows;
			case columns: return columns_or_rows;
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

	// variables for selection box
	double start_selection_x;
	double start_selection_y;
	bool draw_selection_box;
	double current_selection_x;
	double current_selection_y;

	bool translating_ongoing = false;
	bool scaling_ongoing     = false;


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

	//void fit_content_x() {
	//	import std.algorithm;
	//	double left,right;
	//	foreach(ref vis; visualizers.map!(nv=>nv.visualizer)) {
	//				double l,r; 
	//				if (!vis.get_leftright(l,r,transform)) continue;
	//				left =(left  is double.init)?l:min(left,l);
	//				right=(right is double.init)?r:max(right,r);
	//	}
	//	if (left !is double.init && right !is double.init) {
	//		canvas.transformX.set_minmax(left,right);
	//	}
	//}

	//void fit_content_y() {
	//	import std.algorithm;
	//	double bottom,top;
	//	double left = transform.getLeft();
	//	double right= transform.getRight();
	//	foreach(ref vis; visualizers.map!(nv=>nv.visualizer)) {
	//		double b,t;
	//		if (!vis.getBottomTopInLeftRight(b,t, left,right, transform)) continue;
	//		bottom = (bottom is double.init)?b:min(bottom,b);
	//		top    = (top    is double.init)?t:max(top   ,t);
	//	}
	//	if (bottom !is double.init && top !is double.init) {
	//		canvas.transformY.set_minmax(bottom,top);		
	//	}
	//}

	//void fit_content_z() {
	//	import std.algorithm;
	//	double zmin, zmax;
	//	double left = transform.getLeft();
	//	double right= transform.getRight();
	//	double bottom = transform.getBottom();
	//	double top    = transform.getTop();
	//	foreach(ref vis; visualizers.map!(nv=>nv.visualizer)) {
	//		double z1, z2;
	//		if (!vis.getZminZmaxInLeftRightBottomTop(z1,z2, left,right, bottom,top, transform)) continue;
	//		//import std.stdio; writeln("inside fit_content_z ", z1," " ,z2);
	//		zmin = (z1 is double.init)?z1:(zmin is double.init)?z1:min(zmin,z1);
	//		zmax = (z2 is double.init)?z2:(zmax is double.init)?z2:min(zmax,z2);
	//	}
	//	//import std.stdio; writeln("inside fit_content_z ", z1," " ,z2);
	//	if (zmin !is double.init && zmax !is double.init) {
	//		canvas.transformY.set_minmax(zmin,zmax);		
	//	}
	//}

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
		//import std.stdio;
		//writeln("draw_content");
		backend.initialize();
		//backend.set_clip(0,0,canvas.width, canvas.height);
		backend.clear(0.9, 0.9, 0.9);

		//// text size
		backend.set_text_size(global_text_size);
		//if (window_text_size > 0) {
		//	backend.set_text_size(window_text_size);
		//}

		backend.set_color(0,0,0);
		backend.text(100,100,"hallo");

		if (canvas.display_mode == DisplayMode.overlay) {

		//	// find min left and max right of all visualizers
		//	if (autoscale_x) fit_content_x();
		//	if (autoscale_y) fit_content_y();
		//	if (autoscale_z) {
		//		import std.stdio;

		//		fit_content_z();
		//		//writeln("fit_content_z ", transform._zmin, " " , transform._zmax);
		//	}

			canvas.transform[0].update_coefficients(0, 1, canvas.width);
			canvas.transform[1].update_coefficients(0, 1, canvas.height, backend.inverted_y_direction);
			grid_transforms.length = 1;
			grid_transforms[0] = canvas.transform;
			import std.stdio;
			//writeln("tranform x", canvas.transform[0]);
			//writeln("tranform y", canvas.transform[1]);

			if (!canvas.grid_ontop)    draw_grid();
			if (!canvas.numbers_ontop) draw_grid_numbers();
		//	foreach(n_v; visualizers) {
		//		n_v.visualizer.draw(drawer,transform);
		//	}
			if (canvas.grid_ontop)    draw_grid();
			if (canvas.numbers_ontop) draw_grid_numbers();
			draw_grid_numbers();

		//	if (draw_color_bar) {
		//		draw_colorkey(drawer, transform, color_key_width);
		//		color_grid_numbers(drawer, transform, color_key_width);
		//	}	

		//	//if (dim == 2) {
		//	//	draw_colorkey(drawer, transform, color_key_width);
		//	//}

			if (draw_selection_box) draw_selection_box_helper();

		} 
		//else { 
		//	// grid mode
		//	// find number of rows and columns
		//	int rows = columns_or_rows;
		//	int columns = 1;
		//	while (columns*rows < visualizers.length) { 
		//		++columns; 
		//	}
		//	if (row_major) {
		//		import std.algorithm;
		//		swap(columns, rows);
		//	}


		//	//backend.set_color(0.2,0.2,0.2);
		//	//backend.set_line_width(2);
		//	//foreach(row;    1..rows) {
		//	//	backend.horizontal_line(row*(height-1)/rows,0,width);
		//	//	backend.stroke();
		//	//}
		//	//foreach(column; 1..columns) {
		//	//	backend.vertical_line(column*(width-1)/columns,0,height);
		//	//	backend.stroke();
		//	//}

		//	transform.setRowsColumns(rows, columns);

		//	grid_transforms.length = rows*columns;
		//	grid_transforms[0] = transform;

		//	foreach(row; 0..rows) {
		//		foreach(column; 0..columns) {

		//			uint idx = column * rows + row;
		//			if (row_major) {
		//				idx = row * columns + column;
		//			}

		//			transform._content_idx = -1;
		//			if (idx < visualizers.length) {
		//				transform._content_idx = idx;
		//				double left,right, bottom,top, zmin,zmax;
		//				if (autoscale_x && visualizers[idx].visualizer.get_leftright(left,right,transform)) {
		//					canvas.transformX.set_minmax(left,right);
		//				}
		//				if (left  is double.init) left = transform.getLeft();
		//				if (right is double.init) right= transform.getRight();
		//				if (autoscale_y && visualizers[idx].visualizer.getBottomTopInLeftRight(bottom,top, left,right, transform)) {
		//					canvas.transformY.set_minmax(bottom,top);
		//				} else {
		//					bottom = transform.getBottom();
		//					top    = transform.getTop();
		//				}
		//				if (autoscale_z) {
		//					//import std.stdio;writeln("autoscale_z");
		//					if (visualizers[idx].visualizer.getZminZmaxInLeftRightBottomTop(zmin,zmax, left,right, bottom,top, transform)) {
		//						canvas.transformY.set_minmax(zmin,zmax);
		//					}
		//				}
		//			}

		//			transform.update_coefficients(row, column, width, height);
		//			grid_transforms[idx] = transform;

		//			backend.set_clip(     column *width/columns,      row *height/rows, 
		//				            (1.0+column)*width/columns, (1.0+row)*height/rows);

		//			if (!draw_grid_ontop) draw_grid();
		//			if (!draw_nums_ontop) draw_grid_numbers();
		//			if (idx < visualizers.length) {
		//				visualizers[idx].visualizer.draw(drawer,transform);
		//			}
		//			if (draw_grid_ontop) draw_grid();
		//			if (draw_nums_ontop) draw_grid_numbers();
		//			//draw_grid_numbers();

		//			if (draw_color_bar) {
		//				draw_colorkey(drawer, transform, color_key_width);
		//				color_grid_numbers(drawer, transform, color_key_width);
		//			}	

		//			if (draw_selection_box) draw_selection_box_helper();
		//		}
		//	}

		//	backend.set_clip(0,0,width,height);
		//	backend.set_color(0.2,0.2,0.2);
		//	backend.set_line_width(2);
		//	foreach(row;    1..rows) {
		//		backend.horizontal_line(row*(height-1)/rows,0,width);
		//		backend.stroke();
		//	}
		//	foreach(column; 1..columns) {
		//		backend.vertical_line(column*(width-1)/columns,0,height);
		//		backend.stroke();
		//	}

		//}		

		backend.finish();
		backend.need_redraw();

	}

	void mouse_motion(double x, double y, bool ctrl = false, bool shift = false) {
		mouse_pos_x = x;
		mouse_pos_y = y;

		//import std.stdio;
		//writeln("motion ", x, " ", y);
		// determine mouse position and update the mouse_pos label
		foreach( idx, transform ; grid_transforms) {
			import std.math;
			double x_world = canvas.transform[0].canvas2world(x);
			double y_world = canvas.transform[1].canvas2world(y);
			double z_world = canvas.transform[2].canvas2world((y_world - transform[1].min)/transform[1].width);

			if (x_world > canvas.transform[0].min && x_world < canvas.transform[0].max &&
				y_world > canvas.transform[1].min && y_world < canvas.transform[1].max) {
				mouse_transform = canvas.transform;
				if (canvas.transform[0].logscale) {
					x_world = exp(x_world);
				}
				if (canvas.transform[1].logscale) {
					y_world = exp(y_world);
				}
				if (canvas.transform[2].logscale) {
					z_world = exp(z_world);
				}

				backend.show_mouse_pos(x_world, y_world, z_world);
				//if (!canvas.display_mode == DisplayplayMode.overlay) {
				//	if (canvas.transform._content_idx >= 0) {
				//		auto value = visualizers[cast(uint)canvas.transform._content_idx].visualizer.getValue(x_world, y_world);
				//		drawer.show_value(value, visualizers[cast(uint)canvas.transform._content_idx].name);
				//	} else {
				//		drawer.show_value(double.init, "");
				//	}
				//} else {
				//	double last_not_nan_value;
				//	string itemname;
				//	foreach(v; visualizers) {
				//		//import std.stdio;writeln(v.name);
				//		auto value = v.visualizer.getValue(x_world, y_world);
				//		if (value !is double.init) {
				//			last_not_nan_value = value;
				//			itemname = v.name;
				//		}
				//	}
				//	drawer.show_value(last_not_nan_value, itemname);
				//}
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
		canvas.transform[0].scale_start(x, canvas.columns,  canvas.width, false);
		canvas.transform[1].scale_start(y, canvas.rows,     canvas.height, true);
		scaling_ongoing = true;
	}
	void right_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("right release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		canvas.transform[0].scale_finish();
		canvas.transform[1].scale_finish();
		backend.need_redraw();
		scaling_ongoing = false;
	}

	void mid_button_pressed(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("middle click ", nPress, " ",  x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		canvas.transform[0].translate_start(x, canvas.columns,  canvas.width);
		canvas.transform[1].translate_start(y, canvas.rows,     canvas.height);
		translating_ongoing = true;
	}
	void mid_button_released(int nPress, double x, double y, bool ctrl = false, bool shift = false) {
		import std.stdio;
		//writeln("middle release ", nPress, " ", x , " ", y, "     ctrl=", ctrl, "    shift=",shift);
		canvas.transform[0].translate_finish();
		canvas.transform[1].translate_finish();
		backend.need_redraw();
		translating_ongoing = false;
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
		backend.need_redraw();
	}

	/////////////////////////////////////////////////////////
	// scrolling functions (mouse wheel)
	/////////////////////////////////////////////////////////
	void scroll(double dx, double dy, bool ctrl = false, bool shift = false) {
		import std.stdio;
		if (dx) {
			//double amount = dy*(ctrl?-5:-50);
			//transform.translate_one_step(mouse_pos_x, mouse_pos_y, width, height, amount, 0, draw_color_bar?color_key_width:0.0);
		}
		if (dy) {
			double amount = dy*(ctrl?5:50);
			canvas.transform[0].scale_one_step(mouse_pos_x, canvas.columns, canvas.width,  amount,  0.01, false);
			canvas.transform[1].scale_one_step(mouse_pos_y, canvas.rows,    canvas.height, amount,  0.01, true);

			//transform.scale_one_step(mouse_pos_x, mouse_pos_y, width, height, amount, amount, draw_color_bar?color_key_width:0.0);
		}
		if (dx || dy) {
			backend.need_redraw();
		}

		//writeln("scroll ", x , " " , y , "       " , dx , " " , dy, "    width=",size.width, " height=",size.height, "     ctrl=", ctrl, "    shift=",shift);
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
	backend_interface.set_color(0.9,0.9,0.9);
	backend_interface.rectangle(canvas.transform[0].world2canvas(x)-we/2+1, canvas.transform[1].world2canvas(y)-he, 
		             canvas.transform[0].world2canvas(x)+we/2+1, canvas.transform[1].world2canvas(y));
	backend_interface.fill();
	backend_interface.set_color(0,0,0);
	backend_interface.text(canvas.transform[0].world2canvas(x)-we/2+1, canvas.transform[1].world2canvas(y), text);
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
	backend_interface.set_color(0.9,0.9,0.9);
	backend_interface.rectangle(canvas.transform[0].world2canvas(x)   +1, canvas.transform[1].world2canvas(y)-he/2+1, 
		                        canvas.transform[0].world2canvas(x)+we+1, canvas.transform[1].world2canvas(y)+he/2+1);
	backend_interface.fill();
	backend_interface.set_color(0,0,0);
	backend_interface.text(canvas.transform[0].world2canvas(x)+1, canvas.transform[1].world2canvas(y)+he/2+1, text);
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

//void draw_number_label_z(Draw drawer, in Transform t, double x, double y, double twmax, double thmax, string text) {
//	double we, he;
//	drawer.text_extent(text, we,he);
//	drawer.set_color(0.9,0.9,0.9);
//	drawer.rectangle(t.transform_world2canvas_x(x)-we-1, t.transform_world2canvas_y(y)-thmax/2+1, 
//		             t.transform_world2canvas_x(x)-1      , t.transform_world2canvas_y(y)+thmax/2+1);
//	drawer.fill();
//	drawer.set_color(0,0,0);
//	drawer.text(t.transform_world2canvas_x(x)-we-1, t.transform_world2canvas_y(y)+thmax/2+1, text);
//	drawer.stroke();
//}
//void color_grid_numbers(Draw drawer, in Transform t, double color_key_width)
//{
//	if (t._logz) {
//		color_grid_numbers_log(drawer, t, color_key_width);
//		return;
//	}
//	import std.math, std.algorithm;
//	import std.stdio;
//	double bottom = t.getBottom();
//	double top    = t.getTop();
//	double Zmin   = t.getZmin();
//	double Zmax   = t.getZmax();
//	double right  = t.getRight();
//	double left   = t.getLeft();
//	double oom_delta = log(Zmax-Zmin)/log(10.0); // order of magnitude for the dy value

//	next_scaling: foreach (scaling; [0.1,0.2,0.5,1.0,2.0,5.0,10.0]) {
//		double dz = exp(log(10.0)*floor(oom_delta))*scaling;
//		double zmin = dz*floor(Zmin/dz);
//		double zmax = dz* ceil(Zmax/dz);
//		// check if there is any overlap between number labels
//		double ymin = bottom+(top-bottom)*t.transform_world2canvas_z(zmin);
//		//double ymax = bottom+(top-bottom)*t.transform_world2canvas_z(zmax);
//		double last_text_top = -t.transform_world2canvas_y(ymin);
//		double twmax=0;
//		double thmax=0;
//		for(double z=zmin; z<(zmax+dz/2); z+=dz) {
//			import std.conv;
//			if (z<dz/2 && z>(-dz/2)) z = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
//			double tw, th; // text width and height
//			drawer.text_extent(z.to!string, tw, th);
//			if (tw > twmax) twmax = tw;
//			if (th > thmax) thmax = th;
//			double y = bottom+(top-bottom)*t.transform_world2canvas_z(z);
//			double text_bot = -t.transform_world2canvas_y(y);
//			double text_top = text_bot + th*1.4;
//			if (last_text_top > text_bot) continue next_scaling;
//			last_text_top = text_top;
//		}
//		// no collision was found -> draw the numbers
//		for(double z=zmin; z<(zmax+dz/2); z+=dz) {
//			import std.conv;
//			if (z<dz/2 && z>(-dz/2)) z = 0; // prevent long formatting of 0 (e.g. 1.34556e-18)
//			double y = bottom+(top-bottom)*t.transform_world2canvas_z(z);
//			draw_number_label_z(drawer,t, right-color_key_width*(right-left),y, twmax, thmax, z.to!string);
//		}
//		break;
//	}
//}

//void color_grid_numbers_log(Draw drawer, in Transform t, double color_key_width) 
//{
//	import std.stdio, std.math, std.conv;

//	double bottom  = t.getBottom();
//	double top = t.getTop();
//	double left = t.getLeft();
//	double right = t.getRight();
//	double Zmin = t.getZmin();
//	double Zmax = t.getZmax();

//	next_scaling: for(double dz=1.0; ;dz+=1.0) {
//		//writeln("next_scaling ", dy);
//		double zmin = dz*floor(Zmin/log(10.0)/dz);
//		double zmax = dz*ceil(Zmax/log(10.0)/dz);
//		//writeln(ymin, " / ", ymax, " / ", dy);
//		double last_text_top;
//		double twmax=0;
//		double thmax=0;
//		for (double z0=zmin; z0<(zmax+dz/2); z0+=dz) {
//			double z = z0*log(10.0);
//			double tw, th; // text width and height
//			drawer.text_extent(exp(z).to!string, tw, th);
//			//writeln("=>",exp(x).to!string);
//			if (tw > twmax) twmax = tw;
//			if (th > thmax) thmax = th;
//			double y = bottom+(top-bottom)*t.transform_world2canvas_z(z);
//			double text_bot = -t.transform_world2canvas_y(y);
//			double text_top = text_bot + th*1.4;
//			if (last_text_top !is double.init && last_text_top > text_bot) continue next_scaling;
//			last_text_top = text_top;
//		}
//		for(double z0=zmin; z0<(zmax-dz/2); z0+=dz) {
//			double z = z0*log(10.0); // log(10^(y0)) = log(exp(y0*log(10)))
//			double y = bottom+(top-bottom)*t.transform_world2canvas_z(z);
//			draw_number_label_z(drawer,t, right-color_key_width*(right-left),y, twmax, thmax, exp(z).to!string);
//			//draw_number_label_y(drawer,t, left,y, exp(y).to!string);
//			if (dz > 1.5) continue;
//			double z2 = (z0+dz)*log(10.0);
//			double y2 = bottom+(top-bottom)*t.transform_world2canvas_z(z2);
//			double tw, th;
//			drawer.text_extent(exp(z).to!string, tw, th);
//			last_text_top = -t.transform_world2canvas_y(y)+th*1.4;
//			double end = -t.transform_world2canvas_y(y2);

//			for (int i = 1; i < 10; ++i) {
//				double zz  = exp(z0*log(10.0));
//				double zzi = zz*(1.0+i);
//				double zi = log(zzi);
//				double yi = bottom+(top-bottom)*t.transform_world2canvas_z(zi);
//				drawer.text_extent(zzi.to!string, tw,th);
//				double text_bot = -t.transform_world2canvas_y(yi);
//				double text_top = text_bot + th*1.4;
//				if (last_text_top < text_bot && text_top < end) {
//					draw_number_label_z(drawer,t, right-color_key_width*(right-left),yi, twmax, thmax, zzi.to!string);
//					//draw_number_label_y(drawer, t, left,yi, zzi.to!string);
//					last_text_top = text_top;
//				} 
//			}
//		}
//		break;
//	}
//}

