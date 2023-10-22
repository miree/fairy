module fairy;
@safe:


interface ItemFactory {
	import std.json;
	Item create(ref JSONValue);
}

ItemFactory[string] item_factories;
void add_item_factory(string item_type, ItemFactory factory) {
	auto f = item_type in item_factories;
	if (f !is null) {
		// this is not supposed to be caught
		throw new Error("cannot add ItemFactory " ~ item_type ~ ", it already exists");
	}
	item_factories[item_type] = factory;
}

interface Item {
	import std.json;
	JSONValue toJSON();
	string get_type();
}
struct ItemStore {
	Item item;
	import serializeJSON;
	@SERIALIZE string type;
	@SERIALIZE JSONValue data;
}

struct Session {
	import graphics;
	string name = "default";

	CanvasProperties[string] windows;
	ItemStore[string] items;


	void check_name_helper(string prefix, string name) {
		if (name[0] >= '0' && name[0] <= '9' || name[0] == '.') {
			throw new Exception(prefix ~ " name must not start with numerical digit or decimal point");
		}	
	}

	void add_item(string name, Item item) {
		check_name_helper("item ", name);
		if ((name in items) is null) {
			items[name] = ItemStore(item);
		} else {
			throw new Exception("item with name \""~name~"\" already exists");
		}
	}

	string list_items(bool include_null) {
		import std.algorithm, std.array, std.conv;
		string result;
		foreach(name; items.byKey.array.sort) {
			string is_null = "";
			if (items[name].item is null) {
				if (include_null) result ~= name ~ " : unknown type \"" ~ items[name].type ~ "\"\n";
			} else {
				result ~= name ~ " : " ~ items[name].type ~ "\n";
			}
		}
		return result;		
	}


	void add_window(string name, int w, int h, int xpos, int ypos) {
		check_name_helper("window ", name);
		if ((name in windows) is null) {
			windows[name] = CanvasProperties(w,h,xpos,ypos);
			if (start_gui) {
				if (main_gui !is null) {
					main_gui.add_window(name, windows[name]);
				}
			}
		} else {
			throw new Exception("window with name \""~name~"\" already exists");
		}
	}
	string list_windows() {
		import std.algorithm, std.array, std.conv;
		string result;
		foreach(name; windows.byKey.array.sort) {
			result ~= name 
			        ~ " " 
			        ~ windows[name].width.to!string 
			        ~ "x" 
			        ~ windows[name].height.to!string ~ "\n";
		}
		return result;
	}
	CanvasProperties *get_canvas(string name) {
		auto canvas = name in windows;
		if (canvas is null) {
			throw new Exception("there is no window with name ", name);
		}
		return canvas;
	}

	void close() {
		import std.array;
		auto window_names = windows.byKey.array;
		foreach(name; window_names) {
			remove_window(name);
		}
		items = null;
	}

	import std.file, std.json, std.algorithm, serializeJSON;
	@trusted
	void read_from_file() {
		try {
			JSONValue json = readText(name~".session").parseJSON;
			// loading windows by deserializing the entire JSONValue
			if (!json["windows"].isNull) {
				JSONValue window_jsons = json["windows"];
				windows = deserialize!(CanvasProperties[string])(window_jsons);
			}
			// we first need to read the item types ...
			if (!json["items"].isNull) {
				JSONValue item_jsons = json["items"];
				items = deserialize!(ItemStore[string])(item_jsons);
			}
			// ... then restore the item using the type and the item factory
			import std.stdio;
			foreach(name, ref item; items) {
				auto factory = item.type in item_factories;
				if (factory !is null) {
					item.item = factory.create(item.data);
				} else {
					writeln("Found item \"", name, "\" with unknown type: \"", item.type, "\"");
				}
			}

		} catch (Exception e) {
			import std.stdio;
			writeln("Cannot load session: ", e.msg, ", creating a new session!");
		}



	}
	void write_to_file() {
		import std.stdio : writeln;
		auto filename = name~".session";
		writeln("save session to file ", filename);
		JSONValue json_out;
		// windows are easy, because we can directly serialize the array
		json_out["windows"] = serialize(windows);

		// items are polymorphic, so we have to call the virtual toJSON for each item
		// and also store the item type in the surrounding structure so it will be serialized as well
		foreach(ref item; items) {
			if (item.item !is null) {
				item.type = item.item.get_type();
				item.data = item.item.toJSON();				
			}
		}
		json_out["items"] = serialize(items);

		write(filename, json_out.toJSON(true, JSONOptions.specialFloatLiterals));
	}
}

Session session;

@trusted
void run(string[] args) {

	import std.getopt;
	auto getopt_result = getopt(args,
		"session|s", "session name (default = session)", &session.name,
		"gui|g", "start gui at startup", &start_gui
	);	

	import std.stdio;
	writeln("session ", session.name);
	session.read_from_file();


	import cmdline;
	auto console_tid = spawn(&cmdline.run_console, thisTid);
	loop(args);
	// cause the cmdline.run_console thread to stop
	cmdline.close_stdin(); 
	session.write_to_file();
}

public bool start_gui = false;
import graphics;
Gui main_gui = null;
public bool running = true;
@trusted
void loop(string[] args) {

	while(running) {

		import std.stdio;
		stdout.write("fairy> ");
		stdout.flush();
		while (running && !start_gui) {
			if (iterate(10)) {
				stdout.write("fairy> ");
				stdout.flush();
			}
		}

		if (start_gui) {
			version(allegro5) {
				import graphics_allegro5;
				main_gui = new Allegro5Gui;
				main_gui.loop();
				return;
			}
			else version(gtk3) {
				import graphics_gtk;
				return;
			}
			else version(gtk4) {
				import graphics_gtk;
				return;
			}
			else {
				stdout.writeln("Error: no graphics back-end available");
				start_gui = false;
			}
		}

	}

}

// this is the central function to initiate a redraw from outside the graphics 
// backend, for example by all functions in "ui" module that need to redraw a window
void redraw_window(string name) {
	if (start_gui) {
		if (main_gui !is null) {
			main_gui.redraw_window(name);
		}
	}
}

void remove_window(string name) {
	if (start_gui) {
		if (main_gui !is null) {
			main_gui.close_window(name);
		}
	}
}


@trusted
// return false in case of timeout
bool iterate(uint timeout_ms) {
	import std.datetime;
	return receiveTimeout(dur!"msecs"(timeout_ms),
		&cmdline_Command,
		&cmdline_Quit,
		&cmdline_QuitWithError
	);	
}

//////////////////////////////////////////////////////////
/// responses to messages from module cmdline
//////////////////////////////////////////////////////////
import cmdline;
@trusted
void cmdline_Command(cmdline.Command cmd) {
	import std.stdio;
	try {
		import std.array: split;
		auto tokens = cmd.command.split;
		cmdline.run_with_args(tokens).writeln;
	} catch (Exception e) {
		writeln("Error: ", e.msg);
	}

	cmd.tid.send(cmdline.Continue());
}

void cmdline_Quit(cmdline.Quit q) {
	running = false;	
}

void cmdline_QuitWithError(cmdline.QuitWithError qe) {
	throw(new Exception(qe.msg, qe.file, qe.line));
}
