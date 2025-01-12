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
private:
	struct Data{
		@SERIALIZE double left;
		@SERIALIZE double right;
	}	
	Data data;
	ulong item_version = 0;
public:
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
public:
	this(Gate1D g, ulong itemversion) {
		ulong dim = 1;
		super(itemversion, dim);
		gate = g;
	}
	override void draw(BackendInterface d, in Transform[3] t) const	{
		import std.algorithm;
		double left = gate.data.left;
		double right = gate.data.right;
		if (left > right) swap(left, right);
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
		d.set_line_width(3);
		d.set_color(0,0,1);
		d.vertical_line(x1, bottom, top);
		d.stroke();
		d.vertical_line(x2, bottom, top);
		d.stroke();
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
	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {}
	override BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t) { return BoundingBox();}
	override bool setHighlightHandle(long handle) { return false; }
	override void select(long handle, bool add_or_remove = false) {}
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {}

}