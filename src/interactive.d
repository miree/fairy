module interactive;
@safe:

interface Interactive {
	import transform;
	BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t);
	// pass a handle so that the interactive element knows that whatever is
	// associated with this handle was selected to be highlighted.
	// returns true if that changes the apperance of the interactive element
	// and a redraw is needed.
	bool setHighlightHandle(long handle);
	// if an interactive element was selected (e.g. in the GUI) this function should be called to tell the 
	// Interactive about it (so that it can draw it differently).
	void select(long handle, bool add_or_remove = false, bool action = false);
	// selection with a box (box points are canvas coordinates), the add flag decide if the points inside the box should be added or removed
	void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove);
	// an interactive element is dragged by calling this function with x and y being in canvas coordinates 
	void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool ctrl = false, bool shift = false, bool end = false);
}


// This represents a potentially selected interactive element.
// Multiple Interactives may return valid potentially selected elements.
// This structure helps to select the best match among all candidates.
// The selection is based on the distance to the mouse pointer
// and on the size of the element.
// The box should be given in world coordinates.
struct BoundingBox {
	double x1,x2,y1,y2;
	double distance;  // the actual distance to the mouse pointer
	Interactive item; // a reference to the item of this BoundingBox
	long handle = -1; // this is context dependent, each Interactive element 
	                  // must put a number here that allows it to identify the 
	                  // element that is associated with this bounding box
	this (double x_1, double y_1, double x_2, double y_2, double d, Interactive i = null, long h = -1) {
		// make sure that x2 >= x1 
		if (x_2 > x_1) { x1 = x_1; x2 = x_2; } 
		else           { x2 = x_1; x1 = x_2; }

		// make sure that y2 >= y1 
		if (y_2 > y_1) { y1 = y_1; y2 = y_2; } 
		else           { y2 = y_1; y1 = y_2; }

		distance = d;
		item = i;
		handle = h;
	}
	bool valid() const { // invalid BoundingBoxes have (handle == -1)
		return x1 !is double.init;
	}
	double area() const {
		return (x2-x1)*(y2-y1);
	}
	bool contains(double x, double y) const {
		if (x <= x1) return false;
		if (x >= x2) return false;
		if (y <= y1) return false;
		if (y >= y2) return false;
		return true;
	}
	bool contains(in BoundingBox b) const {
		// b is contained if two opposite corner points are contained
		if (contains(b.x1,b.y1) && 
			contains(b.x2,b.y2)) return true;
		return false;
	}
	bool opEquals(in BoundingBox b) const {
		// all points identical means equal
		// note that this is not consistent with equality as derived from opCmp
		// (a==b) differs from (!(a<b) && !(b<a)) 
		// if both are invalid they are considered equal
		// if not all elements have to be equal
		return x1     == b.x1 &&
		       x2     == b.x2 && 
		       y1     == b.y1 &&
		       y2     == b.y2 &&
		       handle == b.handle;
	}
	int opCmp(in BoundingBox b) const {
		// (a==b) differs from (!(a<b) && !(b<a))

		// invalid boxes always end up last in sorted ranges
		if (this.valid != b.valid) {
			if (this.valid) return -1;
			return 1;
		}
		if (!this.valid && !b.valid) return 0;

		// see if one box contains the other 
		if (b.contains(this)) return -1;
		if (this.contains(b)) return  1;
		
		// then compare the areas 
		if (this.area < b.area) return -1;
		if (this.area > b.area) return  1;

		// then compare the distances 
		if (this.distance < b.distance) return -1;
		if (this.distance > b.distance) return  1;

		return  0;
	}
}

import transform;
import graphics;

// return a list of all best candidates from all items (keys are itemnames)
auto highlight_candidates(string[] keys, Visualizer[string] container, double x, double y, in Transform[3] t) {
	import std.algorithm, std.array;
	BoundingBox[] bboxes;
	import std.stdio;
	// get the best matching BoundingBox from each interactive item
	keys.map!(key=>key in container).filter!(vis=>vis)
	    .map!(vis=>cast(Interactive)(*vis)).filter!(vis=>vis)
	    .each!((interactive){
			bboxes ~= interactive.interactMouseMotion(x,y,t);
	    });
	return bboxes;
}
auto best_matching_bbox(string[] keys, Visualizer[string] container, double x, double y, in Transform[3] t) {
	import std.algorithm, std.array;
	BoundingBox[] bboxes = highlight_candidates(keys, container, x,y,t);
	auto candidates = bboxes.sort; 
	long handle = -1;
	Interactive best_match = null;
	if (candidates.length > 0) return candidates.front;
	return BoundingBox(); // invalid box		
}

// identify one (or none) iteractive item that has the mouse pointer (x,y) close enough to create a highlight
// return true if any visual change was caused by this function call so that a redraw of the 
// scene needs to be scheduled
bool highlight(string[] keys, Visualizer[string] container, double x, double y, in Transform[3] t) {
	import std.algorithm, std.array;
	bool need_redraw = false;
	auto best_bbox = best_matching_bbox(keys, container, x,y,t);
	keys.map!(key=>key in container).filter!(vis=>vis)
	    .map!(vis=>cast(Interactive)(*vis)).filter!(inta=>inta)
	    .each!((interactive){
	    	if (best_bbox.item !is null && (interactive is best_bbox.item)) {
	    		need_redraw |= interactive.setHighlightHandle(best_bbox.handle);
	    	} else {
	    		need_redraw |= interactive.setHighlightHandle(-1);
	    	}
	    });
	return need_redraw;
}
// remove all highlights from all elelments 
bool un_highlight(string key, Visualizer[string] container) {
	// if mouse is outside of canvas, all interactives need to be set to -1 (no highlight)
	import std.stdio;
	import std.algorithm, std.array;
	bool need_redraw = false;
	auto vis = key in container;
	if (vis) {
		auto ita = cast(Interactive)(*vis);
		if (ita) {
			//writeln("un_highlight");
			need_redraw |= ita.setHighlightHandle(-1);
		}
	}
	return need_redraw;
}
void select_one(BoundingBox select_this_one, string[] keys, Visualizer[string] container, bool action = false) {
	import std.algorithm, std.array;
	keys.map!(key=>key in container).filter!(vis=>vis)
	    .map!(vis=>cast(Interactive)(*vis)).filter!(vis=>vis)
	    .each!((interactive){
	    	if ((interactive is select_this_one.item)) {
	    		select_this_one.item.select(select_this_one.handle, false, action);
	    	} else {
	    		interactive.select(-1);
	    	}
	    });
}
// create a bounding box from 4 canvas coordinates, transform the box into world coordintates
// an truncate the bounding box on the tranform box
BoundingBox selection_box(double x1, double y1, double x2, double y2, in Transform[3] t) {
	import std.algorithm;
	if (x1 > x2) swap(x1,x2);
	if (y2 > y1) swap(y1,y2);

	double world_x1 = t[0].canvas2world(x1);
	double world_y1 = t[1].canvas2world(y1);
	double world_x2 = t[0].canvas2world(x2);
	double world_y2 = t[1].canvas2world(y2);

	if (world_x1 < t[0].min) world_x1 = t[0].min;
	if (world_x2 > t[0].max) world_x2 = t[0].max;
	if (world_x2 < t[0].min) return BoundingBox();
	if (world_x1 > t[0].max) return BoundingBox();

	if (world_y1 < t[1].min) world_y1 = t[1].min;
	if (world_y2 > t[1].max) world_y2 = t[1].max;
	if (world_y2 < t[1].min) return BoundingBox();
	if (world_y1 > t[1].max) return BoundingBox();

	return BoundingBox(world_x1,world_y1, world_x2,world_y2, 0.0);
}


unittest {
	import std.stdio;
	writeln("Test BoundingBox");
	auto bb1 = BoundingBox(2,2,1,1,1.4);
	assert(bb1.x1 == 1);
	assert(bb1.x2 == 2);
	assert(bb1.y1 == 1);
	assert(bb1.y2 == 2);
	assert(bb1 == bb1);
	assert(bb1.valid);

	auto bb2 = BoundingBox(0,0,4,4,1.5);
	assert(bb2.contains(bb1));
	assert(!bb1.contains(bb2));
	assert(bb1.contains(1.5,1.5));
	assert(!bb1.contains(0,1.5));
	assert(!bb1.contains(1.5,0));
	assert(!bb1.contains(0,3));
	assert(!bb1.contains(3,0));
	assert(bb2 == bb2);
	assert(bb2.valid);

	auto bbs = [bb2,bb1];
	import std.algorithm, std.array;
	//bbs.sort.array.writeln();
	assert(bbs.sort.array == [bb1,bb2]);

	auto bbinvalid = BoundingBox();
	assert(!bbinvalid.valid);
	assert(bb1.valid);
	assert(bb2.valid);

}






















@safe:

import item;
import std.json;
import serializeJSON;
import graphics;

class HierarchicalPointsFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new HierarchicalPoints(json);
	}
}
class HierarchicalPoints : Visual, Item
{
public:
	struct Data {
		@SERIALIZE double[2][] points;
		@SERIALIZE    int[2][] links; // links[i][0] indexes the parent, links[i][1] indexes the child
	}
	this(double[2][] ps, int[2][] ls) {
		data.points   = ps.dup;
		data.links    = ls.dup;
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
			writeln("ERROR in HierarchicalPoints.this(ref JSONValue json)", e.msg);
		} 
	}
	override JSONValue toJSON() { 
		return serialize(data); 
	}
	override string get_type()  {
		return "interactive_demo.HierarchicalPoints";
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
		return new HierarchicalPointsVisualizer(item_version, data.points, data.links, deltas);
	}

private:
	Data data;
	ulong item_version;
	double[2][] deltas; // not part of stored data, but part of interactive appearance
}

import interactive;

class HierarchicalPointsVisualizer : Visualizer,  Interactive
{
public:
	this(ulong itemversion, double[2][] points, int[2][] links, double[2][] deltas){
		super(itemversion, 2);
		this.points = points; // don't copy the data, work directly with item data
		this.links  = links;
		this.deltas = deltas; 
		move_indices.length = points.length;
	}
	import graphics, transform;

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
			highlighted_point_index = handle;
			update_move_indices(highlighted_point_index);
			return true; // highlight changed -> need redraw (which is signaled to the caller by returning true)
		}
		return false;
	}

	void update_move_indices(long idx = -1) {
		import std.algorithm;
		//import std.stdio;
		//writeln("update_move_indices: idx = ", idx, " points ", points, "  selected_points ", selected_points, " links ", links);
		move_indices.length = 0;
		if (idx > -1 && idx <= cast(long)points.length)                                             move_indices ~= idx;  // move the one point that is used as handle
		//writeln("move_indices ", move_indices);
		foreach(s ; selected_points) if (s != idx)                                                  move_indices ~= s;    // and all the selected points
		//writeln("move_indices ", move_indices);
		foreach(l ;           links) if (move_indices.canFind(l[0]) && !move_indices.canFind(l[1])) move_indices ~= l[1]; // if the parent l[0] is moved, the child l[1] must be moved as well
		//writeln("move_indices ", move_indices);
	}

	// change selection of element with handle
	// if add_or_remove is true, the element is added/removed from selected set depending if it is already in the set or not
	// if handle is -1 the selected set is emptied.
	override void select(long handle, bool add_or_remove = false, bool action = false) {
		import std.algorithm;
		import std.stdio;
		move_indices.length = 0; // reset the move indices

		//writeln("select ", handle, " ", add_or_remove);
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
		update_move_indices(handle);
	}
	
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
		import std.algorithm;
		move_indices.length = 0; // reset the move indices

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
		update_move_indices();
	}

	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool ctrl = false, bool shift = false, bool end = false) {
		import std.algorithm;
		double[2] start = [x_canvas_start, y_canvas_start];
		double[2] current = [x_canvas, y_canvas];
		if (handle >= -1 && handle <= cast(long)points.length) {

			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					import std.stdio;
					//writeln("move_indices ", move_indices);
					foreach(i;move_indices) deltas[i][dim] = t[dim].canvas2world_delta(current[dim] - start[dim]); 
				}
				if (end) {
					foreach(i;move_indices) {
						points[i][dim] += deltas[i][dim];
						deltas[i][dim] = 0;
					}
				}
			}
		}
	}

	override void draw(BackendInterface d, in Transform[3] t) const  
	{
		import std.algorithm;

		foreach(i, l; links) { // draw the links
			double[2] pc0, pc1; // endpoints of the line in canvas coordinates
			for (int dim = 0; dim < 2; ++dim) {
				if (t[dim].logscale) {

				} else {
					pc0[dim] = t[dim].world2canvas(points[l[0]][dim] + deltas[l[0]][dim]);
					pc1[dim] = t[dim].world2canvas(points[l[1]][dim] + deltas[l[1]][dim]);
				}
			}
			d.set_color(0,0,0);
			d.set_line_width(1);
			if (move_indices.canFind(l[0])) d.set_line_width(2);
			d.line(pc0[0],pc0[1], pc1[0],pc1[1]);
			d.horizontal_line(pc1[1],pc0[0],pc1[0]);
			d.vertical_line(pc0[0],pc0[1],pc1[1]);
			d.stroke;

		}

		for (int color = 0; color < 2; ++color) // draw the points in 2 colors (first big point with BG-color, then smaller poin with "real" color)
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

protected:
	double[2][] points;
	   int[2][] links;
	double[2][] deltas;
	long highlighted_point_index = -1;
	long[] selected_points;

	// temporarily needed in the drag function
	long[] move_indices;
}




