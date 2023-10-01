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

import transform;
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

enum DisplayMode { overlay, row_major, col_major }
import serializeJSON;


struct Canvas {
	GraphicsInterface graphics;

	@SERIALIZE Transform[3] transform;
	@SERIALIZE int          window_text_size = 0;
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