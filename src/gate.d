module gate;
@safe:

import item;
import std.json;
import serializeJSON;


class Gate1DFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Gate1D(json);
	}
}

import graphics;
import interactive;

class Gate1D : Visual, Item
{
public:
	struct Data{
		@SERIALIZE double min;
		@SERIALIZE double max;
		@SERIALIZE int direction; // 0 -> x-direction, 1 -> y-direction
	}	
	Data data;
	double min_delta  = 0; // relevant for user interaction 
	double max_delta = 0; // relevant for user interaction

	ulong item_version = 0;

	this(double min, double max, int direction = 0) {
		data.min = min;
		data.max = max;
		data.direction = direction;
	}
	this(ref JSONValue json) {
		import std.stdio;
		try data = deserialize!Data(json);
		catch(Exception e) writeln("Function deserialize error: ", e.msg);
	}
	override JSONValue toJSON()  { return serialize(data); }
	override string get_type()  { return "gate.Gate1D"; }
	override void reset() {}
	override ulong getVersion() { return item_version; }
	override void overrideVersion(ulong new_version) { item_version = new_version; }

	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) {
		return new Gate1DVisualizer(this, item_version);
	}
}

class Gate1DVisualizer : Visualizer, Interactive
{
import transform;
import graphics;
private:
	Gate1D gate;
	long highlight_handle = -1; // bitmask: bit 0 means min, bit 1 means max
	long selected_handle  = -1; // bitmask: bit 0 means min, bit 1 means max
	                            // min selected:  0x1
	                            // max selected: 0x2
	                            // both selected:  0x3
public:
	this(Gate1D g, ulong itemversion) {
		ulong dim = 1;
		super(itemversion, dim);
		gate = g;

		if (gate.data.min > gate.data.max) {
			import std.algorithm;
			swap(gate.data.min, gate.data.max);
		}
	}
	void draw_y(BackendInterface d, in Transform[3] t) const	{
		import std.algorithm;
		double min  = gate.data.min  + gate.min_delta;
		double max = gate.data.max + gate.max_delta;
		//if (min > max) swap(min, max);

		import std.math;
		double y1 = t[1].world2canvas(min);
		double y2 = t[1].world2canvas(max);
		double left   = t[0].world2canvas(t[0].min);
		double right  = t[0].world2canvas(t[0].max);
		if (t[1].logscale) {
			if (min > 0) y1 = t[1].world2canvas(log(min)); 
			else         y1 = t[1].world2canvas(t[1].min); 
			if (max > 0) y2 = t[1].world2canvas(log(max)); 
			else         y2 = t[1].world2canvas(t[1].min); 
		}
		d.set_color(1,1,1,0.3);
		d.rectangle(left,y1,right,y2);
		d.fill();

		switch (highlight_handle) {
			case 3:
				d.set_color(0.6,0.6,1);
				d.set_line_width(6);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.horizontal_line(y1, left, right);
				d.stroke();
				d.set_color(0.6,0.6,1);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.horizontal_line(y2, left, right);
				d.stroke();
			break;
			case 1:
				d.set_color(0.6,0.6,1);
				d.set_line_width(6);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.horizontal_line(y1, left, right);
				d.stroke();
				d.set_color(0.0,0.0,1);
				d.set_line_width(3);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.horizontal_line(y2, left, right);
				d.stroke();
			break;
			case 2:
				d.set_color(0.6,0.6,1);
				d.set_line_width(6);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.horizontal_line(y2, left, right);
				d.stroke();
				d.set_color(0.0,0.0,1);
				d.set_line_width(3);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.horizontal_line(y1, left, right);
				d.stroke();
			break;
			default:
				d.set_color(0.0,0.0,1);
				d.set_line_width(3);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.horizontal_line(y1, left, right);
				d.stroke();
				d.set_color(0.0,0.0,1);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.horizontal_line(y2, left, right);
				d.stroke();
		}
	}

	override void draw(BackendInterface d, in Transform[3] t) const	{
		if (gate.data.direction == 1) {
			draw_y(d,t);
			return;
		}

		import std.algorithm;
		double min  = gate.data.min  + gate.min_delta;
		double max = gate.data.max + gate.max_delta;
		//if (min > max) swap(min, max);

		import std.math;
		double x1 = t[0].world2canvas(min);
		double x2 = t[0].world2canvas(max);
		double bottom = t[1].world2canvas(t[1].min);
		double top    = t[1].world2canvas(t[1].max);
		if (t[0].logscale) {
			if (min > 0)  x1 = t[0].world2canvas(log(min)); 
			else           x1 = t[0].world2canvas(t[0].min); 
			if (max > 0) x2 = t[0].world2canvas(log(max)); 
			else           x2 = t[0].world2canvas(t[0].min); 
		}
		d.set_color(1,1,1,0.3);
		d.rectangle(x1,bottom,x2,top);
		d.fill();

		switch (highlight_handle) {
			case 3:
				d.set_color(0.6,0.6,1);
				d.set_line_width(6);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.vertical_line(x1, bottom, top);
				d.stroke();
				d.set_color(0.6,0.6,1);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.vertical_line(x2, bottom, top);
				d.stroke();
			break;
			case 1:
				d.set_color(0.6,0.6,1);
				d.set_line_width(6);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.vertical_line(x1, bottom, top);
				d.stroke();
				d.set_color(0.0,0.0,1);
				d.set_line_width(3);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.vertical_line(x2, bottom, top);
				d.stroke();
			break;
			case 2:
				d.set_color(0.6,0.6,1);
				d.set_line_width(6);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.vertical_line(x2, bottom, top);
				d.stroke();
				d.set_color(0.0,0.0,1);
				d.set_line_width(3);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.vertical_line(x1, bottom, top);
				d.stroke();
			break;
			default:
				d.set_color(0.0,0.0,1);
				d.set_line_width(3);
				if (selected_handle == 3 || selected_handle == 1) d.set_color(1,0,0);
				d.vertical_line(x1, bottom, top);
				d.stroke();
				d.set_color(0.0,0.0,1);
				if (selected_handle == 3 || selected_handle == 2) d.set_color(1,0,0);
				d.vertical_line(x2, bottom, top);
				d.stroke();
		}
	}
	override double getValue(double x, double y) { return 0.0; }
	override bool get_leftright(out double[2] minmax, in Transform[3] t)  {
		if (gate.data.direction == 1) {
			return false;
		}
		import std.algorithm, std.math;
		if (gate.data.min > gate.data.max) swap(gate.data.min, gate.data.max);
		minmax[0] = gate.data.min;
		minmax[1] = gate.data.max;
		bool result = false;
		if (t[0].logscale) {
			if (gate.data.max > 0) {
				minmax[1] = log(gate.data.max);
				result = true;
			} 
			if (gate.data.min > 0) {
				minmax[0] = log(gate.data.min);
			}
			else {
				minmax[0] = t[0].min;
			}
		} else {
			result = true;
		}
		return result;
	}	
	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) 
	{
		if (gate.data.direction == 1) {
			import std.algorithm, std.math;
			if (gate.data.min > gate.data.max) swap(gate.data.min, gate.data.max);
			bt[0] = gate.data.min;
			bt[1] = gate.data.max;
			bool result = false;
			if (t[1].logscale) {
				if (gate.data.max > 0) {
					bt[1] = log(gate.data.max);
					result = true;
				} 
				if (gate.data.min > 0) {
					bt[0] = log(gate.data.min);
				}
				else {
					bt[0] = t[0].min;
				}
			} else {
				result = true;
			}
			return result;			
		} 
		return false; 
	}
	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
		if (handle != -1 || selected_handle != -1) {
			double delta;
			if (gate.data.direction == 0) delta = t[0].canvas2world_delta(x_canvas - x_canvas_start);
			else                          delta = t[1].canvas2world_delta(y_canvas - y_canvas_start);

			if (t[gate.data.direction].logscale) {
				import std.math;
				if (highlight_handle == 3 || highlight_handle == 1 || selected_handle == 3 || selected_handle == 1) {
					gate.min_delta = gate.data.min*exp(delta) - gate.data.min;
				}
				if (highlight_handle == 3 || highlight_handle == 2 || selected_handle == 3 || selected_handle == 2) {
					gate.max_delta = gate.data.max*exp(delta) - gate.data.max;
				}
			} else {
				if (highlight_handle == 3 || highlight_handle == 1 || selected_handle == 3 || selected_handle == 1) {
					gate.min_delta = delta;
				}
				if (highlight_handle == 3 || highlight_handle == 2 || selected_handle == 3 || selected_handle == 2) {
					gate.max_delta = delta;
				}
			}
			if (end) {
				if (highlight_handle == 3 || highlight_handle == 1 || selected_handle == 3 || selected_handle == 1) {
					gate.data.min += gate.min_delta;
				}
				if (highlight_handle == 3 || highlight_handle == 2 || selected_handle == 3 || selected_handle == 2) {
					gate.data.max += gate.max_delta;
				}
				gate.min_delta = 0;
				gate.max_delta = 0;
				if (gate.data.min > gate.data.max) {
					import std.algorithm;
					swap(gate.data.min, gate.data.max);

					     if (highlight_handle == 1) highlight_handle = 2;
					else if (highlight_handle == 2) highlight_handle = 1;
					
					     if (selected_handle == 1) selected_handle = 2;
					else if (selected_handle == 2) selected_handle = 1;
				}
			}
		}
	}

	override BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t) { 

		double mouse_world;
		if (gate.data.direction == 0) mouse_world = mouse_world_x;
		else                          mouse_world = mouse_world_y;

		import std.algorithm, std.math;
		// outer   inner   outer
		//   |   |      |   |
		//   | L |  C   | R |   <== three regions min,Center,max
		//   |   |      |   |
		if (t[gate.data.direction].logscale && (gate.data.min < 0 || gate.data.max < 0)) {
			// in this case one part of the gate is guaranteed to be outside the visible canvas
			// we do not support moving the gate under that circumstances 
			return BoundingBox();
		}

		// here we know that both edges of the gate are visible
		double canvas_min = t[gate.data.direction].world2canvas(t[gate.data.direction].log(gate.data.min));
		double canvas_max = t[gate.data.direction].world2canvas(t[gate.data.direction].log(gate.data.max));
		if (gate.data.direction == 1) swap(canvas_min, canvas_max);
		//import std.stdio;
		//writeln(":::: ", gate.data.min, " ", canvas_min, " ", gate.data.max, " ", canvas_max, " ", mouse_world);
		const double min_width = 10; // we give the user at least that many pixels to grab on
		if (canvas_max-canvas_min < min_width) {
			double canvas_midpoint = 0.5*(canvas_min+canvas_max);
			canvas_min = canvas_midpoint-min_width/2;
			canvas_max = canvas_midpoint+min_width/2;
		}
		double canvas_outer_min = canvas_min-min_width;
		double canvas_outer_max = canvas_max+min_width;
		import std.math;
		double margin = abs((canvas_max-canvas_min)) - 5*min_width;
		if (margin <      0   ) margin = 0;
		if (margin > min_width) margin = min_width;
		canvas_min       += margin/2;
		canvas_outer_min += margin/2; 
		canvas_max       -= margin/2;
		canvas_outer_max -= margin/2; 

		// move back to world coordinates
		if (gate.data.direction == 1) {
			swap(canvas_min, canvas_max);
			swap(canvas_outer_min, canvas_outer_max);
		}
		double min       = t[gate.data.direction].exp(t[gate.data.direction].canvas2world(canvas_min)); 
		double max       = t[gate.data.direction].exp(t[gate.data.direction].canvas2world(canvas_max)); 
		double outer_min = t[gate.data.direction].exp(t[gate.data.direction].canvas2world(canvas_outer_min)); 
		double outer_max = t[gate.data.direction].exp(t[gate.data.direction].canvas2world(canvas_outer_max)); 


		//import std.stdio;
		//writeln(":::: ", outer_min, " ", min, " ", max, " ", outer_max, "   ", mouse_world_x);
		if (mouse_world > min && mouse_world < max)  // Center region
		{
			if (gate.data.direction == 0) return BoundingBox(min, t[1].min, max, t[1].max, max-min, this, 3);
			else                          return BoundingBox(t[0].min, min, t[1].max, max, max-min, this, 3);
		} 
		else if (mouse_world > outer_min && mouse_world < min) 
		{
			if (gate.data.direction == 0) return BoundingBox(outer_min, t[1].min, min, t[1].max, outer_min-min, this, 1);			
			else                          return BoundingBox(t[0].min, outer_min, t[0].max, min, outer_min-min, this, 1);			
		}
		else if (mouse_world > max && mouse_world < outer_max) 
		{
			if (gate.data.direction == 0) return BoundingBox(max, t[1].min, outer_max, t[1].max, outer_max-max, this, 2);
			else                          return BoundingBox(t[0].min, max, t[0].max, outer_max, outer_max-max, this, 2);
		}
		return BoundingBox(); 
	}
	override bool setHighlightHandle(long handle) {
		if (handle != highlight_handle) {
			highlight_handle = handle;
			return true;
		} 
		return false; 
	}
	override void select(long handle, bool add_or_remove = false) {
		//import std.stdio;
		//writeln("handle ", handle, " was selected  (selected_handle=",selected_handle,")  add_or_remove = ", add_or_remove);
		if (add_or_remove) {
			if (selected_handle != -1 && handle != -1) {
				if (selected_handle & handle) {
					//writeln("overlap => remove");
					selected_handle &= ~handle;
				}
				else {
					//writeln("no overlap => add");
					selected_handle |= handle;
				}

			} else {
				selected_handle = handle;
			}
		} else {
			selected_handle = handle;
		}
	}

	void select_box_y(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
		//import std.stdio;
		//writeln("box: ", x1, " ", y1, " ", x2, " ", y2, "add=", add, "  remove=", remove);
		if (t[1].logscale && (gate.data.min < 0 || gate.data.max < 0)) {
			return;
		}
		
		import std.algorithm;
		if (y2 < y1) swap(y1,y2);

		double min_canvas = t[1].world2canvas(t[1].log(gate.data.min));
		double max_canvas = t[1].world2canvas(t[1].log(gate.data.max));

		int pattern = 0;
		
		if (min_canvas > y1 && min_canvas < y2) pattern |= 1;
		if (max_canvas > y1 && max_canvas < y2) pattern |= 2;

		if (selected_handle == -1) selected_handle = 0;
		if (add) {
			selected_handle |= pattern;
		}
		else if (remove) {
			selected_handle &= ~pattern;
		}
		else {
			selected_handle = pattern;
		}
		if (selected_handle == 0) selected_handle = -1;

	}
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
		if (gate.data.direction == 1) {
			select_box_y(x1,y1,x2,y2,t,add,remove);
			return;
		}

		//import std.stdio;
		//writeln("box: ", x1, " ", y1, " ", x2, " ", y2, "add=", add, "  remove=", remove);
		if (t[0].logscale && (gate.data.min < 0 || gate.data.max < 0)) {
			return;
		}
		
		import std.algorithm;
		if (x2 < x1) swap(x1,x2);

		double min_canvas = t[0].world2canvas(t[0].log(gate.data.min));
		double max_canvas = t[0].world2canvas(t[0].log(gate.data.max));

		int pattern = 0;
		
		if (min_canvas > x1 && min_canvas < x2) pattern |= 1;
		if (max_canvas > x1 && max_canvas < x2) pattern |= 2;

		if (selected_handle == -1) selected_handle = 0;
		if (add) {
			selected_handle |= pattern;
		}
		else if (remove) {
			selected_handle &= ~pattern;
		}
		else {
			selected_handle = pattern;
		}
		if (selected_handle == 0) selected_handle = -1;

	}

}













class Gate2DFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Gate2D(json);
	}
}

import graphics;
import interactive;

class Gate2D : Visual, Item
{
public:
	struct Data{
		@SERIALIZE double xmin;
		@SERIALIZE double xmax;
		@SERIALIZE double ymin;
		@SERIALIZE double ymax;
	}	
	Data data;

	double xmin_delta = 0; // relevant for user interaction 
	double xmax_delta = 0; // relevant for user interaction
	double ymin_delta = 0; // relevant for user interaction 
	double ymax_delta = 0; // relevant for user interaction

	ulong item_version = 0;

	this(double xmin, double xmax, double ymin, double ymax) {
		data.xmin = xmin;
		data.xmax = xmax;
		data.ymin = ymin;
		data.ymax = ymax;
	}
	this(ref JSONValue json) {
		import std.stdio;
		try data = deserialize!Data(json);
		catch(Exception e) writeln("Function deserialize error: ", e.msg);
	}
	override JSONValue toJSON()  { return serialize(data); }
	override string get_type()  { return "gate.Gate2D"; }
	override void reset() {}
	override ulong getVersion() { return item_version; }
	override void overrideVersion(ulong new_version) { item_version = new_version; }

	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) {
		return new Gate2DVisualizer(this, item_version);
	}
}



class Gate2DVisualizer : Visualizer, Interactive
{
import transform;
import graphics;
private:
	Gate2D gate;
	long highlight_handle = -1; // bitmask: bit 0 means xmin, bit 1 means xmax, bit 2 means ymin, bit 3 means ymax
	long selected_handle  = -1; // bitmask: bit 0 means xmin, bit 1 means xmax, bit 2 means ymin, bit 3 means ymax
	                            // xmin selected:  0x1
	                            // xmax selected: 0x2
	                            // xminmax selected:  0x3
	                            // all selected: 0xf
public:
	this(Gate2D g, ulong itemversion) {
		ulong dim = 2;
		super(itemversion, dim);
		gate = g;

		import std.algorithm;
		if (gate.data.xmin > gate.data.xmax) swap(gate.data.xmin, gate.data.xmax);
		if (gate.data.ymin > gate.data.ymax) swap(gate.data.ymin, gate.data.ymax);

	}

	override void draw(BackendInterface d, in Transform[3] t) const	{

		import std.algorithm;
		double xmin = gate.data.xmin + gate.xmin_delta;
		double xmax = gate.data.xmax + gate.xmax_delta;
		double ymin = gate.data.ymin + gate.ymin_delta;
		double ymax = gate.data.ymax + gate.ymax_delta;

		import std.math;
		double x1 = t[0].world2canvas(xmin);
		double x2 = t[0].world2canvas(xmax);
		double y1 = t[1].world2canvas(ymin);
		double y2 = t[1].world2canvas(ymax);

		if (t[0].logscale) {
			if (xmin > 0) x1 = t[0].world2canvas(log(xmin)); 
			else          x1 = t[0].world2canvas(t[0].min); 
			if (xmax > 0) x2 = t[0].world2canvas(log(xmax)); 
			else          x2 = t[0].world2canvas(t[0].min); 
		}
		if (t[1].logscale) {
			if (ymin > 0) y1 = t[1].world2canvas(log(ymin)); 
			else          y1 = t[1].world2canvas(t[1].min); 
			if (ymax > 0) y2 = t[1].world2canvas(log(ymax)); 
			else          y2 = t[1].world2canvas(t[1].min); 
		}

		d.set_color(1,1,1,0.3);
		d.rectangle(x1,y1,x2,y2);
		d.fill();

		for(uint i = 0; i < 4; ++i) {
			bool is_highlighted = ((highlight_handle!=-1) && (highlight_handle&(1<<i)))?true:false;
			bool is_selected    = ((selected_handle!=-1) && (selected_handle &(1<<i)))?true:false;
			d.set_color(0.0,0.0,1);
			d.set_line_width(3);
			if (is_highlighted) { d.set_color(0.6,0.6,1); d.set_line_width(6); }
			if (is_selected)    { d.set_color(1.0,0.0,0); d.set_line_width(6); }
			switch(i) {
				case 0:   d.vertical_line(x1,y1,y2); break;
				case 1:   d.vertical_line(x2,y1,y2); break;
				case 2: d.horizontal_line(y1,x1,x2); break;
				case 3: d.horizontal_line(y2,x1,x2); break;
				default: break;
			}
			d.stroke();
		}
		//double boundsx1,boundsx2,boundsx3,boundsx4;
		//boundaries(xmin,xmax,t[0],boundsx1,boundsx2,boundsx3,boundsx4);
		//d.set_color(0,0.4,0);
		//d.set_line_width(2);
		//d.vertical_line(t[0].world2canvas(boundsx1),t[1].world2canvas(t[1].min),t[1].world2canvas(t[1].max));
		//d.stroke();
		//d.vertical_line(t[0].world2canvas(boundsx2),t[1].world2canvas(t[1].min),t[1].world2canvas(t[1].max));
		//d.stroke();
		//d.vertical_line(t[0].world2canvas(boundsx3),t[1].world2canvas(t[1].min),t[1].world2canvas(t[1].max));
		//d.stroke();
		//d.vertical_line(t[0].world2canvas(boundsx4),t[1].world2canvas(t[1].min),t[1].world2canvas(t[1].max));
		//d.stroke();

		//double boundsy1,boundsy2,boundsy3,boundsy4;
		//boundaries(ymin,ymax,t[1],boundsy1,boundsy2,boundsy3,boundsy4);
		//d.set_color(0.4,0,0);
		//d.set_line_width(2);
		//d.horizontal_line(t[1].world2canvas(boundsy1),t[0].world2canvas(t[0].min),t[0].world2canvas(t[0].max));
		//d.stroke();
		//d.horizontal_line(t[1].world2canvas(boundsy2),t[0].world2canvas(t[0].min),t[0].world2canvas(t[0].max));
		//d.stroke();
		//d.horizontal_line(t[1].world2canvas(boundsy3),t[0].world2canvas(t[0].min),t[0].world2canvas(t[0].max));
		//d.stroke();
		//d.horizontal_line(t[1].world2canvas(boundsy4),t[0].world2canvas(t[0].min),t[0].world2canvas(t[0].max));
		//d.stroke();

	}
	override double getValue(double x, double y) { return 0.0; }
	override bool get_leftright(out double[2] minmax, in Transform[3] t)  {
		import std.algorithm, std.math;
		if (gate.data.xmin > gate.data.xmax) swap(gate.data.xmin, gate.data.xmax);
		minmax[0] = gate.data.xmin;
		minmax[1] = gate.data.xmax;
		bool result = false;
		if (t[0].logscale) {
			if (gate.data.xmax > 0) {
				minmax[1] = log(gate.data.xmax);
				result = true;
			} 
			if (gate.data.xmin > 0) {
				minmax[0] = log(gate.data.xmin);
			}
			else {
				minmax[0] = t[0].min;
			}
		} else {
			result = true;
		}
		return result;
	}	
	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) 
	{
		import std.algorithm, std.math;
		if (gate.data.ymin > gate.data.ymax) swap(gate.data.ymin, gate.data.ymax);
		bt[0] = gate.data.ymin;
		bt[1] = gate.data.ymax;
		bool result = false;
		if (t[1].logscale) {
			if (gate.data.ymax > 0) {
				bt[1] = log(gate.data.ymax);
				result = true;
			} 
			if (gate.data.ymin > 0) {
				bt[0] = log(gate.data.ymin);
			}
			else {
				bt[0] = t[1].min;
			}
		} else {
			result = true;
		}
		return result;			
	}
	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {

		if (handle != -1 || selected_handle != -1) {
			//import std.stdio;
			//writeln("drag handle = ", handle, "   selected_handle = ", selected_handle);

			double deltax = t[0].canvas2world_delta(x_canvas - x_canvas_start);
			double deltay = t[1].canvas2world_delta(y_canvas - y_canvas_start);

			if (t[0].logscale) {
				import std.math;
				if ((handle & 0x1) || ((selected_handle != -1) && (selected_handle & 0x1))) if (gate.data.xmin > 0) gate.xmin_delta = gate.data.xmin*exp(deltax) - gate.data.xmin;
				if ((handle & 0x2) || ((selected_handle != -1) && (selected_handle & 0x2))) if (gate.data.xmax > 0) gate.xmax_delta = gate.data.xmax*exp(deltax) - gate.data.xmax;
			} else {
				if ((handle & 0x1) || ((selected_handle != -1) && (selected_handle & 0x1))) gate.xmin_delta = deltax;
				if ((handle & 0x2) || ((selected_handle != -1) && (selected_handle & 0x2))) gate.xmax_delta = deltax;
			}

			if (t[1].logscale) {
				import std.math;
				if ((handle & 0x4) || ((selected_handle != -1) && (selected_handle & 0x4))) if (gate.data.ymin > 0) gate.ymin_delta = gate.data.ymin*exp(deltay) - gate.data.ymin;
				if ((handle & 0x8) || ((selected_handle != -1) && (selected_handle & 0x8))) if (gate.data.ymax > 0) gate.ymax_delta = gate.data.ymax*exp(deltay) - gate.data.ymax;
			} else {
				if ((handle & 0x4) || ((selected_handle != -1) && (selected_handle & 0x4))) gate.ymin_delta = deltay;
				if ((handle & 0x8) || ((selected_handle != -1) && (selected_handle & 0x8))) gate.ymax_delta = deltay;
			}

			if (end) {
				if ((handle & 0x1) || ((selected_handle != -1) && (selected_handle & 0x1))) gate.data.xmin += gate.xmin_delta;
				if ((handle & 0x2) || ((selected_handle != -1) && (selected_handle & 0x2))) gate.data.xmax += gate.xmax_delta;
				gate.xmin_delta = 0;
				gate.xmax_delta = 0;

				if ((handle & 0x4) || ((selected_handle != -1) && (selected_handle & 0x4))) gate.data.ymin += gate.ymin_delta;
				if ((handle & 0x8) || ((selected_handle != -1) && (selected_handle & 0x8))) gate.data.ymax += gate.ymax_delta;
				gate.ymin_delta = 0;
				gate.ymax_delta = 0;
			}
		}

	}


	void boundaries(double min_world, double max_world, in Transform t, out double world_outer_min, out double world_min, out double world_max, out double world_outer_max) const {
		import std.algorithm, std.math;
		double canvas_min, canvas_max;
		import std.stdio;

		if (t.logscale && min_world < 0) canvas_min = double.init;
		else                             canvas_min = t.world2canvas(t.log(min_world));
		if (t.logscale && max_world < 0) canvas_max = double.init;
		else                             canvas_max = t.world2canvas(t.log(max_world));

		double canvas_midpoint = 0.5*(canvas_min+canvas_max);
		double min_width = 10;
		double factor = 1;
		if (canvas_min > canvas_max) factor = -1;
		//writeln("canvas_min: ", canvas_min, " canvas_max: ", canvas_max, " factor: ", factor);
		
		if (factor*(canvas_max - canvas_min) < min_width) {
			canvas_min = canvas_midpoint - factor*min_width/2;
			canvas_max = canvas_midpoint + factor*min_width/2;
		}
		double canvas_outer_min = canvas_min - factor*min_width;
		double canvas_outer_max = canvas_max + factor*min_width;

		double margin = abs(factor*(canvas_max-canvas_min)) - 5*min_width;
		if (margin <      0   ) margin = 0;
		if (margin > min_width) margin = min_width;
		canvas_min       += factor*margin/2;
		canvas_outer_min += factor*margin/2;
		canvas_max       -= factor*margin/2;
		canvas_outer_max -= factor*margin/2; 

		world_outer_min = t.canvas2world(canvas_outer_min);
		world_min       = t.canvas2world(canvas_min);
		world_max       = t.canvas2world(canvas_max);
		world_outer_max = t.canvas2world(canvas_outer_max);

	}
	override BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t) { 

		double outer_xmin, xmin, xmax, outer_xmax;
		double outer_ymin, ymin, ymax, outer_ymax;

		boundaries(gate.data.xmin, gate.data.xmax, t[0], outer_xmin, xmin, xmax, outer_xmax);
		boundaries(gate.data.ymin, gate.data.ymax, t[1], outer_ymin, ymin, ymax, outer_ymax);

		//import std.stdio;
		//writeln("-----------------");
		//writeln(outer_xmin, " ", xmin, " ", xmax, " ", outer_xmax);
		//writeln(outer_ymin, " ", ymin, " ", ymax, " ", outer_ymax);
		double mouse_x = mouse_world_x;
		double mouse_y = mouse_world_y;
		//writeln(mouse_x, " ", mouse_y);

		import std.algorithm;
		if (outer_xmin < mouse_x && xmin >= mouse_x   &&   outer_ymin < mouse_y && ymin >= mouse_y) {
			return BoundingBox(outer_xmin, outer_ymin, xmin, ymin, min(xmin-outer_xmin,ymin-outer_ymin), this, (1<<0)|(1<<2));
		}
		if (xmin < mouse_x && xmax >= mouse_x   &&   outer_ymin < mouse_y && ymin >= mouse_y) {
			return BoundingBox(xmin,       outer_ymin, xmax, ymin, min(xmax-xmin,ymin-outer_ymin), this, (1<<2));
		}
		if (xmax < mouse_x && outer_xmax >= mouse_x   &&   outer_ymin < mouse_y && ymin >= mouse_y) {
			return BoundingBox(xmax,       outer_ymin, outer_xmax, ymin, min(outer_xmax-xmax,ymin-outer_ymin), this, (1<<1)|(1<<2));
		}

		if (outer_xmin < mouse_x && xmin >= mouse_x   &&   ymin < mouse_y && ymax >= mouse_y) {
			return BoundingBox(outer_xmin, ymin, xmin, ymax, min(xmin-outer_xmin,ymax-ymin), this, (1<<0));
		}
		if (xmin < mouse_x && xmax >= mouse_x   &&   ymin < mouse_y && ymax >= mouse_y) {
			return BoundingBox(xmin,       ymin, xmax, ymax, min(xmax-xmin,ymax-ymin), this, 0xf);
		}
		if (xmax < mouse_x && outer_xmax >= mouse_x   &&   ymin < mouse_y && ymax >= mouse_y) {
			return BoundingBox(xmax,       ymin, outer_xmax, ymax, min(outer_xmax-xmax,ymax-ymin), this, (1<<1));
		}

		if (outer_xmin < mouse_x && xmin >= mouse_x   &&   ymax < mouse_y && outer_ymax >= mouse_y) {
			return BoundingBox(outer_xmin, ymax, xmin, outer_ymax, min(xmin-outer_xmin,outer_ymax-ymax), this, (1<<0)|(1<<3));
		}
		if (xmin < mouse_x && xmax >= mouse_x   &&   ymax < mouse_y && outer_ymax >= mouse_y) {
			return BoundingBox(xmin,       ymax, xmax, outer_ymax, min(xmax-xmin,outer_ymax-ymax), this, (1<<3));
		}
		if (xmax < mouse_x && outer_xmax >= mouse_x   &&   ymax < mouse_y && outer_ymax >= mouse_y) {
			return BoundingBox(xmax,       ymax, outer_xmax, outer_ymax, min(outer_xmax-xmax,outer_ymax-ymax), this, (1<<1)|(1<<3));
		}

		return BoundingBox();
	}
	override bool setHighlightHandle(long handle) {
		if (handle != highlight_handle) {
			highlight_handle = handle;
			return true;
		} 
		return false; 
	}
	override void select(long handle, bool add_or_remove = false) {
		//import std.stdio;
		//writeln("handle ", handle, " was selected  (selected_handle=",selected_handle,")  add_or_remove = ", add_or_remove);
		if (add_or_remove) {
			if (selected_handle != -1 && handle != -1) {
				if (selected_handle & handle) {
					//writeln("overlap => remove");
					selected_handle &= ~handle;
				}
				else {
					//writeln("no overlap => add");
					selected_handle |= handle;
				}

			} else {
				selected_handle = handle;
			}
		} else {
			selected_handle = handle;
		}
	}


	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
		//if (gate.data.direction == 1) {
		//	select_box_y(x1,y1,x2,y2,t,add,remove);
		//	return;
		//}

		////import std.stdio;
		////writeln("box: ", x1, " ", y1, " ", x2, " ", y2, "add=", add, "  remove=", remove);
		//if (t[0].logscale && (gate.data.min < 0 || gate.data.max < 0)) {
		//	return;
		//}
		
		//import std.algorithm;
		//if (x2 < x1) swap(x1,x2);

		//double min_canvas = t[0].world2canvas(t[0].log(gate.data.min));
		//double max_canvas = t[0].world2canvas(t[0].log(gate.data.max));

		//int pattern = 0;
		
		//if (min_canvas > x1 && min_canvas < x2) pattern |= 1;
		//if (max_canvas > x1 && max_canvas < x2) pattern |= 2;

		//if (selected_handle == -1) selected_handle = 0;
		//if (add) {
		//	selected_handle |= pattern;
		//}
		//else if (remove) {
		//	selected_handle &= ~pattern;
		//}
		//else {
		//	selected_handle = pattern;
		//}
		//if (selected_handle == 0) selected_handle = -1;

	}

}








