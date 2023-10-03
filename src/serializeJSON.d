module serializeJSON;
@safe:

public import std.json;
import std.traits;


struct SERIALIZE {}
bool isSERIALIZEd(T, alias membername)(in T t) {
	foreach (attr; __traits(getAttributes, __traits(getMember,t,membername))) {
		static if (is(attr==SERIALIZE)) return true;
	}
	return false;
}


auto serialize(T)(in T data) {
	JSONValue json;
	serialize!T(data,json);
	return json;
}
void serialize(T)(in T data, ref JSONValue json) {
	static      if (isAssociativeArray!T) serialize_aa!(KeyType!T,ValueType!T)(data,json);
	else static if (isStaticArray!T)      serialize_sa!(T)(data,json);
	else static if (isDynamicArray!T)     serialize_da!(T)(data,json);
	else static if (isAggregateType!T)    serialize_struct!T(data,json);
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

void serialize_sa(T)(in T data, ref JSONValue json) pure {
	JSONValue[] jsons;
	foreach(a; data) jsons ~= serialize(a);
	json = JSONValue(jsons);
}
void serialize_da(T)(in T data, ref JSONValue json) pure {
	JSONValue[] jsons;
	foreach(a; data) jsons ~= serialize(a);
	json = JSONValue(jsons);
}
void serialize_aa(K,V)(in V[K] data, ref JSONValue json) pure {
	foreach(k,v; data) json[k] = serialize(v); 
}


void serialize_struct(T)(in T structure, ref JSONValue json) {
	import std.json;
	import std.traits;
	alias helper(alias T) = T;
	static foreach(memberName; __traits(allMembers, T)) {{
		alias member = helper!(__traits(getMember, T, memberName));
		static if (!isSomeFunction!(typeof(member))) {
			if (isSERIALIZEd!(T,memberName)(structure)) {
				JSONValue member_json;
				mixin("serialize(structure." ~ memberName ~ ", member_json);");
				json[memberName] = member_json;
			}
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
			if (isSERIALIZEd!(T,memberName)(result)) {
				try {
					//pragma(msg,"result." ~ memberName ~ " = deserialize!(typeof(T."~memberName~"))(json[\"" ~ memberName ~ "\"]);" );
					mixin("result." ~ memberName ~ " = deserialize!(typeof(T."~memberName~"))(json[\"" ~ memberName ~ "\"]);");
				} catch (Exception e) {
					// nothing, just maybe a report
					//import std.stdio; writeln("member " ~ memberName ~ " not found in JSON");
				}
			}
		}
	}}
	return result;
}

unittest {
	import std.stdio;
	{
		auto aa = ["eins":1, "zwei":2, "drei":3] ;
		struct S {
			@SERIALIZE int[] a;
			           int b;
			@SERIALIZE double c = 1.0;
		}

		S s;
		//__traits(getMember,S,"a") = 1;
		//static foreach(mem; __traits(allMembers, S)) {{
		//	mem.write; " ".write; isSERIALIZEd!(S,mem)(s).writeln;
		//}}
		auto json = serialize(aa);
		//json.toString(JSONOptions.specialFloatLiterals).writeln;
		auto aa2 = deserialize!(typeof(aa))(json);
		assert(aa==aa2);

		auto json2 = serialize(s);
		//json2.toString(JSONOptions.specialFloatLiterals).writeln;
		S s2 = deserialize!(typeof(s))(json2);
		assert(s == s2);
	}


	{
		struct S {
			@SERIALIZE int a = 1; 
			@SERIALIZE double b = 3.14;
		}
		auto s = S();
		auto json = serialize(s);
		//json.toString.writeln;
		auto s2 = deserialize!S(json);
		assert(s==s2);
	}
	{
		struct NN {
			@SERIALIZE double[] hist; 
			@SERIALIZE double x = 6.6; 
			@SERIALIZE string text = "blub";
		}
		struct N {
			@SERIALIZE double x = 5.5; 
			@SERIALIZE string text = "bla"; 
			@SERIALIZE NN nn;
			           NN nn2;
		}
		struct S {
			@SERIALIZE int a = 1; 
			@SERIALIZE double[string] b; 
			@SERIALIZE N n; 
			@SERIALIZE int[3] sa=[1,2,3]; 
			@SERIALIZE double[] da;
		}
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
		struct N { 
			@SERIALIZE int[3] ar=[2,3,4];
			double d = 1.0;
		}
		struct S {
			@SERIALIZE int a;
			@SERIALIZE double b;
			           double b2;
			@SERIALIZE string x;
			@SERIALIZE N n;
			@SERIALIZE N[3] na;
			@SERIALIZE N[] da;
			@SERIALIZE N[string] aa;
			           double b3;
		}
		string json_string = `{"a":1,"b":2.0,"c":"extra"}`;
		auto json = parseJSON(json_string);
		auto s = deserialize!S(json);
		//writeln(s);
		s.aa["hallo"] = N();
		serialize(s,json);
		json.toString(JSONOptions.specialFloatLiterals).writeln;

		s.writeln;
		S s2 = deserialize!S(json);
		s2.writeln;
		//json.toJSON(true).writeln;
		//assert(serialize(s).toString(JSONOptions.specialFloatLiterals) == `{"a":1,"b":2.0,"n":{"ar":[2,3,4]},"x":""}`);
		//assert(json_string == json.toString);
	}

}
