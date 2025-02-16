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