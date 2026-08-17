//    Fairy: Flexible Analysis of Ionizing Radiation Yields
//    Copyright (C) 2019-2026 Michael Reese

//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.

//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.

//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <https://www.gnu.org/licenses/>.

module value;
@safe:

import item;
import std.json;
import serializeJSON;


class ValueFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Value(json);
	}
}

import graphics;

class Value : Visual, Item
{
	struct Data {
		@SERIALIZE int dimension; // 0=x, 1=y, 2=z;
		@SERIALIZE double value;
		@SERIALIZE string text;
	}
	Data data;
	double delta = 0;
	ulong item_version = 0;
	this(double v, int dim, string t) {
		data.value = v;
		data.dimension = dim;
		data.text = t;
	}
	this (ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
		} catch(Exception e) {
			writeln("Value deserialize error: ", e.msg);
		} 
	}
	override JSONValue toJSON()  { return serialize(data); }
	override string get_type()  {
		return "value.Value";
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
		return new ValueVisualizer(this);
	}

}



import graphics;
import interactive;

class ValueVisualizer : Visualizer, Interactive
{
	Value value;
	long highlight_handle = -1;
	long selected_handle = -1;
public:

	import std.stdio;
	this(Value val)
	{
		value = val;
		super(value.item_version, value.data.dimension);
	}
	import graphics, transform;

	@trusted override void draw(BackendInterface d, in Transform[3] t, bool modified)   
	{
		if (value.data.dimension == 0) {
			double x = t[0].world2canvas(t[0].log(value.data.value + value.delta));
			double y0 = t[1].world2canvas(t[1].min);
			double y1 = t[1].world2canvas(t[1].max);
			d.set_line_width(2.0);
			if (highlight_handle == 1) {
				d.set_line_width(4.0);
			}
			d.set_color(0.0,0.5,0);
			if (selected_handle == 1) {
				d.set_color(1.0,0,0);
			}
			d.vertical_line(x, y0, y1);
			d.stroke();
			double w,h;
			d.text_extent(value.data.text,w,h);
			d.text(x,y1+h,value.data.text);
			d.stroke();
		}
		if (value.data.dimension == 1) {
			double y = t[1].world2canvas(t[1].log(value.data.value + value.delta));
			double x0 = t[0].world2canvas(t[0].min);
			double x1 = t[0].world2canvas(t[0].max);
			d.set_line_width(2.0);
			if (highlight_handle == 1) {
				d.set_line_width(4.0);
			}
			d.set_color(0.0,0.5,0);
			if (selected_handle == 1) {
				d.set_color(1.0,0,0);
			}
			d.horizontal_line(y, x0, x1);
			d.stroke();
			double w,h;
			d.text_extent(value.data.text,w,h);
			d.text(x0,y,value.data.text);
			d.stroke();
		}
	}

	// Interactive overrides
	override BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t) { 

		double mouse_world;
		if (value.data.dimension == 0) mouse_world = t[0].log(mouse_world_x);
		else                           mouse_world = t[1].log(mouse_world_y);

		double canvas_value = t[value.data.dimension].world2canvas(t[value.data.dimension].log(value.data.value));
		const double min_width = 10; // we give the user at least that many pixels to grab on
		double canvas_min = canvas_value-min_width;
		double canvas_max = canvas_value+min_width;

		// move back to world coordinates
		double min = (t[value.data.dimension].canvas2world(canvas_min)); 
		double max = (t[value.data.dimension].canvas2world(canvas_max)); 

		if (value.data.dimension == 1) {
			import std.algorithm;
			swap(min,max);
		}

		if (mouse_world > min && mouse_world < max) 
		{
			if (value.data.dimension == 0) return BoundingBox(min, t[1].min, max, t[1].max, max-min, this, 1);			
			else                           return BoundingBox(t[0].min, min, t[0].max, max, max-min, this, 1);			
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
		if (add_or_remove && handle == 1) {
			selected_handle = !selected_handle;
		} else {
			selected_handle = handle;
		}
	}
	override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
		if (value.data.dimension == 1) {
			double v = t[1].world2canvas(t[1].log(value.data.value));
			if (v >= y1 && v <= y2) {
				if (remove) selected_handle = -1;
				else        selected_handle =  1;
			}
			return;
		}	
		double v = t[0].world2canvas(t[0].log(value.data.value));
		if (v >= x1 && v <= x2) {
			if (remove) selected_handle = -1;
			else        selected_handle =  1;
		}
		return;
	}
	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool ctrl = false, bool shift = false, bool end = false) {
		if (handle == 1 || selected_handle == 1) {
			double delta;
			if (value.data.dimension == 0) delta = t[0].canvas2world_delta(x_canvas - x_canvas_start);
			else                           delta = t[1].canvas2world_delta(y_canvas - y_canvas_start);

			if (t[value.data.dimension].logscale) {
				import std.math;
				value.delta = value.data.value*exp(delta) - value.data.value;
			} else {
				value.delta = delta;
			}

			if (end) {
				value.data.value += value.delta;
				value.delta = 0;
			}
		}
	}


}