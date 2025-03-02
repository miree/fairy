module projection;
@safe:

import item;
import std.json;
import serializeJSON;

class Hist2ProjectorFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Hist2Projector(json);
	}
}


import graphics;
import interactive;

class Hist2Projector : Visual, Item
{
public:
	struct Data{
		@SERIALIZE string hist2d_itemname;
		@SERIALIZE int direction; // 0 -> x-direction, 1 -> y-direction
		@SERIALIZE double[2][] positive_gates;
		@SERIALIZE double[2][] negative_gates;
	}	
	Data data;
	double[2][] gate_deltas; // relevant for user interaction 

	ulong item_version = 0;
	this(string hist2dname, int direction = 0) {
		import fairy;

		//auto hist = fairy.session.items[hist2dname].item;

		data.direction = direction;
	}
	this(ref JSONValue json) {
		import std.stdio;
		try data = deserialize!Data(json);
		catch(Exception e) writeln("Function deserialize error: ", e.msg);
	}
	override JSONValue toJSON()  { return serialize(data); }
	override string get_type()  { return "projection.Hist2Projector"; }
	override void reset() {}
	override ulong getVersion() { return item_version; }
	override void overrideVersion(ulong new_version) { item_version = new_version; }

	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) {
		//return new Hist2ProjectorVisualizer(this, item_version);
		return null;
	}

}
