module draw;
@safe:

interface GraphicsInterface {
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
	ulong    create_bitmap(int w, int h);
	void   destroy_bitmap(ulong handle);
	@trusted
	uint[] access_bitmap_data(ulong handle);
	void    access_bitmap_done(ulong handle);
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

	void draw(GraphicsInterface gi, in Transform t) 
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

import serializeJSON;
class Canvas : PersistentData!JSONValue {
	GraphicsInterface graphics;

	enum DisplayMode { overlay, row_major, col_major }
	struct Data {
		Transform   transform;
		int         window_text_size = 0;
		bool[2]     grid             = [true,true];
		bool        grid_ontop       = true;
		bool[2]     numbers          = [true,true];
		bool        numbers_ontop    = true;
		bool        color_bar        = true;
		int         dim              = 1;
		DisplayMode display_mode     = DisplayMode.overlay;
		int         columns_or_rows  = 1;
		double      color_key_width  = 0.05; // percent of canvas width
		bool[3]     autoscale        = [false,false,false];
		bool        autorefresh      = false;
	}
	Data persistent_data;
	void read(in JSONValue json) {
		persistent_data = deserialize!Data(json);
	}
	void write(ref JSONValue json) {
		persistent_data.serialize(json);
	}
}

import std.math;
struct Transform
{

	int[2] canvas_width; // in pixels
	int[2] segments; // if the canvas is not in overlay mode, this contains the number of grid segments in each direction

	double[3] min = [-1,-1,-1];
	double[3] max = [ 1, 1, 1];
	double[3] delta = [0,0,0];
	double[3] scale = [1,1,1];
	double[3] min_width = [1e-3, 1e-3, 1e-3];
	double[3] max_width = [1e10, 1e10, 1e10];

	bool[3] logscale; 

	long content_idx = -1;

	void set_minmax_width(ulong dim, double[2] minmax) {
		min_width[dim] = minmax[0];
		max_width[dim] = minmax[1];
	}

	double get_min(ulong dim)   const pure { return min[dim]-delta[dim];            }
	double get_max(ulong dim)   const pure { return get_min(dim)+get_width(dim);      }
	double get_width(ulong dim) const pure { return (min[dim]-max[dim])*scale[dim]; }

	void set_minmax(ulong dim, double[2] minmax) {
		min[dim] = minmax[0];
		max[dim] = minmax[1];
		if (max[dim]-min[dim] < min_width[dim]) {
			double mid = 0.5*(min[dim]+max[dim]);
			min[dim] = mid - 0.5*min_width[dim];
			max[dim] = mid + 0.5*min_width[dim];
		}
		scale[dim] = 1;
		delta[dim] = 0;
	}

	void switch_log2lin(ref double a, ref double b, double max) {
		a = std.math.exp(a);
		b = std.math.exp(b);
		if (b-a > max) b = a+max;
	}
	double minlog(double x, double min=0.1) {
		if (x<=0) x = min;
		return std.math.log(x);
	}
	void switch_lin2log(ref double a, ref double b, double min) {
		a = minlog(a);
		b = minlog(b);
		if (b <= a+min) b=a+min;
	}

	bool set_logscale(ulong dim, bool l) {
		bool changed = (logscale[dim] != l);
		if (changed &&  l) switch_lin2log(min[dim],max[dim],min_width[dim]);
		if (changed && !l) switch_log2lin(min[dim],max[dim],max_width[dim]);
		logscale[dim] = l;
		return changed;
	}

	double[3] a;
	double[3] b;

	void update_coefficients(int[2] segment, int[2] canvas_w) {
		canvas_width[] = canvas_w[];
		double[2] offset = 1.0 * segment[] * canvas_width[] / segments[];
		double[2] width  = 1.0 * canvas_width[] / segments[];

		b[0] = canvas_width[0] / get_width(0);
		a[0] = offset[0] - b[0] * get_min(0);

		b[1] = - canvas_width[1] / get_width(1);
		a[1] = offset[1] - b[1] * get_max(1);

		b[2] = 1.0 / get_width(2);
		a[2] = - b[2] * get_min(2);
	}

	double get_pixel_width(ulong dim) pure {
		return (dim?(-1.0):(1.0)) / b[dim];
	}

	double world2canvas(ulong dim, in double x) const pure {
		return a[dim] + b[dim] * x;
	}
	double world2canvas_delta(ulong dim, in double dx) const pure {
		return b[dim] * dx;
	}

	double canvas2world(ulong dim, in double x) const pure {
		return (x - a[dim]) / b[dim];
	}
	double canvas2world_delta(ulong dim, in double dx) const pure {
		return dx / b[dim];
	}

	double log(ulong dim, in double x, in double xmin = 0.0) const pure {
		if (logscale[dim]) return (x>0)?std.math.log(x):((xmin>0.0)?std.math.log(xmin):get_min(dim));
		return x;
	}
	double exp(ulong dim, in double x) const pure { 
		if (logscale[dim]) return std.math.exp(x);
		return x;
	}

	// takes into account the tiling to reduce the x position to the value inside the first tile
	double reduce_canvas(ulong dim, in double x) const pure {
		double segment_width = canvas_width[dim] / segments[dim];
		int segment = cast(int)(x / segment_width);
		if (segment < 0) segment = 0;
		return x - segment*segment_width;
	}
}

private:
struct TransformationManipulator
{
	Transform *transform;
	double[2] start_canvas;
	double[3] start_world;
	bool active = false;
	bool dim2 = false; // indicate that the manipulation is along dimesion 2 (z-direction)
}
void translate_one_step(ref TransformationManipulator translation, double[2] canvas_start, int[2] canvas_width, double[2] step, double color_key_width) {
	translate_start(translation, canvas_start, canvas_width, color_key_width);
	double[2] canvas_current = canvas_start[] + step[];
	translate_ongoing(translation, canvas_current);
	translate_finish(translation, canvas_current);
}
void translate_start(ref TransformationManipulator translation, double[2] canvas_start, int[2] canvas_width, double color_key_width) {
	with(translation) {
		start_canvas[] = canvas_start[];
		transform.update_coefficients([0,0], canvas_width);
		start_world[0] = transform.canvas2world(0, transform.reduce_canvas(0, canvas_start[0]));
		start_world[1] = transform.canvas2world(1, transform.reduce_canvas(1, canvas_start[1]));
		start_world[2] = transform.canvas2world(2, 1.0*(start_world[1] - transform.get_min(1)) / transform.get_width(1));
		active = true;
		dim2 = (color_key_width > 0.0) && (start_world[0] > transform.get_min(0) + (1.0 - color_key_width)*transform.get_width(0));
	}
}
void translate_ongoing(ref TransformationManipulator translation, double[2] canvas_current) {
	with(translation) {
		if (dim2) {
			transform.delta[2] = transform.canvas2world_delta(1, canvas_current[1] - start_canvas[1])/transform.get_width(1)/transform.b[2];
		} else {
			transform.delta[0] = (canvas_current[0] - start_canvas[0] ) / transform.b[0];
			transform.delta[1] = (canvas_current[1] - start_canvas[1] ) / transform.b[1];
		}
	}
}
void translate_finish(ref TransformationManipulator translation, double[2] canvas_current) {
	with (translation) {
		with (transform) {
			if (dim2) {
				min[2] -= delta[2];
				max[2] -= delta[2];
			} else {
				static foreach(dim; 0..2) {{
					min[dim] -= delta[dim];
					max[dim] -= delta[dim];
				}}
			}
			delta[] = 0;
		}
		active = false;
		dim2 = false;
	}
}
void scale_one_step(ref TransformationManipulator scaler, double[2] canvas_start, int[2] canvas_width, double[2] step, double color_key_width) {
	scale_start(scaler, canvas_start, canvas_width, color_key_width);
	double[2] canvas_current = canvas_start[] + step[];
	scale_ongoing(scaler, canvas_current);
	scale_finish(scaler, canvas_current);
}
void scale_start(ref TransformationManipulator scaler, double[2] canvas_start, int[2] canvas_width, double color_key_width) {
	with(scaler) {
		start_canvas[] = canvas_start[];
		transform.update_coefficients([0,0], canvas_width);
		start_world[0] = transform.canvas2world(0, transform.reduce_canvas(0, canvas_start[0]));
		start_world[1] = transform.canvas2world(1, transform.reduce_canvas(1, canvas_start[1]));
		start_world[2] = transform.canvas2world(2, 1.0*(start_world[1] - transform.get_min(1)) / transform.get_width(1));
		active = true;
		dim2 = (color_key_width > 0.0) && (start_world[0] > transform.get_min(0) + (1.0 - color_key_width)*transform.get_width(0));
	}
}
void scale_ongoing(ref TransformationManipulator scaler, double[2] canvas_current) {
	with(scaler) {
		import std.math;
		if (dim2) {
			double scale_distance = canvas_current[1] - scaler.start_canvas[1];
			transform.scale[2] = std.math.exp(scale_distance/100.0);
			double new_min = scaler.start_world[2] - transform.scale[2]*(scaler.start_world[2] - transform.min[2]);
			transform.delta[2] = transform.min[2] - new_min;
		} else {
			static foreach(dim; 0..2) {{
				double scale_distance = canvas_current[dim] - scaler.start_canvas[dim];
				if (dim == 0) scale_distance *= -1;
				transform.scale[dim] = std.math.exp(scale_distance/100.0);
				if (transform.get_width(dim) < transform.min_width[dim]) transform.scale[dim] = transform.min_width[dim] / (transform.max[dim]-transform.min[dim]);
				if (transform.get_width(dim) > transform.max_width[dim]) transform.scale[dim] = transform.max_width[dim] / (transform.max[dim]-transform.min[dim]);
				double new_min = scaler.start_world[dim] - transform.scale[dim]*(scaler.start_world[dim] - transform.min[dim]);
				transform.delta[dim] = transform.min[dim] - new_min;
			}}
		}
	}	
}
void scale_finish(ref TransformationManipulator scaler, double[2] canvas_current) {
	with(scaler) {
		with(transform) {
			if (dim2) {
				double width = get_width(2);
				min[2] -= delta[2];
				max[2]  = min[2] + width;
			} else {
				static foreach(dim; 0..2) {{
					double width = get_width(dim);
					min[dim] -= delta[dim];
					max[dim]  = min[dim] + width;
				}}
			}
			scale[] = 1.0;
			delta[] = 0.0;
		}
		active = false;
		dim2 = false;
	}
}

