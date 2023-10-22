module histogram;
@safe:

import fairy;
import std.json;
import serializeJSON;

static this() {
	fairy.add_item_factory(FileHistogram.stringof, new FileHistogramFactory);
}

class FileHistogramFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new FileHistogram(json);
	}
}

class FileHistogram : Item {
	struct Data {
		@SERIALIZE string filename;
	}
	Data data;
	this(Data d)             { data = d; }
	this(ref JSONValue json) { data = deserialize!Data(json); }
	override JSONValue toJSON() { return serialize(data); }
	override string get_type()   { 
		return typeof(this).stringof; 
	}

}
