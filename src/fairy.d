module fairy;
@safe:

import draw;

bool running = true;

@trusted
void run(string[] args) {
	import cmdline;
	auto console_tid = spawn(&cmdline.run_console, thisTid);
	loop(args);
	// cause the cmdline.run_console thread to stop
	cmdline.close_stdin(); 
}

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
