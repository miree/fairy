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
	bool valid() const {
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
