module interactive_demo;


@safe:

import item;
import std.json;
import serializeJSON;
import graphics;

class PointsFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Points(json);
	}
}
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
		deltas = data.points.dup;
		foreach(ref d; deltas) {
			d[0] = 0.0;
			d[1] = 0.0;
		}
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
			deltas = data.points.dup;
			foreach(ref d; deltas) {
				d[0] = 0.0;
				d[1] = 0.0;
			}
		} catch(Exception e) {
			writeln("XXX Points.this(ref JSONValue json)", e.msg);
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
		return new PointsVisualizer(item_version, data.points, deltas);
	}

private:
	Data data;
	ulong item_version;
	double[2][] deltas; // not part of data, but part of interactive appearance
}

import interactive;

class PointsVisualizer : Visualizer,  Interactive
{
public:
	this(ulong itemversion, double[2][] points, double[2][] deltas){
		super(itemversion, 2);
		this.points = points; // don't copy the data, work directly with item data
		this.deltas = deltas; 
	}
	import graphics, transform;
	long highlighted_point_index = -1;

	long[] selected_points;

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

	override BoundingBox interactMouseMotion(double x, double y, in Transform[3] t) {
		import std.stdio;
		//writeln("interactMouseMotion called");
		bool is_close(long d, double world1, double world2, double max_canvas_distance) {
			double canvas1 = logprocess(world1,t[d]);
			double canvas2 = logprocess(world2,t[d]);
			double distance = canvas2-canvas1;
			if (distance is double.init) return false;
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
			//writeln("ResetHighlightHandle ", handle);
			highlighted_point_index = handle;
			return true; // highlight changed -> need redraw (which is signaled to the caller by returning true)
		}
		return false;
	}

	// change selection of element with handle
	// if add_or_remove is true, the element is added/removed from selected set depending if it is already in the set or not
	// if handle is -1 the selected set is emptied.
	override void select(long handle, bool add_or_remove) {
		import std.algorithm;
		import std.stdio;
		writeln("select ", handle, " ", add_or_remove);
		if (handle == -1) {
			selected_points.length = 0;
		} else if (handle >= 0 && handle <= points.length) {
			if (add_or_remove) {
				if (selected_points.canFind(handle)) { 
					// remove an existing point
					auto found = selected_points.find(handle);
					swap(found[0],found[$-1]);
					selected_points.length = selected_points.length-1;
				} else {
					// add a new point
					selected_points ~= handle;
				}
			} else {
				selected_points.length = 0;
				selected_points ~= handle;

			}
		}
	}
	
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
		import std.algorithm;
		BoundingBox sb = selection_box(x1,y1, x2,y2, t);
		if (!sb.valid) return;
		if ((!add && !remove) || (add  &&  remove)) { // if neither add nor remove are given, delete the point selection and only select the boxed elements
			selected_points.length = 0;
			add = true;
		}
		foreach(i, p; points) {
			if (sb.contains(p[0],p[1])) {
				if (add && !selected_points.canFind(i)) {
					selected_points ~= i;
				}
				if (!add && selected_points.canFind(i)) {
					auto found = selected_points.find(i);
					swap(found[0],found[$-1]);
					selected_points.length = selected_points.length-1;
				}
			}
		}
	}

	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
		double[2] start = [x_canvas_start, y_canvas_start];
		double[2] current = [x_canvas, y_canvas];
		if (handle >= -1 && handle <= cast(long)points.length) {
			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					if (handle >= 0) deltas[handle][dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag the active point ...
					foreach(s;selected_points) {
						deltas[s][dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // ... and all selected points
					}
				}
				if (end) {
					if (handle >= 0) points[handle][dim] += deltas[handle][dim];
					if (handle >= 0) deltas[handle][dim] = 0;
					foreach(s;selected_points) {
						points[s][dim] += deltas[s][dim];
						deltas[s][dim] = 0;
					}
				}
			}
		}
	}

	override void draw(BackendInterface d, in Transform[3] t) const  
	{
		for (int color = 0; color < 2; ++color)
		foreach(i, p; points) {
			double[2] pc; // point_on_canvas
			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					pc[dim] = t[dim].world2canvas(p[dim] + deltas[i][dim]);
				}
			}
			if (pc[0] is double.init || pc[1] is double.init) continue;
			double w = 4, h = 4;
			if (color == 0) {
				w += 4;
				h += 4;
				d.set_color(0.9,0.9,0.9);
			}
			import std.algorithm;
			if (i == highlighted_point_index) {
				w += 4; h += 4;
			}
			if (color == 1) {
				d.set_color(0,0,1);
				if (selected_points.canFind(i)) {
					d.set_color(1,0,0);
				}
			}
			d.rectangle(pc[0]-w/2,pc[1]-h/2,   pc[0]+w/2,pc[1]+h/2);
			d.fill;
		}
	}

private:
	double[2][] points;
	double[2][] deltas;
}





































import item;
import std.json;
import serializeJSON;
import graphics;

class EllipseFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Ellipse(json);
	}
}
class Ellipse : Visual, Item
{
public:
	struct Data {
		@SERIALIZE double[2][] cap; // center, aphel, perihel
	}
	this() {
		data.cap = [[0,0],[1,0],[0,1]];
		deltas   = [[0,0],[0,0],[0,0]];
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data   = deserialize!Data(json);
			deltas = [[0,0],[0,0],[0,0]];
		} catch(Exception e) {
			writeln("ERROR in Ellipse.this(ref JSONValue json)", e.msg);
		} 
	}
	override JSONValue toJSON() { return serialize(data); }
	override string get_type()  {
		return "interactive_demo.Ellipse";
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
		return new EllipseVisualizer(item_version, data.cap, deltas);
	}

private:
	Data data;
	ulong item_version;
	double[2][] deltas; // not part of data, but part of interactive appearance
}




import interactive;

class EllipseVisualizer : Visualizer,  Interactive
{
public:
	this(ulong itemversion, double[2][] points, double[2][] deltas){
		super(itemversion, 2);
		this.points = points; // don't copy the data, work directly with item data
		this.deltas = deltas; 
		import std.stdio;
		writeln("EllipseVisualizer created: ", points, " " , deltas);
	}
	import graphics, transform;
	long highlighted_point_index = -1;

	long[] selected_points;

	override BoundingBox interactMouseMotion(double x, double y, in Transform[3] t) {
		import std.stdio;
		//writeln("interactMouseMotion called");
		bool is_close(long d, double world1, double world2, double max_canvas_distance) {
			double canvas1 = t[d].world2canvas(world1);
			double canvas2 = t[d].world2canvas(world2);
			double distance = canvas2-canvas1;
			if (distance is double.init) return false;
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
			highlighted_point_index = handle;
			return true; // highlight changed -> need redraw (which is signaled to the caller by returning true)
		}
		return false;
	}

	// change selection of element with handle
	// if add_or_remove is true, the element is added/removed from selected set depending if it is already in the set or not
	// if handle is -1 the selected set is emptied.
	override void select(long handle, bool add_or_remove) {

	}
	
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {

	}

	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
		double[2] start = [x_canvas_start, y_canvas_start];
		double[2] current = [x_canvas, y_canvas];
		if (handle >= 0 && handle <= cast(long)points.length) {
			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					if (handle > 0) deltas[handle][dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag the active point ...
					else foreach(ref d; deltas) d[dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag all points when the center (index == 0) was chosen
				}
				if (end) {
					if (handle > 0) points[handle][dim] += deltas[handle][dim];
					foreach(i, ref d; deltas) {
						if (handle == 0) points[i][dim] += d[dim];
						d[dim] = 0;
					}
				}
			}
		}
	}
	// This version of "drag" function assures that the two "aphel" and "perihel" points are always 90 degrees apart.
	// But this is not good because fairy can have x- and y-axis separately scaled so that angles are not conserved. 
	// That results in a very unexpected user experience.
	//override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
	//	double[2] start = [x_canvas_start, y_canvas_start];
	//	double[2] current = [x_canvas, y_canvas];
	//	if (handle >= 0 && handle <= cast(long)points.length) {
	//		if (handle > 0) {
	//			for(int dim = 0; dim < 2; ++dim) deltas[handle][dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag the active point ...
	//			import std.math;
	//			//double[2] r0 = points[handle][] - points[0][];
	//			//double alpha0 = atan2(r0[1],r0[0]);
	//			double[2] r1 = points[handle][] + deltas[handle][] - points[0][];
	//			double alpha1 = atan2(r1[1],r1[0]);
	//			//double d_alpha = alpha0 - alpha1;

	//			long other = (handle==1)?2:1;
	//			double[2] l1 = points[other];
	//			l1[] -= points[0][];
	//			double beta0 = atan2(l1[1],l1[0]);
	//			double beta1 = alpha1+PI/2;
	//			double delta = (handle==1)?(beta0-beta1):(beta0-beta1+PI);
	//			double[2] l2 = [cos(delta)*l1[0] + sin(delta)*l1[1],
	//			               -sin(delta)*l1[0] + cos(delta)*l1[1]];
	//			deltas[other] = l2[]-l1[];
	//		}
	//		else {
	//			for(int dim = 0; dim < 2; ++dim) foreach(ref d; deltas) d[dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag all points when the center (index == 0) was chosen
	//		}
	//		if (end) {
	//			for(int dim = 0; dim < 2; ++dim) {
	//				if (handle > 0) {
	//					points[1][dim] += deltas[1][dim];
	//					points[2][dim] += deltas[2][dim];
	//				}
	//				foreach(i, ref d; deltas) {
	//					if (handle == 0) points[i][dim] += d[dim];
	//					d[dim] = 0;
	//				}
	//			}
	//		}
	//	}
	//}
	override void draw(BackendInterface d, in Transform[3] t) const  
	{
		assert(points.length == 3 && deltas.length == 3);

		// draw the circumfence of the ellipse
		import std.math;
		double[2][3] ps;
		foreach(i, ref p; points) for(int dim = 0; dim < 2; ++dim) ps[i][dim] = p[dim]+deltas[i][dim];
		double[2] r1 = [ps[1][0]-ps[0][0],  ps[1][1]-ps[0][1]];
		double[2] r2 = [ps[2][0]-ps[0][0],  ps[2][1]-ps[0][1]];

		double alpha = atan2(r1[1],r1[0]);
		double R1 = sqrt(r1[0]*r1[0] + r1[1]*r1[1]);
		double R2 = sqrt(r2[0]*r2[0] + r2[1]*r2[1]);

		const int N = 100;
		for(int color = 0; color < 2; ++color)
		for (int i = 0; i < N; ++i) {
			double phi = i*2*PI/N;
			double cx1 = cos(phi);
			double cy1 = sin(phi);
			double cx2 = cos(phi+2*PI/N);
			double cy2 = sin(phi+2*PI/N);

			double x1 = t[0].world2canvas(ps[0][0] + r1[0]*cx1 + r2[0]*cy1);
			double y1 = t[1].world2canvas(ps[0][1] + r1[1]*cx1 + r2[1]*cy1);
			double x2 = t[0].world2canvas(ps[0][0] + r1[0]*cx2 + r2[0]*cy2);
			double y2 = t[1].world2canvas(ps[0][1] + r1[1]*cx2 + r2[1]*cy2);

			if (color == 0)	{
				d.set_line_width(6);
				d.set_color(0.9,0.9,0.9); 
			}
			if (color == 1)	{
				d.set_line_width(2);
				d.set_color(0,0,1);
			}
			d.line(x1,y1,x2,y2);
			d.stroke();
		}

		// draw the control points
		for (int color = 0; color < 2; ++color)
		foreach(i, p; points) {
			//import std.stdio;
			//writeln("draw point ", i , ": ", p);
			double[2] pc; // point_on_canvas
			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					pc[dim] = t[dim].world2canvas(p[dim] + deltas[i][dim]);
				}
			}
			if (pc[0] is double.init || pc[1] is double.init) continue;
			double w = 4, h = 4;
			if (color == 0) {
				w += 4;
				h += 4;
				d.set_color(0.9,0.9,0.9);
			}
			import std.algorithm;
			if (i == highlighted_point_index) {
				w += 4; h += 4;
			}
			if (color == 1) {
				d.set_color(0,0,1);
				if (selected_points.canFind(i)) {
					d.set_color(1,0,0);
				}
			}
			d.rectangle(pc[0]-w/2,pc[1]-h/2,   pc[0]+w/2,pc[1]+h/2);
			d.fill;
		}


	}

private:
	double[2][] points;
	double[2][] deltas;
}






























/+



import item;
import std.json;
import serializeJSON;
import graphics;

class Window1DFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Window1D(json);
	}
}
class Window1D : Visual, Item
{
public:
	struct Data {
		@SERIALIZE double[2] edges; // min and max
		@SERIALIZE int       dim; // 0 = x; 1 = y;
	}
	this(double a, double b) {
		data.edges = [a,b];
		deltas     = [0,0];
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data   = deserialize!Data(json);
			deltas = [0,0];
		} catch(Exception e) {
			writeln("ERROR in Window1D.this(ref JSONValue json)", e.msg);
		} 
	}
	override JSONValue toJSON() { return serialize(data); }
	override string get_type()  {
		return "interactive_demo.Window1D";
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
		return new Window1DVisualizer(item_version, data.edges, deltas);
	}

private:
	Data data;
	ulong item_version;
	double[2] deltas; // not part of data, but part of interactive appearance
}




import interactive;

class Window1DVisualizer : Visualizer,  Interactive
{
public:
	this(ulong itemversion, double[2][] points, double[2][] deltas){
		super(itemversion, 2);
		this.points = points; // don't copy the data, work directly with item data
		this.deltas = deltas; 
		import std.stdio;
		writeln("Window1DVisualizer created: ", points, " " , deltas);
	}
	import graphics, transform;
	long highlighted_point_index = -1;

	long[] selected_points;

	override BoundingBox interactMouseMotion(double x, double y, in Transform[3] t) {
		import std.stdio;
		//writeln("interactMouseMotion called");
		bool is_close(long d, double world1, double world2, double max_canvas_distance) {
			double canvas1 = t[d].world2canvas(world1);
			double canvas2 = t[d].world2canvas(world2);
			double distance = canvas2-canvas1;
			if (distance is double.init) return false;
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
			highlighted_point_index = handle;
			return true; // highlight changed -> need redraw (which is signaled to the caller by returning true)
		}
		return false;
	}

	// change selection of element with handle
	// if add_or_remove is true, the element is added/removed from selected set depending if it is already in the set or not
	// if handle is -1 the selected set is emptied.
	override void select(long handle, bool add_or_remove) {

	}
	
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {

	}

	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
		double[2] start = [x_canvas_start, y_canvas_start];
		double[2] current = [x_canvas, y_canvas];
		if (handle >= 0 && handle <= cast(long)points.length) {
			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					if (handle > 0) deltas[handle][dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag the active point ...
					else foreach(ref d; deltas) d[dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag all points when the center (index == 0) was chosen
				}
				if (end) {
					if (handle > 0) points[handle][dim] += deltas[handle][dim];
					foreach(i, ref d; deltas) {
						if (handle == 0) points[i][dim] += d[dim];
						d[dim] = 0;
					}
				}
			}
		}
	}
	// This version of "drag" function assures that the two "aphel" and "perihel" points are always 90 degrees apart.
	// But this is not good because fairy can have x- and y-axis separately scaled so that angles are not conserved. 
	// That results in a very unexpected user experience.
	//override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool end = false) {
	//	double[2] start = [x_canvas_start, y_canvas_start];
	//	double[2] current = [x_canvas, y_canvas];
	//	if (handle >= 0 && handle <= cast(long)points.length) {
	//		if (handle > 0) {
	//			for(int dim = 0; dim < 2; ++dim) deltas[handle][dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag the active point ...
	//			import std.math;
	//			//double[2] r0 = points[handle][] - points[0][];
	//			//double alpha0 = atan2(r0[1],r0[0]);
	//			double[2] r1 = points[handle][] + deltas[handle][] - points[0][];
	//			double alpha1 = atan2(r1[1],r1[0]);
	//			//double d_alpha = alpha0 - alpha1;

	//			long other = (handle==1)?2:1;
	//			double[2] l1 = points[other];
	//			l1[] -= points[0][];
	//			double beta0 = atan2(l1[1],l1[0]);
	//			double beta1 = alpha1+PI/2;
	//			double delta = (handle==1)?(beta0-beta1):(beta0-beta1+PI);
	//			double[2] l2 = [cos(delta)*l1[0] + sin(delta)*l1[1],
	//			               -sin(delta)*l1[0] + cos(delta)*l1[1]];
	//			deltas[other] = l2[]-l1[];
	//		}
	//		else {
	//			for(int dim = 0; dim < 2; ++dim) foreach(ref d; deltas) d[dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); // drag all points when the center (index == 0) was chosen
	//		}
	//		if (end) {
	//			for(int dim = 0; dim < 2; ++dim) {
	//				if (handle > 0) {
	//					points[1][dim] += deltas[1][dim];
	//					points[2][dim] += deltas[2][dim];
	//				}
	//				foreach(i, ref d; deltas) {
	//					if (handle == 0) points[i][dim] += d[dim];
	//					d[dim] = 0;
	//				}
	//			}
	//		}
	//	}
	//}
	override void draw(BackendInterface d, in Transform[3] t) const  
	{
		assert(points.length == 3 && deltas.length == 3);
		foreach(i, p; points) {
			//import std.stdio;
			//writeln("draw point ", i , ": ", p);
			double[2] pc; // point_on_canvas
			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					pc[dim] = t[dim].world2canvas(p[dim] + deltas[i][dim]);
				}
			}
			if (pc[0] is double.init || pc[1] is double.init) continue;
			double w = 4, h = 4;
			import std.algorithm;
			if (i == highlighted_point_index) {
				w = 10; h = 10;
			}
			d.set_color(0,0,1);
			if (selected_points.canFind(i)) {
				d.set_color(1,0,0);
			}
			d.rectangle(pc[0]-w/2,pc[1]-h/2,   pc[0]+w/2,pc[1]+h/2);
			d.fill;
		}

		// draw the circumfence of the ellipse
		import std.math;
		double[2][3] ps;
		foreach(i, ref p; points) for(int dim = 0; dim < 2; ++dim) ps[i][dim] = p[dim]+deltas[i][dim];
		double[2] r1 = [ps[1][0]-ps[0][0],  ps[1][1]-ps[0][1]];
		double[2] r2 = [ps[2][0]-ps[0][0],  ps[2][1]-ps[0][1]];

		double alpha = atan2(r1[1],r1[0]);
		double R1 = sqrt(r1[0]*r1[0] + r1[1]*r1[1]);
		double R2 = sqrt(r2[0]*r2[0] + r2[1]*r2[1]);

		const int N = 100;
		for (int i = 0; i < N; ++i) {
			double phi = i*2*PI/N;
			double cx1 = cos(phi);
			double cy1 = sin(phi);
			double cx2 = cos(phi+2*PI/N);
			double cy2 = sin(phi+2*PI/N);

			double x1 = t[0].world2canvas(ps[0][0] + r1[0]*cx1 + r2[0]*cy1);
			double y1 = t[1].world2canvas(ps[0][1] + r1[1]*cx1 + r2[1]*cy1);
			double x2 = t[0].world2canvas(ps[0][0] + r1[0]*cx2 + r2[0]*cy2);
			double y2 = t[1].world2canvas(ps[0][1] + r1[1]*cx2 + r2[1]*cy2);


			d.set_color(0,0,1);
			d.set_line_width(3);
			d.line(x1,y1,x2,y2);
			d.stroke();
		}

	}

private:
	double[2][] points;
	double[2][] deltas;
}
+/
