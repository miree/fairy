module ui;
@safe:

// struct for user defined attribute
struct UI_EXPORT {
	string   description;
	string[] arg_descriptions;
}
auto getAttribute(alias mem, T)() {
	foreach (attr; __traits(getAttributes, mem)) {
		static if (is(typeof(attr) == T)) {
			return attr;
		}
	}
	return T.init;
}
bool hasUiExport(alias mem)() {
	foreach (attr; __traits(getAttributes, mem)) {
		static if (is(typeof(attr) == UI_EXPORT)) {
			return true;
		}
	}
	return false;
}



@UI_EXPORT("quit program")
@trusted
string quit() {
	import cmdline;
	import std.concurrency;
	import fairy;
	fairy.running = false;
	return "";
}


alias helper(alias T) = T;
@UI_EXPORT("display help for exported functions", 
	["name of a specific function"])
string help(string name = "__all") {
	import std.traits, std.conv;
	string result = "available commands:\n\n";

	alias mod = helper!(mixin(__MODULE__));
	static foreach(memberName; __traits(allMembers, mod)) {{
		alias member = helper!(__traits(getMember, mod, memberName));
		static if (__traits(isStaticFunction, member) && hasUiExport!member) {
			alias func = member;
			if (name == "__all") { // no specific function was requested
				auto num_spaces = 20 - memberName.length;
				result ~= memberName;
				foreach(i;0..num_spaces) result ~= ' ';
				result ~= getAttribute!(func,UI_EXPORT).description ~ "\n";
			} else {
				if (name == memberName) {
					result ~= "usage: " ~ name ~ " ";
					foreach(argName; ParameterIdentifierTuple!func) {
						result ~= " " ~ argName;
					}
					result ~= "\n\n" ~ getAttribute!(func,UI_EXPORT).description ~ "\n";
					if (ParameterTypeTuple!func.length) {
						result ~= "Arguments:\n";
						auto arg_descriptions = getAttribute!(func,UI_EXPORT).arg_descriptions;
						foreach(idx, argName; ParameterIdentifierTuple!func) {
							static if (is(ParameterDefaultValueTuple!func[idx] == void)) {
								string defaultValue = null;
							} else {
								string defaultValue = ParameterDefaultValueTuple!func[idx].to!string;
							}
							string argDesc = "?";
							if (idx < arg_descriptions.length) {
								argDesc = arg_descriptions[idx];
							}
							string argType = ParameterTypeTuple!func[idx].stringof;
							result ~= "    " ~ argName ~ " (" ~ argType ~ "): " ~ argDesc;
							if (defaultValue !is null) {
								result ~= " [default=" ~ defaultValue ~ "]";
							} 
							result ~= "\n";
						}
					}
				}
			}
		}
	}}
	return result;
}
