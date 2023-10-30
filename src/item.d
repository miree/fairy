module item;
@safe:

interface ItemFactory {
	import std.json;
	Item create(ref JSONValue);
}

interface Item {
	import std.json;
	JSONValue toJSON() const ;
	string get_type() const ;
}
struct ItemStore {
	Item item;
	import serializeJSON;
	@SERIALIZE string type;
	@SERIALIZE JSONValue data;
}
