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
	override void draw(BackendInterface d, in Transform[3] t) const	{}
	override double getValue(double x, double y) { return 0.0; }
	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) { return false; }
	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {}
	override BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t) { return BoundingBox();}
	override bool setHighlightHandle(long handle) { return false; }
	override void select(long handle, bool add_or_remove = false) {}
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {}

}