module fairy;
@safe:



struct Session {
	import graphics;
	string name = "default";

	CanvasProperties[string] windows;


	void add_window(string name, int w, int h, int xpos, int ypos) {
		if (name[0] >= '0' && name[0] <= '9') {
			throw new Exception("window name must not start with numerical digit");
		}
		if ((name in windows) is null) {
			windows[name] = CanvasProperties(w,h,xpos,ypos);
			if (start_gui) {
				version(allegro5) {
					import graphics_allegro5;
					gui_add_window(name,windows[name]);
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

	import std.file, std.json, std.algorithm, serializeJSON;
	@trusted
	void read_from_file() {
		try {
			JSONValue json = readText(name~".session").parseJSON;
			if (!json["windows"].isNull) {
				JSONValue window_jsons = json["windows"];
				windows = deserialize!(CanvasProperties[string])(window_jsons);
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
		json_out["windows"] = serialize(windows);
		write(filename, json_out.toJSON(true, JSONOptions.specialFloatLiterals));
	}
}

Session session;

@trusted
void run(string[] args) {

	import std.getopt;
	auto getopt_result = getopt(args,
		"session|s", "session name (default = session)", &session.name
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
				gui_loop();
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
