module fairy;
@safe:

import item;

static this() {
	import histogram;
	import waveform;
	import functions;
	import gate;
	import value;
	import interactive_demo;
	import interactive;
	add_item_factory("waveform.Waveform",                   new WaveformFactory);
	add_item_factory("histogram.FileWaveform",              new FileWaveformFactory);
	add_item_factory("histogram.FileHistogram",             new FileHistogramFactory);
	add_item_factory("histogram.Hist1",                     new Hist1Factory);
	add_item_factory("histogram.Hist2",                     new Hist2Factory);
	add_item_factory("histogram.Hist2Projection",           new Hist2ProjectionFactory);
	add_item_factory("functions.Function",                  new FunctionFactory);
	add_item_factory("gate.Gate1D",                         new Gate1DFactory);
	add_item_factory("gate.Gate2D",                         new Gate2DFactory);
	add_item_factory("gate.PolyGate",                       new PolyGateFactory);
	add_item_factory("value.Value",                         new ValueFactory);
	add_item_factory("interactive_demo.Points",             new PointsFactory);
	add_item_factory("interactive_demo.HierarchicalPoints", new HierarchicalPointsFactory);
	add_item_factory("interactive_demo.Ellipse",            new EllipseFactory);
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


struct Session {
	import graphics;
	string name = "default";

	CanvasProperties[string] windows;
	ItemStore[string] items;


	void check_name_helper(string prefix, string name) {
		if (name is null) {
			throw new Exception(prefix ~= " no item with name " ~ name);
		}
		if (name[0] >= '0' && name[0] <= '9' || name[0] == '.') {
			throw new Exception(prefix ~ " name must not start with numerical digit or decimal point");
		}	
	}

	void add_item(string name, Item item, NameCollisionPolicy policy = NameCollisionPolicy.disallow) {
		check_name_helper("item ", name);
		if (start_gui) {
			if (main_gui !is null) {
				main_gui.add_item(name);
			}
		}
		if ((name in items) !is null) { // item already exists
			final switch(policy) {
				case NameCollisionPolicy.replace:
					if (start_gui) {
						if (main_gui !is null) {
							main_gui.reset_item(name);
						}
					}
				break;
				case NameCollisionPolicy.disallow:
					throw new Exception("item with name \""~name~"\" already exists");
				break;
			}
		}
		items[name] = ItemStore(item);
	}
	void remove_item(string name) {
		check_name_helper("item ", name);
		if (start_gui) {
			if (main_gui !is null) {
				main_gui.remove_item(name);
			}
		}
		if ((name in items) is null) {
			throw new Exception("no item with name \""~name~"\"");
		} else {
			items.remove(name);
		}

	}
	void remove_items(string[] names) {
		foreach(name; names) {
			check_name_helper("item ", name);
			if ((name in items) is null) {
				continue;
			} else {
				items.remove(name);
			}
		}
		if (start_gui) {
			if (main_gui !is null) {
				foreach (window; windows.byKey) {
					main_gui.update_from_canvas(window);
				}
			}
		}
	}
	void reset_item(string name) {
		check_name_helper("item ", name);
		if ((name in items) is null) {
			throw new Exception("no item with name \""~name~"\"");
		} else {
			items[name].item.reset;
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
				result ~= name ~ " : " ~ items[name].item.get_type ~ "\n";
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
	void close_window(string name) {
		check_name_helper("window ", name);
		if ((name in windows) !is null) {
			windows.remove(name);
			if (start_gui) {
				if (main_gui !is null) {
					main_gui.close_window(name);
				}
			}
		} else {
			throw new Exception("there is no window with name \""~name~"\"");
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
			        ~ windows[name].height.to!string
			        ~ ": ";
			        foreach(itemname; windows[name].itemnames) {
			        	result ~= itemname ~ " ";
			        }
			        result ~= "\n";
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
	Visual get_visual_item(string name) {
		auto item = name in items;
		if (item is null) {
			throw new Exception("there is no item with name ", name);
		}
		Visual visual = cast(Visual)item.item;
		if (visual is null) {
			throw new Exception("item " ~ name ~ " cannot be visualized");
		}
		return visual;
	}

	void close() {
		//import std.stdio;
		//writeln("windows -> ", windows.byKey);
		import std.array;
		foreach(name; items.byKey.array) {
			import ui;
			remove_item(name);
		}
		auto window_names = windows.byKey.array;
		foreach(name; window_names) {
			remove_window(name);
			windows.remove(name);
		}
		//writeln("windows after close() -> ", windows.byKey);
		items = null;
	}

	import std.file, std.json, std.algorithm, serializeJSON;
	@trusted
	void read_from_file() {
		try {
			JSONValue json = readText(name~".session").parseJSON(-1,JSONOptions.specialFloatLiterals);
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
		//writeln("save session to file ", filename);
		JSONValue json_out;
		writeln("write_to_file");
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
	string execute;
	bool no_gui=false;
	auto getopt_result = getopt(args,
		"session|s", "session name (default = session)", &session.name,
		"nogui|g",   "do not launch gui at application start", &no_gui,
		"execute|e", "execute this command after startup", &execute 
	);	
	start_gui = !no_gui;

	import std.stdio, std.algorithm;
	if (session.name.endsWith(".session")) session.name = session.name[0..$-".session".length];
	writeln("session ", session.name);
	session.read_from_file();


	import cmdline;
	auto console_tid = spawn(&cmdline.run_console, thisTid);
	if (execute.length)	thisTid.send(cmdline.Command(cast(immutable string)execute, thisTid));
	loop(args);
	// cause the cmdline.run_console thread to stop
	//cmdline.close_stdin(); 
	session.write_to_file();
}

public bool start_gui = true;
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
			}
			else version(gtk3) {
				import graphics_gtk;
				main_gui = new GtkGui;
			}
			else version(gtk4) {
				import graphics_gtk;
				main_gui = new GtkGui;
			}
			else version(gtk4_native) {
				import graphics_gtk4_native;
				main_gui = new Gtk4NativeGui;
			}
			else version(minigui) {
				import graphics_minigui;
				main_gui = new MiniGui;
			}
			else version(minigui_gl) {
				import graphics_minigui_gl;
				main_gui = new MiniGuiGL;
			}
			else {
				stdout.writeln("Error: no graphics back-end available");
				start_gui = false;
			}
			if (session.windows.length == 0) {
				import cmdline;
				thisTid.send(cmdline.Command("win window0", thisTid));
			}

		}

		if (main_gui !is null) return main_gui.loop();

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

void redraw_windows() {
	if (start_gui) {
		if (main_gui !is null) {
			foreach(window_name; session.windows.byKey) {
				main_gui.redraw_window(window_name);
			}
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


version (elderpt) {

	import elderpt;
	// add a module destructor that ensures the termination 
	// of elderpt thread before the application goes down.
	@trusted
	static ~this() {
		import std.concurrency;
		if (elderpt.running) {
			elderpt.tid.send(elderpt.MsgStop());
			receive((elderpt.MsgAck msg) {});
		}
	}

	@trusted
	void handle_elderpt_MsgHist1dCreate(MsgHist1dCreate msg) {
		import item, histogram;
		fairy.session.add_item(msg.name, cast(Hist1)msg.hist, NameCollisionPolicy.replace);
	}
	@trusted
	void handle_elderpt_MsgHist2dCreate(MsgHist2dCreate msg) {
		import item, histogram;
		fairy.session.add_item(msg.name, cast(Hist2)msg.hist, NameCollisionPolicy.replace);
	}
	@trusted
	void handle_elderpt_MsgGate1DCreate(MsgGate1DCreate msg) {
		import item, gate;
		fairy.session.add_item(msg.name, cast(Gate1D)msg.gate, NameCollisionPolicy.replace);
	}
	@trusted
	void handle_elderpt_MsgGate2DCreate(MsgGate2DCreate msg) {
		import item, gate;
		fairy.session.add_item(msg.name, cast(Gate2D)msg.gate, NameCollisionPolicy.replace);
	}
	@trusted
	void handle_elderpt_MsgPolyGateCreate(MsgPolyGateCreate msg) {
		import item, gate;
		fairy.session.add_item(msg.name, cast(PolyGate)msg.gate, NameCollisionPolicy.replace);
	}

}

version(alsa) {
	// audiodaq waveforms
	import audiodaq;
	@trusted
	void handle_audiodaq_Waveform(MsgWaveformCreate msg) {
		import item, waveform;
		auto wf = new Waveform(msg.wave);
		import std.stdio;
		//writeln("got waveform ", msg.name, " ", wf.get_type(), " N=", wf.d.N);
		fairy.session.add_item(msg.name, wf, NameCollisionPolicy.replace);
		import std.concurrency;
		audiodaq.tid.send(audiodaq.MsgAck());
	}

	void handle_audiodaq_Error(MsgError msg) {
		import std.stdio;
		writeln("got error from audiodaq");
		audiodaq.running = false;
		audiodaq.paused = false;
	}
}

@trusted
// return false in case of timeout
bool iterate(uint timeout_ms) {
	import std.datetime;
	import cmdline;
	bool got_cmd = false;

	while (receiveTimeout(dur!"msecs"(timeout_ms),
		&cmdline.handle_Command,
		&cmdline.handle_Quit,
		&cmdline.handle_QuitWithError
	)) { got_cmd = true; }	
	version(elderpt) {
		while (receiveTimeout(dur!"msecs"(0),
			&handle_elderpt_MsgHist1dCreate,
			&handle_elderpt_MsgHist2dCreate,
			&handle_elderpt_MsgGate1DCreate,
			&handle_elderpt_MsgGate2DCreate,
			&handle_elderpt_MsgPolyGateCreate
		)) {}
	}
	version(alsa) {
		while (receiveTimeout(dur!"msecs"(0),
			&handle_audiodaq_Waveform,
			&handle_audiodaq_Error
			)) {}
	}
	return got_cmd;
}

