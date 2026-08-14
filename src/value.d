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
	}
	Data data;
	ulong item_version = 0;
	this(double v, int dim) {
		data.value = v;
		data.dimension = dim;
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




class ValueVisualizer : Visualizer
{
	Value value;
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
			double x = t[0].world2canvas(t[0].log(value.data.value));
			double y0 = t[1].world2canvas(t[1].min);
			double y1 = t[1].world2canvas(t[1].max);
			d.set_line_width(2.0);
			d.set_color(1.0,0,0);
			d.vertical_line(x, y0, y1);
			d.stroke();
		}
	}

}