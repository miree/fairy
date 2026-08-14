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

module app;
@safe:

int main(string[] args) {

	import fairy;
	try {
		import std.stdio;

		writeln;
    	writeln("Fairy: Flexible Analysis of Ionizing Radiation Yields");
    	writeln("Copyright (C) 2019-2026 Michael Reese");
    	writeln("License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>");
    	writeln;
		writeln("This program is free software: you can redistribute it and/or modify");
		writeln("it under the terms of the GNU General Public License as published by");
		writeln("the Free Software Foundation, either version 3 of the License, or");
		writeln("(at your option) any later version.");
		writeln;
		writeln("This program is distributed in the hope that it will be useful,");
		writeln("but WITHOUT ANY WARRANTY; without even the implied warranty of");
		writeln("MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the");
		writeln("GNU General Public License for more details.");
		writeln;

		fairy.run(args);
	} catch (Exception e) {
		import std.stdio;
		writeln("Exception: ", e.file ,":", e.line, " : ", e.msg);
		return -1;
	}
	return 0;
}
