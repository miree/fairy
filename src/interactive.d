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
	long handle = -1; // this is context dependent, each Interactive element 
	                  // must put a number here that allows it to identify the 
	                  // element that is associated with this bounding box
	this (double x_1, double y_1, double x_2, double y_2, long h) {
		// make sure that x2 >= x1 
		if (x_2 > x_1) { x1 = x_1; x2 = x_2; } 
		else           { x2 = x_1; x1 = x_2; }

		// make sure that y2 >= y1 
		if (y_2 > y_1) { y1 = y_1; y2 = y_2; } 
		else           { y2 = y_1; y1 = y_2; }

		handle = h;
	}
	bool valid() {
		return x1 !is double.init;
	}
	double area() const {
		return (x2-x1)*(y2-y1);
	}
	bool contains(double x, double y) const {
		if (x < x1) return false;
		if (x > x2) return false;
		if (y < y1) return false;
		if (y > y2) return false;
		return true;
	}
	bool contains(in BoundingBox b) const {
		// b is contained if two opposite corner points are contained
		if (contains(b.x1,b.y1) && 
			contains(b.x2,b.y2)) return true;
		return false;
	}
	bool opEquals(in BoundingBox b) {
		// all points identical means equal
		// note that this is not consistent with equality as derived from opCmp
		// (a==b) differs from (!(a<b) && !(b<a)) 
		return x1 == b.x1 &&
		       x2 == b.x2 && 
		       y1 == b.y1 &&
		       y2 == b.y2;
	}
	int opCmp(in BoundingBox b) {
		// (a==b) differs from (!(a<b) && !(b<a))
		
		// first see if one box contains the other 
		if (b.contains(this)) return -1;
		if (this.contains(b)) return  1;
		
		// then compare the areas 
		if (this.area < b.area) return -1;
		if (b.area < this.area) return  1;

		// then assume they are equal
		return 0;
	}
}


unittest {
	import std.stdio;
	writeln("Test BoundingBox");
	auto bb1 = BoundingBox(2,2,1,1);
	assert(bb1.x1 == 1);
	assert(bb1.x2 == 2);
	assert(bb1.y1 == 1);
	assert(bb1.y2 == 2);

	auto bb2 = BoundingBox(0,0,4,4);
	assert(bb2.contains(bb1));
	assert(!bb1.contains(bb2));
	assert(bb1.contains(1.5,1.5));
	assert(!bb1.contains(0,1.5));
	assert(!bb1.contains(1.5,0));
	assert(!bb1.contains(0,3));
	assert(!bb1.contains(3,0));

	auto bbs = [bb2,bb1];
	import std.algorithm, std.array;
	assert(bbs.sort.array == [bb1,bb2]);

	auto helper1 = BoundingBox();
	assert(!helper1.valid);
	assert(bb1.valid);
	assert(bb2.valid);
}
