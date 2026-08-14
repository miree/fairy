//    Fairy: Flexible Analysis of Ionizing Radiation Yields
//    Copyright (C) 2019-2026 Michael Reese

//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.

//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.

//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <https://www.gnu.org/licenses/>.

module cmdline;
@safe:

public import std.concurrency;


struct Command { immutable string command; Tid tid;}
struct QuitWithError { string msg; string file; ulong line; }
struct Quit {}
struct Continue {};

//////////////////////////////////////////////////////////
/// responses to messages from module cmdline
//////////////////////////////////////////////////////////
@trusted
void handle_Command(cmdline.Command cmd) {
	import std.stdio;
	try {
		import std.array: split;
		auto lines = cmd.command.split('\n');
		foreach(line; lines) {
			auto tokens = line.split;
			cmdline.run_with_args(tokens).writeln;
			//import core.thread;
			//Thread.sleep(10.msecs);
		}
	} catch (Exception e) {
		writeln("Error: ", e.msg);
	}
	cmd.tid.send(cmdline.Continue());
}

void handle_Quit(cmdline.Quit q) {
	import fairy;
	fairy.running = false;	
}

void handle_QuitWithError(cmdline.QuitWithError qe) {
	throw(new Exception(qe.msg, qe.file, qe.line));
}



@trusted int wait_for_input() {
	import core.sys.posix.poll : poll, pollfd, POLLIN;
	import core.sys.posix.unistd : STDIN_FILENO;
	auto pfd = pollfd(STDIN_FILENO, POLLIN); 
	int timeout_ms = 100;
	return poll(&pfd,1,timeout_ms);
}

//void close_stdin() {
//	import core.sys.posix.unistd;
//	close(STDIN_FILENO);	
//}

@trusted
void run_console(Tid main_thread) {
	import std.string, std.algorithm;
	bool running = true;
	try {
		while(running) {
			const pollresult = wait_for_input();
			if (pollresult>0) { // stdin has data
				import std.stdio;
				auto input = stdin.readln;
				auto command = input.stripRight('\n').stripRight('\r').strip(' ');
				// comment
				if (command.startsWith("#")) continue;
				if (input.empty){ 
					main_thread.send(Quit());
					break;
				} 
				// the receiver of this message should send the Continue message in response
				if (input.length) {
					main_thread.send(Command(command, thisTid));
					// wait until the reciever sends Continue signal
					receive((Continue c) {});
				}
			}
			else { // timeout 
				import std.datetime;
				receiveTimeout(dur!"msecs"(0), 
					(Quit q) { 
						running = false;	
					},
					(Command cmd) { 
						main_thread.send(Command(cmd.command, thisTid)); 
						receive((Continue c){});
					}
				);
			}
		}
	} catch (const Exception e) {
		main_thread.send(QuitWithError(e.msg, e.file, e.line));
	}
}

string run_with_args(string[] args){
	import std.traits, std.conv;
	import ui;
	string name;
	string result;
	if (args.length) {
		name = args[0];
		args = args[1..$];

		bool function_found = false;

		alias mod = helper!(mixin("ui"));

		static foreach(memberName; __traits(allMembers, mod)) {{
			alias member = helper!(__traits(getMember, mod, memberName));
			static if (__traits(isStaticFunction, member) && hasUiExport!member) {
				if (name == memberName) {
					alias func = member;
					ParameterTypeTuple!func arguments;
					alias argumentNames    = ParameterIdentifierTuple!func;
					alias defaultArguments = ParameterDefaultValueTuple!func;
					if (args.length > arguments.length) {
						throw new Exception("Two many arguments for function " ~ memberName);
					}						
					foreach(idx, ref arg; arguments) {
						if (idx < args.length) {
							arg = to!(typeof(arg))(args[idx]);
						} else static if (!is(defaultArguments[idx] == void)) {
							arg = defaultArguments[idx];
						} else {
							throw new Exception("Requiered argument " ~ argumentNames[idx] ~ " is missing for function " ~ memberName);
						}
					}
					static if(is(ReturnType!func == void)) {
						func(arguments);
					} else {
						result = to!string(func(arguments));
					}
					function_found = true;
					return result;
				}
			}
		}}
		throw new Exception("No function with name " ~ name);
	}
	throw new Exception("Function name required");
	return result;
}
