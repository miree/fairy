module app;
@safe:


int main(string[] args) {
	import fairy;
	try {
		fairy.run(args);
	} catch (Exception e) {
		import std.stdio;
		writeln("Exception: ", e.msg);
		return -1;
	}
	return 0;
}
