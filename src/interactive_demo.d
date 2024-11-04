module interactive_demo;


@safe:

import item;
import std.json;
import serializeJSON;



class PointsFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Points(json);
	}
}
import graphics;
class Points : Visual, Item
{
public:
	struct Data {
		@SERIALIZE double[2][] points;
	}
	this(uint n) {
		data.points.length = n;
		foreach(ref d; data.points) {
			import std.random;
			d[0] = uniform(0,10);
			d[1] = uniform(0,10);
		}
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
		} catch(Exception e) {
			writeln("XXX ", e.msg);
		} 
	}
	override JSONValue toJSON() { return serialize(data); }
	override string get_type()  {
		return "interactive_demo.Points";
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
		return new PointsVisualizer(item_version, data.points);
	}

private:
	Data data;
	ulong item_version;
}

import interactive;

class PointsVisualizer : Visualizer,  Interactive
{
public:
	this(ulong itemversion, double[2][] points){
		super(itemversion, 2);
		this.points = points;
	}
	import graphics, transform;
	long highlighted_point_index = -1;

	override BoundingBox interactMouseMotion(double x, double y, in Transform[3] t) {
		import std.stdio;
		//writeln("interactMouseMotion called");
		bool is_close(long d, double world1, double world2, double max_canvas_distance) {
			double canvas1 = t[d].world2canvas(world1);
			double canvas2 = t[d].world2canvas(world2);
			double distance = canvas2-canvas1;
			if (distance < 0) distance = -distance;
			if (distance < max_canvas_distance) return true;
			return false;
		}
		double distance(double px, double py) {
			auto dx = px-x;
			auto dy = py-y;
			return dx*dx + dy*dy;
		}
		const double WIDTH = 10;
		const double HEIGHT = 10;
		double min_distance = double.max;
		long point_index = -1;
		// among all points that have the mouspe pointer in their proximity
		// select the one that is closest to the mouse pointer
		foreach(i, p; points) {
			if (is_close(0,p[0],x,WIDTH) && is_close(1,p[1],y,HEIGHT)) {
				//writeln("is close ", i);
				double d = distance(p[0],p[1]);
				if (d < min_distance) {
					min_distance = d;
					point_index = i;
				}
			}
		}
		if (point_index >= 0) { // we have a candidate that may be highlited
			// make 10 pixel wide bounding box for points
			double w = t[0].canvas2world_delta(WIDTH);
			double h = t[1].canvas2world_delta(HEIGHT);
			double px = points[point_index][0];
			double py = points[point_index][1];
			import std.math;
			return BoundingBox(px-w/2,py-h/2, px+w/2,py+h/2, sqrt(min_distance), this, point_index);
		}
		return BoundingBox();
	}
	override bool setHighlightHandle(long handle) {
		import std.stdio;
		if (highlighted_point_index != handle) {
			writeln("ResetHighlightHandle ", handle);
			highlighted_point_index = handle;
			return true; // highlight changed -> need redraw (which is signaled to the caller by returning true)
		}
		return false;
	}

	override void draw(BackendInterface d, in Transform[3] t) const  
	{
		foreach(i, p; points) {
			double x = t[0].world2canvas(p[0]);
			double y = t[1].world2canvas(p[1]);
			double w = 4, h = 4;
			import std.algorithm;
			if (i == highlighted_point_index) {
				w = 10; h = 10;
			}
			d.rectangle(x-w/2,y-h/2,   x+w/2,y+h/2);
		}
		d.set_color(0,0,1);
		d.fill;
	}

private:
	double[2][] points;
}