module fairy;
@safe:



struct Session {
	import graphics;
	string name = "default";

	Canvas[string] windows;


	void add_window(string name, int w, int h) {
		if (name[0] >= '0' && name[0] <= '9') {
			throw new Exception("window name must not start with numerical digit");
		}
		if ((name in windows) is null) {
			windows[name] = Canvas(w,h);
		} else {
			throw new Exception("window with name \""~name~"\" already exists");
		}
	}
	string list_windows() {
		import std.array;
		return windows.byKey.array.join('\n');
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


	import cmdline;
	auto console_tid = spawn(&cmdline.run_console, thisTid);
	loop(args);
	// cause the cmdline.run_console thread to stop
	cmdline.close_stdin(); 
}

bool running = true;
void loop(string[] args) {
	while (running) {
		import std.stdio;
		"fairy> ".write;
		iterate;
	}
}

@trusted
void iterate() {
	receive(
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
