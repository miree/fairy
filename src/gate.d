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
		@SERIALIZE double left;
		@SERIALIZE double right;
	}	
	Data data;
	double left_delta  = 0; // relevant for user interaction 
	double right_delta = 0; // relevant for user interaction

	ulong item_version = 0;

	this(double left, double right) {
		data.left = left;
		data.right = right;
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
	long highlight_handle = -1; // bitmask: bit 0 means left, bit 1 means right
	long selected_handle  = -1; // bitmask: bit 0 means left, bit 1 means right
	                            // left selected:  0x1
	                            // right selected: 0x2
	                            // both selected:  0x3
public:
	this(Gate1D g, ulong itemversion) {
		ulong dim = 1;
		super(itemversion, dim);
		gate = g;

		if (gate.data.left > gate.data.right) {
			import std.algorithm;
			swap(gate.data.left, gate.data.right);
		}
	}
	override void draw(BackendInterface d, in Transform[3] t) const	{
		import std.algorithm;
		double left  = gate.data.left  + gate.left_delta;
		double right = gate.data.right + gate.right_delta;
		//if (left > right) swap(left, right);

		import std.math;
		double x1 = t[0].world2canvas(left);
		double x2 = t[0].world2canvas(right);
		double bottom = t[1].world2canvas(t[1].min);
		double top    = t[1].world2canvas(t[1].max);
		if (t[0].logscale) {
			if (left > 0)  x1 = t[0].world2canvas(log(left)); 
			else           x1 = t[0].world2canvas(t[0].min); 
			if (right > 0) x2 = t[0].world2canvas(log(right)); 
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
	override bool get_leftright(out double[2] leftright, in Transform[3] t)  {
		import std.algorithm, std.math;
		if (gate.data.left > gate.data.right) swap(gate.data.left, gate.data.right);
		leftright[0] = gate.data.left;
		leftright[1] = gate.data.right;
		bool result = false;
		if (t[0].logscale) {
			if (gate.data.right > 0) {
				leftright[1] = log(gate.data.right);
				result = true;
			} 
			if (gate.data.left > 0) {
				leftright[0] = log(gate.data.left);
			}
			else {
				leftright[0] = t[0].min;
			}
		} else {
			result = true;
		}
		return result;
	}	
	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) { return false; }
	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
		if (handle != -1 || selected_handle != -1) {
			double delta = t[0].canvas2world_delta(x_canvas - x_canvas_start);
			if (t[0].logscale) {
				import std.math;
				if (highlight_handle == 3 || highlight_handle == 1 || selected_handle == 3 || selected_handle == 1) {
					gate.left_delta = gate.data.left*exp(delta) - gate.data.left;
				}
				if (highlight_handle == 3 || highlight_handle == 2 || selected_handle == 3 || selected_handle == 2) {
					gate.right_delta = gate.data.right*exp(delta) - gate.data.right;
				}
			} else {
				if (highlight_handle == 3 || highlight_handle == 1 || selected_handle == 3 || selected_handle == 1) {
					gate.left_delta = delta;
				}
				if (highlight_handle == 3 || highlight_handle == 2 || selected_handle == 3 || selected_handle == 2) {
					gate.right_delta = delta;
				}
			}
			if (end) {
				if (highlight_handle == 3 || highlight_handle == 1 || selected_handle == 3 || selected_handle == 1) {
					gate.data.left += gate.left_delta;
				}
				if (highlight_handle == 3 || highlight_handle == 2 || selected_handle == 3 || selected_handle == 2) {
					gate.data.right += gate.right_delta;
				}
				gate.left_delta = 0;
				gate.right_delta = 0;
				if (gate.data.left > gate.data.right) {
					import std.algorithm;
					swap(gate.data.left, gate.data.right);

					     if (highlight_handle == 1) highlight_handle = 2;
					else if (highlight_handle == 2) highlight_handle = 1;
					
					     if (selected_handle == 1) selected_handle = 2;
					else if (selected_handle == 2) selected_handle = 1;
				}
			}
		}
	}
	double logprocess(double x, in Transform t) const {
		import std.math;
		if (t.logscale && x <= 0) {
			return double.init;
		}
		if (t.logscale && x > 0) {
			return t.world2canvas(log(x));
		}
		return t.world2canvas(x);
	}
	override BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t) { 
		//bool is_close(long d, double world1, double world2, double max_canvas_distance) {
		//	double canvas1 = logprocess(world1,t[d]);
		//	double canvas2 = logprocess(world2,t[d]);
		//	double distance = canvas2-canvas1;
		//	if (distance is double.init) return false;
		//	if (distance < 0) distance = -distance;
		//	if (distance < max_canvas_distance) return true;
		//	return false;
		//}

		import std.algorithm, std.math;
		// outer   inner   outer
		//   |   |      |   |
		//   | L |  C   | R |   <== three regions Left,Center,Right
		//   |   |      |   |
		if (t[0].logscale && (gate.data.left < 0 || gate.data.right < 0)) {
			// in this case one part of the gate is guaranteed to be outside the visible canvas
			// we do not support moving the gate under that circumstances 
			return BoundingBox();
		}

		// here we know that both edges of the gate are visible
		double canvas_left = t[0].world2canvas(t[0].log(gate.data.left));
		double canvas_right = t[0].world2canvas(t[0].log(gate.data.right));
		//import std.stdio;
		//writeln(":::: ", gate.data.left, " ", canvas_left, " ", gate.data.right, " ", canvas_right);
		const double min_width = 10; // we give the user at least that many pixels to grab on
		if (canvas_right-canvas_left < min_width) {
			double canvas_midpoint = 0.5*(canvas_left+canvas_right);
			canvas_left = canvas_midpoint-min_width/2;
			canvas_right = canvas_midpoint+min_width/2;
		}
		double canvas_outer_left  = canvas_left -min_width;
		double canvas_outer_right = canvas_right+min_width;
		import std.math;
		double margin = abs((canvas_right-canvas_left)) - 5*min_width;
		if (margin <      0   ) margin = 0;
		if (margin > min_width) margin = min_width;
		canvas_left       += margin/2;
		canvas_outer_left += margin/2; 
		canvas_right       -= margin/2;
		canvas_outer_right -= margin/2; 

		// move back to world coordinates
		double left        = t[0].exp(t[0].canvas2world(canvas_left)); 
		double right       = t[0].exp(t[0].canvas2world(canvas_right)); 
		double outer_left  = t[0].exp(t[0].canvas2world(canvas_outer_left)); 
		double outer_right = t[0].exp(t[0].canvas2world(canvas_outer_right)); 


		//import std.stdio;
		//writeln(":::: ", outer_left, " ", left, " ", right, " ", outer_right, "   ", mouse_world_x);
		if (mouse_world_x > left && mouse_world_x < right)  // Center region
		{
			return BoundingBox(left, t[1].min, right, t[1].max, 
				               right-left,
				               this, 3);
		} 
		else if (mouse_world_x > outer_left && mouse_world_x < left) 
		{
			return BoundingBox(outer_left, t[1].min, left, t[1].max, 
				               outer_left-left,
				               this, 1);			
		}
		else if (mouse_world_x > right && mouse_world_x < outer_right) 
		{
			return BoundingBox(right, t[1].min, outer_right, t[1].max, 
				               outer_right-right,
				               this, 2);			
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
		import std.stdio;
		writeln("handle ", handle, " was selected  (selected_handle=",selected_handle,")  add_or_remove = ", add_or_remove);
		if (add_or_remove) {
			if (selected_handle != -1 && handle != -1) {
				if (selected_handle & handle) {
					writeln("overlap => remove");
					selected_handle &= ~handle;
				}
				else {
					writeln("no overlap => add");
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
		if (t[0].logscale && (gate.data.left < 0 || gate.data.right < 0)) {
			return;
		}
		
		import std.algorithm;
		if (x2 < x1) swap(x1,x2);

		double left_canvas = t[0].world2canvas(t[0].log(gate.data.left));
		double right_canvas = t[0].world2canvas(t[0].log(gate.data.right));

		int pattern = 0;
		
		if (left_canvas > x1 && left_canvas < x2) pattern |= 1;
		if (right_canvas > x1 && right_canvas < x2) pattern |= 2;

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