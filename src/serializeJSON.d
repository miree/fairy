module serializeJSON;
@safe:

public import std.json;
import std.traits;

interface PersistentData(Representation) {
	void read(in Representation r);
	void write(ref Representation r);
}

auto serialize(T)(in T data) pure {
	JSONValue json;
	serialize!T(data,json);
	return json;
}
void serialize(T)(in T data, ref JSONValue json) {
	static if (isAggregateType!T) serialize_struct!T(data,json);
	else json = JSONValue(data);
}
T deserialize(T)(in JSONValue json) pure {
 	static      if (isAssociativeArray!T) return deserialize_aa!(KeyType!T,ValueType!T)(json);
 	else static if (isSomeString!T)       return json.get!T;
 	else static if (isStaticArray!T)      return deserialize_sa!(T)(json); 
 	else static if (isDynamicArray!T)     return deserialize_da!(T)(json); 
 	else static if (isAggregateType!T)    return deserialize_struct!(T)(json); 
 	else return json.get!T;
}



private:


void serialize_struct(T)(in T structure, ref JSONValue json) {
	import std.json;
	import std.traits;
	alias helper(alias T) = T;
	static foreach(memberName; __traits(allMembers, T)) {{
		alias member = helper!(__traits(getMember, T, memberName));
		static if (!isSomeFunction!(typeof(member))) {
			JSONValue member_json;
			mixin("serialize(structure." ~ memberName ~ ", member_json);");
			json[memberName] = member_json;
		}
	}}
}

@trusted
V[K] deserialize_aa(K,V)(in JSONValue json) pure {
	auto result = new V[K];
	foreach(string k, j;json.object) result[k] = j.deserialize!V;
	return result;
}
@trusted
T deserialize_sa(T)(in JSONValue json) pure {
	T result;
	foreach(idx, j; json.array) result[idx] = j.deserialize!(typeof(result[0]));
	return result;
}
@trusted
T deserialize_da(T)(in JSONValue json) pure {
	T result;
	foreach(j; json.array) result ~= j.deserialize!(typeof(result[0]));
	return result;
}
T deserialize_struct(T)(in JSONValue json) pure {
	static assert(isAggregateType!T);
	T result;
	alias helper(alias T) = T;
	static foreach(memberName; __traits(allMembers, T)) {{
		alias member = helper!(__traits(getMember, T, memberName));
		static if (!isSomeFunction!(typeof(member))) {
			try {
				mixin("result." ~ memberName ~ " = deserialize!(typeof(T."~memberName~"))(json[\"" ~ memberName ~ "\"]);");
			} catch (Exception e) {
				// nothing, just maybe a report
				//import std.stdio; writeln("member " ~ memberName ~ " not found in JSON");
			}
		}
	}}
	return result;
}

unittest {
	import std.stdio;
	{
		auto aa = ["eins":1, "zwei":2, "drei":3];
		auto json = serialize(aa);
		//json.toString.writeln;
		auto aa2 = deserialize!(typeof(aa))(json);
		assert(aa==aa2);
	}
	{
		struct S {int a = 1; double b = 3.14;}
		auto s = S();
		auto json = serialize(s);
		//json.toString.writeln;
		auto s2 = deserialize!S(json);
		assert(s==s2);
	}
	{
		struct NN {double[] hist; double x = 6.6; string text = "blub";}
		struct N {double x = 5.5; string text = "bla"; NN nn;}
		struct S {int a = 1; double[string] b; N n; int[3] sa=[1,2,3]; double[] da;}
		auto s = S();
		s.da ~= 1.23;
		s.da ~= 4.56;
		s.n.nn.hist = new double[10];
		s.n.nn.hist[] = 1.0;
		auto json = serialize(s);
		//json.toString(JSONOptions.specialFloatLiterals).writeln;
		auto s2 = deserialize!S(json);
		assert(s==s2);
		//s2.writeln;
		JSONValue json2;
		serialize(s2,json2);
		auto s3 = deserialize!S(json2);
		//s3.writeln;
	}
	{
		struct N { int[3] ar=[2,3,4];}
		struct S {
			int a;
			double b;
			string x;
			N n;
		}
		string json_string = `{"a":1,"b":2.0,"c":"extra"}`;
		auto json = parseJSON(json_string);
		auto s = deserialize!S(json);
		//writeln(s);
		serialize(s,json);
		//json.toJSON(true).writeln;
		//serialize(s).toString.writeln;
		//assert(json_string == json.toString);
	}

	{
		class C : PersistentData!JSONValue {
			enum Enum { a, b, c}
			struct Data {
				int a;
				double b;
				Enum e;
				int f(int a) { return a*a;}
			};
			Data persistent;

			void read ( in JSONValue json) { persistent = deserialize!Data(json); }
			void write(ref JSONValue json) { persistent.serialize(json);          }
		}

		auto json = parseJSON(`{"a":1,"b":2,"e":1}`);
		auto my_class = new C;
		auto x = my_class.persistent.f(1);
		my_class.read(json);
		//my_class.persistent.writeln;
		JSONValue new_json;
		my_class.write(new_json);
		//new_json.toJSON(true).writeln;
	}

}
