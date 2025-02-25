module gate;
@safe:

import item;
import std.json;
import serializeJSON;


void set_gate_color(BackendInterface d) {
	d.set_color(0,7,0);
}
void set_gate_color_selected(BackendInterface d) {
	d.set_color(4,7,4);
}

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

		d.set_line_width(2);
		if ((highlight_handle != -1) && (highlight_handle & 0x1)) d.set_line_width(4);
		d.set_gate_color(); 
		if ((selected_handle != -1) && (selected_handle  & 0x1)) d.set_color(1,0,0);
		d.horizontal_line(y1, left, right);
		d.stroke();

		d.set_line_width(2);
		if ((highlight_handle != -1) && (highlight_handle & 0x2)) d.set_line_width(4);
		d.set_gate_color(); 
		if ((selected_handle != -1) && (selected_handle  & 0x2)) d.set_color(1,0,0);
		d.horizontal_line(y2, left, right);
		d.stroke();
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

		d.set_line_width(2);
		if ((highlight_handle != -1) && (highlight_handle & 0x1)) d.set_line_width(4);
		d.set_gate_color(); 
		if ((selected_handle != -1) && (selected_handle  & 0x1)) d.set_color(1,0,0);
		d.vertical_line(x1, bottom, top);
		d.stroke();

		d.set_line_width(2);
		if ((highlight_handle != -1) && (highlight_handle & 0x2)) d.set_line_width(4);
		d.set_gate_color(); 
		if ((selected_handle != -1) && (selected_handle  & 0x2)) d.set_color(1,0,0);
		d.vertical_line(x2, bottom, top);
		d.stroke();

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
					if (gate.data.min > 0) gate.min_delta = gate.data.min*exp(delta) - gate.data.min;
				}
				if (highlight_handle == 3 || highlight_handle == 2 || selected_handle == 3 || selected_handle == 2) {
					if (gate.data.max > 0) gate.max_delta = gate.data.max*exp(delta) - gate.data.max;
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
		if (gate.data.direction == 0) mouse_world = t[0].log(mouse_world_x);
		else                          mouse_world = t[1].log(mouse_world_y);

		import std.algorithm, std.math;
		// outer   inner   outer
		//   |   |      |   |
		//   | L |  C   | R |   <== three regions min,Center,max
		//   |   |      |   |

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
		double min       = (t[gate.data.direction].canvas2world(canvas_min)); 
		double max       = (t[gate.data.direction].canvas2world(canvas_max)); 
		double outer_min = (t[gate.data.direction].canvas2world(canvas_outer_min)); 
		double outer_max = (t[gate.data.direction].canvas2world(canvas_outer_max)); 


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
	override void select(long handle, bool add_or_remove = false, bool action = false) {
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
			d.set_gate_color();
			d.set_line_width(2);
			if (is_highlighted) { d.set_line_width(4); }
			if (is_selected)    { d.set_color(1,0,0);  }
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
				if (((highlight_handle != -1) && (highlight_handle & 0x1)) || ((selected_handle != -1) && (selected_handle & 0x1))) if (gate.data.xmin > 0) gate.xmin_delta = gate.data.xmin*exp(deltax) - gate.data.xmin;
				if (((highlight_handle != -1) && (highlight_handle & 0x2)) || ((selected_handle != -1) && (selected_handle & 0x2))) if (gate.data.xmax > 0) gate.xmax_delta = gate.data.xmax*exp(deltax) - gate.data.xmax;
			} else {
				if (((highlight_handle != -1) && (highlight_handle & 0x1)) || ((selected_handle != -1) && (selected_handle & 0x1))) gate.xmin_delta = deltax;
				if (((highlight_handle != -1) && (highlight_handle & 0x2)) || ((selected_handle != -1) && (selected_handle & 0x2))) gate.xmax_delta = deltax;
			}

			if (t[1].logscale) {
				import std.math;
				if (((highlight_handle != -1) && (highlight_handle & 0x4)) || ((selected_handle != -1) && (selected_handle & 0x4))) if (gate.data.ymin > 0) gate.ymin_delta = gate.data.ymin*exp(deltay) - gate.data.ymin;
				if (((highlight_handle != -1) && (highlight_handle & 0x8)) || ((selected_handle != -1) && (selected_handle & 0x8))) if (gate.data.ymax > 0) gate.ymax_delta = gate.data.ymax*exp(deltay) - gate.data.ymax;
			} else {
				if (((highlight_handle != -1) && (highlight_handle & 0x4)) || ((selected_handle != -1) && (selected_handle & 0x4))) gate.ymin_delta = deltay;
				if (((highlight_handle != -1) && (highlight_handle & 0x8)) || ((selected_handle != -1) && (selected_handle & 0x8))) gate.ymax_delta = deltay;
			}

			if (end) {
				if (((highlight_handle != -1) && (highlight_handle & 0x1)) || ((selected_handle != -1) && (selected_handle & 0x1))) gate.data.xmin += gate.xmin_delta;
				if (((highlight_handle != -1) && (highlight_handle & 0x2)) || ((selected_handle != -1) && (selected_handle & 0x2))) gate.data.xmax += gate.xmax_delta;
				gate.xmin_delta = 0;
				gate.xmax_delta = 0;

				if (((highlight_handle != -1) && (highlight_handle & 0x4)) || ((selected_handle != -1) && (selected_handle & 0x4))) gate.data.ymin += gate.ymin_delta;
				if (((highlight_handle != -1) && (highlight_handle & 0x8)) || ((selected_handle != -1) && (selected_handle & 0x8))) gate.data.ymax += gate.ymax_delta;
				gate.ymin_delta = 0;
				gate.ymax_delta = 0;

				import std.algorithm;
				if (gate.data.xmin > gate.data.xmax) {
					swap(gate.data.xmin, gate.data.xmax);
					if ((highlight_handle&0x3) == 0x1) {
						highlight_handle &= ~0x3;
						highlight_handle |= 0x2;
					}
					else if ((highlight_handle&0x3) == 0x2) {
						highlight_handle &= ~0x3;
						highlight_handle |= 0x1;
					}
					if ((selected_handle&0x3) == 0x1) {
						selected_handle &= ~0x3;
						selected_handle |= 0x2;
					}
					else if ((selected_handle&0x3) == 0x2) {
						selected_handle &= ~0x3;
						selected_handle |= 0x1;
					}
				}
				if (gate.data.ymin > gate.data.ymax) {
					swap(gate.data.ymin, gate.data.ymax);
					if ((highlight_handle&0xc) == 0x4) {
						highlight_handle &= ~0xc;
						highlight_handle |= 0x8;
					}
					else if ((highlight_handle&0xc) == 0x8) {
						highlight_handle &= ~0xc;
						highlight_handle |= 0x4;
					}
					if ((selected_handle&0xc) == 0x4) {
						selected_handle &= ~0xc;
						selected_handle |= 0x8;
					}
					else if ((selected_handle&0xc) == 0x8) {
						selected_handle &= ~0xc;
						selected_handle |= 0x4;
					}
				}
			}
		}

	}


	void boundaries(double min_world, double max_world, in Transform t, out double world_outer_min, out double world_min, out double world_max, out double world_outer_max) const {
		import std.algorithm, std.math;
		double canvas_min, canvas_max;
		import std.stdio;

		canvas_min = t.world2canvas(t.log(min_world));
		canvas_max = t.world2canvas(t.log(max_world));

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
		double mouse_x = t[0].log(mouse_world_x);
		double mouse_y = t[1].log(mouse_world_y);
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
	override void select(long handle, bool add_or_remove = false, bool action = false) {
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
		//import std.stdio;
		//writeln("box: ", x1, " ", y1, " ", x2, " ", y2, "add=", add, "  remove=", remove);
		if (t[0].logscale && (gate.data.xmin < 0 || gate.data.xmax < 0)) {
			return;
		}
		if (t[1].logscale && (gate.data.ymin < 0 || gate.data.ymax < 0)) {
			return;
		}
		
		double xmin_canvas = t[0].world2canvas(t[0].log(gate.data.xmin));
		double xmax_canvas = t[0].world2canvas(t[0].log(gate.data.xmax));
		double ymin_canvas = t[1].world2canvas(t[1].log(gate.data.ymin));
		double ymax_canvas = t[1].world2canvas(t[1].log(gate.data.ymax));

		import std.algorithm;
		if (x2 < x1) swap(x1,x2);
		if (y2 < y1) swap(y1,y2);


		int pattern = 0;

		// left side inside or intersecting box
		if (x1 < xmin_canvas && x2 > xmin_canvas) {
			if (!(ymin_canvas < y1 && ymax_canvas < y1)) {
				if (!(ymin_canvas > y2 && ymax_canvas > y2)) {
					pattern |= 0x1;
				}
			}
		}

		// right side inside or intersecting box
		if (x1 < xmax_canvas && x2 > xmax_canvas) {
			if (!(ymin_canvas < y1 && ymax_canvas < y1)) {
				if (!(ymin_canvas > y2 && ymax_canvas > y2)) {
					pattern |= 0x2;
				}
			}
		}

		// bottom side inside or intersecting
		if (y1 < ymin_canvas && y2 > ymin_canvas) {
			if (!(xmin_canvas < x1 && xmax_canvas < x1)) {
				if (!(xmin_canvas > x2 && xmax_canvas > x2)) {
					pattern |= 0x4;
				}
			}
		}
		// bottom side inside or intersecting
		if (y1 < ymax_canvas && y2 > ymax_canvas) {
			if (!(xmin_canvas < x1 && xmax_canvas < x1)) {
				if (!(xmin_canvas > x2 && xmax_canvas > x2)) {
					pattern |= 0x8;
				}
			}
		}
		
		//if (min_canvas > x1 && min_canvas < x2) pattern |= 1;
		//if (max_canvas > x1 && max_canvas < x2) pattern |= 2;



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














import item;
import std.json;
import serializeJSON;
import graphics;

class PolyGateFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new PolyGate(json);
	}
}
class PolyGate : Visual, Item
{
public:
	struct Data {
		@SERIALIZE double[2][] points;
	}
	this(double[2][] ps) {
		data.points   = ps.dup;
		deltas.length = data.points.length;
		foreach(ref d; deltas) d = [0.0, 0.0];
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
			deltas.length = data.points.length;
			foreach(ref d; deltas) d = [0.0, 0.0];
		} catch(Exception e) {
			writeln("ERROR in PolyGate.this(ref JSONValue json)", e.msg);
		} 
	}
	override JSONValue toJSON() { 
		return serialize(data); 
	}
	override string get_type()  {
		return "gate.PolyGate";
	}
	override void reset() {
	}
	override ulong getVersion() {
		return item_version;
	}
	override void overrideVersion(ulong new_version) {
		item_version = new_version;
	}
	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) 
	{
		return new PolyGateVisualizer(this, item_version);
	}

	bool inside(double x, double y) {
		bool is_inside = false;
		double[2] p1 = data.points[$-1];
		foreach(p; data.points) {
			double[2] p2 = p;
			if ( ((p2[1] > y) != (p1[1] > y)) &&
			     (x < (p1[0] - p2[0]) * (y - p2[1]) / (p1[1] - p2[1]) + p2[0]) ) {
			    is_inside = !is_inside;
			}
			p1 = p2;
		}
		return is_inside;
	}


	Data data;
	ulong item_version;
	double[2][] deltas; // not part of stored data, but part of interactive appearance
private:
}






import interactive;

class PolyGateVisualizer : Visualizer,  Interactive
{
private:

	bool closest_point_on_line(out double x, out double y, // 
		                       double ax, double ay, // beginning of line
		                       double bx, double by, // end of line
		                       double mx, double my) // test point
	{
		import std.math;
		double ux=mx-ax;
		double uy=my-ay;
		double vx=bx-ax;
		double vy=by-ay;
		double lu = sqrt(ux*ux+uy*uy);
		double lv = sqrt(vx*vx+vy*vy);
		if (lu < 1e-10 || lv < 1e-10) {
			return false;
		}
		double p = (ux*vx+uy*vy)/lv/lv;
		if (p >= 0 && p <= 1) {
			x = ax+p*vx;
			y = ay+p*vy;
			return true;
		}
		return false;
	}
	unittest {
		import std.stdio;

		double cx,cy;
		closest_point_on_line(cx,cy, 0,0, 1,0, 0.5,0);
		writeln("cx=", cx, "  cy=",cy);
		closest_point_on_line(cx,cy, 0,0, 1,0, 0.5,1);
		writeln("cx=", cx, "  cy=",cy);
		closest_point_on_line(cx,cy, 0,0, 1,1, 1,0);
		writeln("cx=", cx, "  cy=",cy);

		writeln("closest_point_on_line test done");

	}

private:
	PolyGate gate;
	// the following indices 
	long[] selected;
	long highlight_handle = -1;

public:

	this(PolyGate g, ulong itemversion){
		super(itemversion, 2);
		gate = g;
	}
	import graphics, transform;

	override double getValue(double x, double y) { return 0.0; }
	override bool get_leftright(out double[2] minmax, in Transform[3] t)  {
		double left, right;
		foreach(point; gate.data.points) {
			if (left is double.init || left > point[0]) {
				left = point[0];
			}
			if (right is double.init || right < point[0]) {
				right = point[0];
			}
		}
		minmax[0] = left;
		minmax[1] = right;
		return true;
	}	
	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) 
	{
		double bottom, top;
		double[2] leftright;
		get_leftright(leftright, t);
		bool result = false;
		foreach (point; gate.data.points) {
			if ((point[0] >= lr[0] && point[0] <= lr[1]) ||
				(t[0].min >= leftright[0] && t[0].min <= leftright[1]) ||
				(t[0].max >= leftright[0] && t[0].max <= leftright[1])) 
			{
				if (bottom is double.init || bottom >= point[1]) {
					bottom = point[1];
				}
				if (top is double.init || top <= point[1]) {
					top = point[1];
				}
				result = true;
			}
		}
		if (result) {
			bt[0] = bottom;
			bt[1] = top;
		}
		return result;
	}


	override BoundingBox interactMouseMotion(double x_world, double y_world, in Transform[3] t) {
		long highlighted = -1;
		double x_canvas = t[0].world2canvas(t[0].log(x_world));
		double y_canvas = t[1].world2canvas(t[1].log(y_world));

		double DISTANCE = 10;
		import std.math;

		double xmin,xmax,ymin,ymax;

		double min_distance;

		for (int i = 0; i < gate.data.points.length; ++i) {
			int iplus1 = i+1;
			if (iplus1 == gate.data.points.length) iplus1 = 0;
			double x1 = t[0].world2canvas(t[0].log(gate.data.points[i][0]));
			double y1 = t[1].world2canvas(t[1].log(gate.data.points[i][1]));
			double x2 = t[0].world2canvas(t[0].log(gate.data.points[iplus1][0]));
			double y2 = t[1].world2canvas(t[1].log(gate.data.points[iplus1][1]));

			if (xmin is double.init || xmin > t[0].log(gate.data.points[i][0])) xmin = t[0].log(gate.data.points[i][0]);
			if (ymin is double.init || ymin > t[1].log(gate.data.points[i][1])) ymin = t[1].log(gate.data.points[i][1]);
			if (xmax is double.init || xmax < t[0].log(gate.data.points[i][0])) xmax = t[0].log(gate.data.points[i][0]);
			if (ymax is double.init || ymax < t[1].log(gate.data.points[i][1])) ymax = t[1].log(gate.data.points[i][1]);

			BoundingBox bb1,bb2,bbline;

			double x_line, y_line;
			double distance;
			if (closest_point_on_line(x_line, y_line, x1,y1, x2,y2, x_canvas,y_canvas)) {
				double dx = x_line - x_canvas;
				double dy = y_line - y_canvas;
				distance = sqrt(dx*dx+dy*dy);
				if (distance < DISTANCE) {
					// indices are: [0... length-1] => points ; [length...2*length-1] => lines ; [2*length] => all
					highlighted = gate.data.points.length+i;
					bbline = BoundingBox(t[0].canvas2world(x1),t[1].canvas2world(y1),t[0].canvas2world(x2),t[1].canvas2world(y2), distance, this, highlighted);
				}
			}

			import std.algorithm;
			if (abs(x1-x_canvas) < DISTANCE && abs(y1-y_canvas) < DISTANCE) {
				highlighted = i;
				bb1 = BoundingBox(t[0].canvas2world(x1-DISTANCE),t[1].canvas2world(y1+DISTANCE), t[0].canvas2world(x1+DISTANCE),t[1].canvas2world(y1-DISTANCE), min(t[0].canvas2world_delta(DISTANCE),t[1].canvas2world_delta(DISTANCE)), this, highlighted);
			}

			if (abs(x2-x_canvas) < DISTANCE && abs(y2-y_canvas) < DISTANCE) {
				highlighted = iplus1;
				bb1 = BoundingBox(t[0].canvas2world(x2-DISTANCE),t[1].canvas2world(y2+DISTANCE), t[0].canvas2world(x2+DISTANCE),t[1].canvas2world(y2-DISTANCE), min(t[0].canvas2world_delta(DISTANCE),t[1].canvas2world_delta(DISTANCE)), this, highlighted);
			}

			if (bb2.valid && bb2.valid) {
				if (bb1.distance < bb2.distance) return bb1;
				else                             return bb2;
			}
			if (bb1.valid) {
				return bb1;
			}
			if (bb2.valid) {
				return bb2;
			}
			if (bbline.valid) {
				return bbline;
			}
		}

		if (gate.inside(x_world,y_world)) {
			import std.algorithm;
			highlighted = 2*gate.data.points.length;
			return BoundingBox(xmin,ymin, xmax,ymax, min(abs(xmax-xmin),abs(ymax-ymin)), this, highlighted);
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

	void add_or_remove_point(long handle) {
		// remove a point 
		if (handle >= 0 && handle < gate.data.points.length) {
			if (gate.data.points.length <= 3) return; // polygon cannot have less than 3 points!
			long previous_length = gate.data.points.length;

			import std.algorithm, std.array;
			double[2][] new_points;
			double[2][] new_deltas;
			foreach(idx, point; gate.data.points) {
				if (idx != handle) {
					new_points ~= point;
					new_deltas ~= gate.deltas[idx];
				}
			}
			gate.data.points = new_points;
			gate.deltas      = new_deltas;
			highlight_handle = gate.data.points.length + handle - 1;
			if (highlight_handle == 2*gate.data.points.length) highlight_handle = gate.data.points.length;
			if (highlight_handle < gate.data.points.length) highlight_handle = 2*gate.data.points.length-1;

			// if removed point was selected
			if (selected.canFind(handle)) {
				auto idx = selected.countUntil(handle);
				selected.remove!(SwapStrategy.unstable)(idx);
				selected = selected[0..$-1];
			}
			// repair the selection
			foreach(ref sel; selected) {
				if (sel >= 0 && sel < previous_length) { // this was a selected point
					if (sel > handle) sel -= 1;
				}
			}
			// remove potential duplicates in selected
			selected = selected.sort.uniq.array;
			return;
		}
		// insert a point on the middle of the highlighted line segment
		if (handle >= gate.data.points.length && handle < 2*gate.data.points.length) {
			long previous_length = gate.data.points.length;
			long insert_after_idx = handle - gate.data.points.length;
			long insert_before_idx = insert_after_idx+1;
			if (insert_before_idx == gate.data.points.length) insert_before_idx = 0;
			double[2]   additional_point = 0.5*(gate.data.points[insert_after_idx][]+gate.data.points[insert_before_idx][]);
			double[2][] new_points;
			double[2][] new_deltas;
			foreach(idx, point; gate.data.points) {
				new_points ~= point;
				new_deltas ~= gate.deltas[idx];
				if (idx == insert_after_idx) {
					new_points ~= additional_point;
					new_deltas ~= [0,0];
				}
			}
			gate.data.points = new_points;
			gate.deltas      = new_deltas;
			highlight_handle = insert_after_idx + 1; // then new point is highlighted;

			bool point_before_was_selected = false;
			bool point_after_was_selected = false;
			// repair the selection
			foreach(ref sel; selected) {
				if (sel == insert_before_idx) point_before_was_selected = true;
				if (sel == insert_after_idx) point_after_was_selected = true;
				if (sel >= 0 && sel < previous_length) { // this was a selected point
					if (sel > insert_after_idx) sel += 1;
				}
			}
			if (point_before_was_selected && point_after_was_selected) selected ~= insert_after_idx+1;
			return;
		}
	}

	// change selection of element with handle
	// if add_or_remove is true, the element is added/removed from selected set depending if it is already in the set or not
	// if handle is -1 the selected set is emptied.
	override void select(long handle, bool add_or_remove = false, bool action = false) {
		import std.algorithm;
		
		if (handle == -1) {
			selected.length = 0;
			return;
		} 

		if (action) {
			add_or_remove_point(handle);
			return;
		}

		if (add_or_remove) {
			if (handle >= 0 && handle < gate.data.points.length) {
				if (selected.canFind(handle)) {
					if (selected.length == 1) {
						selected.length = 0;
					} else {
						auto idx = selected.countUntil(handle);
						selected.remove!(SwapStrategy.unstable)(idx);
						selected = selected[0..$-1];
					}
				} else {
					if (!selected.canFind(handle)) selected ~= handle;				
				}
			}
			if (handle >= gate.data.points.length && handle < 2*gate.data.points.length) { // line 
				long i = handle - gate.data.points.length;
				long iplus1 = i+1;
				if (iplus1 == gate.data.points.length) iplus1 = 0;
				if (selected.canFind(i) && selected.canFind(iplus1)) { // remove both
					if (selected.length == 2) {
						selected.length = 0;
					} else {
						auto idx = selected.countUntil(i);
						selected.remove!(SwapStrategy.unstable)(idx);
						selected = selected[0..$-1];
						idx = selected.countUntil(iplus1);
						selected.remove!(SwapStrategy.unstable)(idx);
						selected = selected[0..$-1];
					}
				} else {
					if (!selected.canFind(i)) selected ~= i;
					if (!selected.canFind(iplus1)) selected ~= iplus1;
				}
			}
			if (handle == 2*gate.data.points.length) { // all points
				bool select_all = false;
				for (long i = 0; i < gate.data.points.length; ++i) {
					if (!selected.canFind(i)) {
						selected.length = 0;
						for (long j = 0; j < gate.data.points.length; ++j) {
							selected ~= j;
						}
						select_all = true;
						break;
					}
				}
				if (!select_all) {
					selected.length = 0;
				}
			}
		} else {
			if (handle >= 0 && handle < gate.data.points.length) {
				selected.length = 0;
				if (!selected.canFind(handle)) selected ~= handle;
			}
			if (handle >= gate.data.points.length && handle < 2*gate.data.points.length) {
				long i = handle - gate.data.points.length;
				long iplus1 = i+1;
				if (iplus1 == gate.data.points.length) iplus1 = 0;
				selected.length = 0;
				if (!selected.canFind(i))      selected ~= i;
				if (!selected.canFind(iplus1)) selected ~= iplus1;
			}
			if (handle == 2*gate.data.points.length) { // all points
				selected.length = 0;
				for (long i = 0 ; i < gate.data.points.length; ++i) {
					selected ~= i;
				}
			}
		}

	}
	
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
		import std.algorithm;
		if (x2 < x1) swap(x1,x2);
		if (y2 < y1) swap(y1,y2);
		if (!add && !remove) {
			selected.length = 0;
		}
		for (long i = 0; i < gate.data.points.length; ++i) {
			double x_canvas = t[0].world2canvas(t[0].log(gate.data.points[i][0]));
			double y_canvas = t[1].world2canvas(t[1].log(gate.data.points[i][1]));
			if (x1 <= x_canvas && x2 >= x_canvas && y1 <= y_canvas && y2 >= y_canvas) {
				if (remove) {
					if (selected.canFind(i)) {
						if (selected.length == 1) selected.length = 0;
						else {
							long idx = selected.countUntil(i);
							selected.remove!(SwapStrategy.unstable)(idx);
							selected = selected[0..$-1];
						}
					}
				} else {
					selected ~= i;
				}
			}
		}

	}

	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
		import std.algorithm;
		double deltax = t[0].canvas2world_delta(x_canvas - x_canvas_start);
		double deltay = t[1].canvas2world_delta(y_canvas - y_canvas_start);
		//for (long i = 0 ; i < selected.length; ++i) {
		for (long i = 0 ; i < gate.data.points.length; ++i) {
			bool needs_to_be_dragged = false;
			if (highlight_handle == 2*gate.data.points.length) needs_to_be_dragged = true; // entire polygon is highlighted
			if (highlight_handle == i || selected.canFind(i)) needs_to_be_dragged = true;  // single point highlighted or selected
			long iminus1 = (i==0)?(gate.data.points.length-1):(i-1);
			if (highlight_handle == gate.data.points.length+iminus1 || highlight_handle == gate.data.points.length+i) needs_to_be_dragged = true; // line highlighted
			if (needs_to_be_dragged) {
				if (!t[0].logscale && !t[1].logscale) {
					if (end) {
						gate.data.points[i][0] += deltax;
						gate.data.points[i][1] += deltay;
						gate.deltas[i][0] = 0;
						gate.deltas[i][1] = 0;
					} else {
						gate.deltas[i][0] = deltax;
						gate.deltas[i][1] = deltay;
					}
				}

			}				
		}

	}

	override void draw(BackendInterface d, in Transform[3] t) const  
	{
		import std.algorithm;

		import std.stdio;
		//writeln("polygate draw ", gate.data.points);

		// determine the center point (mean value) of all points
		double xsum = 0.0;
		double ysum = 0.0;
		for (int i = 0; i < gate.data.points.length; ++i) {
			double x1 = t[0].world2canvas(t[0].log(gate.deltas[i][0] + gate.data.points[i][0]));
			double y1 = t[1].world2canvas(t[1].log(gate.deltas[i][1] + gate.data.points[i][1]));
			xsum += x1;
			ysum += y1;
		}
		double xcenter = xsum / gate.data.points.length;
		double ycenter = ysum / gate.data.points.length;
		double Rmax = 0;


		for (int i = 0; i < gate.data.points.length; ++i) {
			int iplus1 = i+1;
			if (iplus1 == gate.data.points.length) iplus1 = 0;
			double x1 = t[0].world2canvas(t[0].log(gate.deltas[i][0]      + gate.data.points[i][0]));
			double y1 = t[1].world2canvas(t[1].log(gate.deltas[i][1]      + gate.data.points[i][1]));
			double x2 = t[0].world2canvas(t[0].log(gate.deltas[iplus1][0] + gate.data.points[iplus1][0]));
			double y2 = t[1].world2canvas(t[1].log(gate.deltas[iplus1][1] + gate.data.points[iplus1][1]));

			// maximum radius (measured from center point)
			import std.math;
			double dx = xcenter - x1;
			double dy = ycenter - y1;
			double R = sqrt(dx*dx + dy*dy);
			if (Rmax < R) {
				Rmax = R;
			}

			//writeln("point ", i, " ", x1, " ", y1, " ", x2, " ", y2);
			int POINTSIZE=3;
			import std.algorithm;
			if (highlight_handle == i /*|| highlight_handle == gate.data.points.length*2*/) POINTSIZE = 6;
			d.set_gate_color();
			if (selected.canFind(i)) d.set_color(1,0,0);
			d.rectangle(x1-POINTSIZE,y1-POINTSIZE, x1+POINTSIZE,y1+POINTSIZE);
			d.fill();

			if (highlight_handle == i+gate.data.points.length || highlight_handle == gate.data.points.length*2) d.set_line_width(4);
			else                                                                                                d.set_line_width(2);
			d.set_gate_color();
			if (selected.canFind(i) && selected.canFind(iplus1)) d.set_color(1,0,0);
			d.line(x1,y1,x2,y2);
			d.stroke();
		}

		//// draw outer circle
		//Rmax = min(Rmax,30);
		//int Npoints = 32;
		//double x0 = xcenter + Rmax;
		//double y0 = ycenter + 0;
		//for (int i = 1 ; i <= Npoints; ++i) {
		//	d.set_line_width(2);
		//	d.set_color(0.8,0.8,1);
		//	import std.math;
		//	double x1 = xcenter + Rmax*cos(2.0*PI*i/Npoints);
		//	double y1 = ycenter - Rmax*sin(2.0*PI*i/Npoints);
		//	d.line(x0,y0, x1,y1);
		//	d.stroke();
		//	x0 = x1;
		//	y0 = y1;
		//}

	}

}
