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

///////////////////////////////////////////////////////////////////////
// all user interface functions are here
///////////////////////////////////////////////////////////////////////

@UI_EXPORT("quit program")
@trusted
string quit() {
	import cmdline;
	import std.concurrency;
	import fairy;
	fairy.running = false;
	return "";
}


@UI_EXPORT("create new window")
@trusted
string win(string name, int w = 600, int h = 400) {
	import fairy;
	fairy.session.add_window(name, w, h);
	return "created new window "~name;
}

@UI_EXPORT("render window in ascii text")
@trusted
string showwin(string name, string mode = "double", int w = -1, int h = -1) {
	import std.stdio;
	import std.typecons, std.array, std.algorithm, std.conv;
	Tuple!(int,"status",string,"output") stty_size;
	int stty_w, stty_h;	
	if (w<0 || h<0) {
		import std.process;
		stty_size = execute(["stty","size"]);
		auto output = stty_size.output.stripRight('\n').stripRight('\r').split(' ');
		stty_w = output[1].to!int;
		stty_h = output[0].to!int;
		//writeln("stty_w:", stty_w, " stty_h:",stty_h);
	}
	if (w<0) {
		if (stty_size.status != 0) {
			writeln("could not determine width");
			w = 80;
		} else w = stty_w;
	}
	if (h<0) {
		if (stty_size.status != 0) {
			writeln("could not determine height");
			h = 80;
		} else h = stty_h-1;
	}

	import fairy, asciirender;
	import std.typecons;
	AsciiRender.Mode m = (mode=="quad")?AsciiRender.Mode.quad_pixel:(
		               	 (mode=="double")?AsciiRender.Mode.double_pixel:AsciiRender.Mode.single_pixel
		                 );
	if (m==AsciiRender.Mode.quad_pixel || m==AsciiRender.Mode.double_pixel) h *= 2;
	if (m==AsciiRender.Mode.quad_pixel) w *= 2;

	auto renderer = scoped!AsciiRender(w,h,m);
	//renderer.horizontal_line(h/2, 0,w);
	//renderer.vertical_line(w/2,0,h);
	renderer.rectangle(0,0,w-1,h-1);
	renderer.stroke();
	for (int i = 0; i < w; i+=10) renderer.text(i,h,i.to!string);
	double tw,th;
	renderer.text_extent("0",tw,th);
	for (int i = 0; i < w; i+=10) renderer.text(i,th,i.to!string);

	return renderer.render;
}

@UI_EXPORT("list all windows")
@trusted
string lswin() {
	import fairy;
	return fairy.session.list_windows();
}



alias helper(alias T) = T;
@UI_EXPORT("display help for exported functions", 
	["name of a specific function"])
string help(string name = "__all") {
	import std.traits, std.conv;
	string result;
	if (name == "__all") result ~= "available commands:\n\n";

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
	if (name == "__all") result ~= "\n\"help <command>\" provides details about a specific command";
	return result;
}
