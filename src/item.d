module item;
@safe:

interface ItemFactory {
	import std.json;
	Item create(ref JSONValue);
}

interface Item {
	import std.json;
	JSONValue toJSON() ;
	string get_type() ;
	void reset();
}
struct ItemStore {
	Item item;
	import serializeJSON;
	@SERIALIZE string type;
	@SERIALIZE JSONValue data;
}

enum NameCollisionPolicy{
	disallow,
	replace
}
