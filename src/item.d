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

module item;
@safe:

interface ItemFactory {
	import std.json;
	Item create(ref JSONValue);
}

interface Item {
	import std.json;
	JSONValue toJSON() ;
	string get_type() ;
	void reset();
}
struct ItemStore {
	Item item;
	import serializeJSON;
	@SERIALIZE string type;
	@SERIALIZE JSONValue data;
}

enum NameCollisionPolicy{
	disallow,
	replace
}

/////////////////////////////////////////////////////////////////////////////////
// generic "properties window" support (see graphics_gtk.d's PropertiesWindow for the actual
// GTK widget construction). An Item that wants to expose its Data struct's @EDITABLE fields
// implements HasProperties with a one-line body:
//   override void visitEditableFields(FieldVisitor v) { item.visitEditableFields(data, v); }
// FieldVisitor can't be a templated interface method (D doesn't allow those), so it's instead a
// fixed, finite overload set covering the primitive types a Data struct field can realistically
// be; visitEditableFields(T) below does the actual @SERIALIZE+@EDITABLE introspection over the
// concrete Data struct type T, so the per-Item boilerplate stays to that one line.
/////////////////////////////////////////////////////////////////////////////////
interface FieldVisitor {
	void field(string name, ref int value);
	void field(string name, ref long value);
	void field(string name, ref ulong value);
	void field(string name, ref double value);
	void field(string name, ref bool value);
	void field(string name, ref string value);
}
interface HasProperties {
	void visitEditableFields(FieldVisitor v);
}
void visitEditableFields(T)(ref T data, FieldVisitor v) {
	import serializeJSON, std.traits;
	alias helper(alias X) = X;
	static foreach(memberName; __traits(allMembers, T)) {{
		alias member = helper!(__traits(getMember, T, memberName));
		static if (!isSomeFunction!(typeof(member))) {
			if (isSERIALIZEd!(T,memberName)(data) && isEDITABLEd!(T,memberName)(data)) {
				// silently skip any @EDITABLE field whose type isn't one FieldVisitor
				// supports (e.g. an array), rather than failing to compile -- keeps
				// "non-array types and strings" an opt-in-per-field property, not a
				// footgun if a struct ever grows an array field that gets tagged by mistake.
				static if (__traits(compiles, v.field(memberName, __traits(getMember, data, memberName)))) {
					v.field(memberName, __traits(getMember, data, memberName));
				}
			}
		}
	}}
}
