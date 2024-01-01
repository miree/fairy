module expression;
@safe:

import std.stdio;

interface Expression {
	double eval(const double[] params = null) const;
}

bool reached_end(ref string expression) {
	import std.range, std.string;
	expression = expression.stripLeft;
	return expression.empty;
}

class Literal : Expression {
	import std.range, std.string, std.format;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		if (expression.reached_end) throw new Exception("unexpected end");
		expression.formattedRead!"%s"(value);
	}
	override double eval(const double[] params = null) const {
		return value;
	}
	double value;
}

class Parameter : Expression {
	import std.range, std.string, std.format, std.ascii, std.algorithm;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		string name;
		while (!expression.empty && expression.front.isAlphaNum) {
			name ~= expression.front;
			expression.popFront;
		}
		if ((name in parameter_index_lookup) is null) {
			auto indices = parameter_index_lookup.byValue;
			parameter_index_lookup[name] = indices.empty?0:indices.maxElement+1;
		}
		param_idx = parameter_index_lookup[name];
	}
	override double eval(const double[] params = null) const {
		import std.stdio;
		return params[param_idx];
	}
	int param_idx;
}


double gauss(double x, double s) {
	import std.math;
	double x_s = x/s;
	return exp(-0.5*x_s*x_s)/sqrt(2*PI)/s;
}
double step(double x) {
	if (x>=0) return 1.0;
	return 0.0;
}
double window(double x, double w) {
	if (x<0) x = -x;
	if (x>=w/2) return 0;
	return 1;
}
double triangle(double x, double w) {
	if (x<0) x = -x;
	if (x>=w) return 0;
	return 1.0-x/w;
}

enum UnaryFunctionNames = ["sin","cos","tan","asin","acos","atan","exp","log","step"];
enum BinaryFunctionNames = ["atan2","gauss","window","triangle"];
class Function(string name, int argc) : Expression {
	import std.range, std.math;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		if (expression.reached_end) throw new Exception("unexpected end");
		expression = expression[name.length..$];
		if (expression.reached_end) throw new Exception("unexpected end");
		const next = expression.front;
		if (next == '(') {
			for (int arg = 0; arg < argc; ++arg) {
				expression.popFront;
				args ~= new Sum(expression, parameter_index_lookup);
				if (expression.reached_end) throw new Exception("unexpected end");
				if (arg+1 < argc) {
					if (expression.front != ',') throw new Exception("expecting \',\'");				
				} 
			}
			if (expression.front != ')') throw new Exception("expecting \')\'");
			expression.popFront;
		} else throw new Exception("expecting \'(\' after "~name);
	}
	override double eval(const double[] params = null) const {
		static if (argc==1) {
			mixin("return "~name~"(args[0].eval(params));");
		}
		static if (argc==2) {
			mixin("return "~name~"(args[0].eval(params), args[1].eval(params));");
		}
	}
	Expression[] args;	
}

class Number : Expression {
	import std.range, std.string, std.format;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		if (expression.reached_end) throw new Exception("unexpected end");
		const next = expression.front;
		if (expression.front == '(') {
			expression.popFront;
			e = new Sum(expression, parameter_index_lookup);
			if (expression.reached_end) throw new Exception("unexpected end");
			if (expression.front != ')') throw new Exception("expecting \')\'");
			expression.popFront;
			return;
		} 
		static foreach(function_name; BinaryFunctionNames) {
			if (expression.startsWith(function_name)) {
				e = new Function!(function_name,2)(expression, parameter_index_lookup);
				return;
			}
		}
		static foreach(function_name; UnaryFunctionNames) {
			if (expression.startsWith(function_name)) {
				e = new Function!(function_name,1)(expression, parameter_index_lookup);
				return;
			}
		}
		if (expression.front == '-') {
			negative = true;
			expression.popFront;
			if (expression.reached_end) throw new Exception("unexpected end");
		}
		if ((expression.front >= 'a' && expression.front <= 'z') ||
		    (expression.front >= 'A' && expression.front <= 'Z')) {
			e = new Parameter(expression, parameter_index_lookup);
		} else {
			e = new Literal(expression, parameter_index_lookup);
		}			
	}
	override double eval(const double[] params = null) const {
		if (negative) return -e.eval(params);
		return e.eval(params);
	}
	bool negative;
	Expression e;	
}

class Product : Expression {
	import std.range, std.string;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		for (;;) {
			es ~= new Number(expression, parameter_index_lookup);
			if (expression.reached_end) return;
			switch(expression.front) {
				case '*': case '/': 
					ops ~= expression.front;
					expression.popFront;
					if (expression.reached_end) return;
				break;
				case '+': case '-': case ')': case ',': return;
				default: throw new Exception("expect \'*\' or \'/\' found \'"~cast(char)expression.front~"\'");
			}
		}
	}
	override double eval(const double[] params = null) const {
		double result = es[0].eval(params);
		foreach(idx,op; ops) {
			double v2 = es[idx+1].eval(params);
			if (op == '*') result *= v2;
			if (op == '/') result /= v2;
		}
		return result;
	}
	char[] ops;
	Expression[] es;
}

class Sum : Expression {
	import std.range, std.string;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		for (;;) {
			es ~= new Product(expression, parameter_index_lookup);
			if (expression.reached_end) return;
			switch(expression.front) {
				case '+': case '-': 
					ops ~= expression.front;
					expression.popFront;
					if (expression.reached_end) return;
				break;
				case ')': case ',': return;
				default: throw new Exception("expect \'+\' or \'-\' found \'"~cast(char)expression.front~"\'");
			}
		}
	}
	override double eval(const double[] params = null) const {
		double result = es[0].eval(params);
		foreach(idx,op; ops) {
			double v2 = es[idx+1].eval(params);
			if (op == '+') result += v2;
			if (op == '-') result -= v2;
		}
		return result;
	}
	char[] ops;
	Expression[] es;
}

Expression parse_noparam(string expression) {
	import std.range;
	int[string] param_index_lookup;
	auto result = new Sum(expression, param_index_lookup);
	if (!param_index_lookup.empty) throw new Exception("expression has parameters");
	return result;
}
struct Result {
	Expression e;
	int[string] param_index_lookup;
}
Result evaluate(string expression) {
	Result result;
	result.e = new Sum(expression, result.param_index_lookup);
	return result;
}

unittest {

	void testLiteral(string ex, double expected) {
		const e = ex.parse_noparam;
		assert(e.eval == expected);
	}
	testLiteral("2.0", 2.0);
	testLiteral("  2.0 ", 2.0);
	testLiteral("-2.0 ", -2.0);
	testLiteral("	-2.0", -2.0);
	testLiteral("+2.0", 2.0);
	testLiteral("1e2", 1e2);
	testLiteral(".01e-10", .01e-10);

	void testSum(string ex, double expected) {
		import std.stdio;
		const e = ex.parse_noparam;
		assert(e.eval == expected);
	}

	testSum("1+1", 2.0);
	testSum("1+1-1", 1.0);
	testSum("2-(1+1)", 0.0);
	testSum("2*(1+1)", 4.0);
	testSum("2-1-1",0.0);
	testSum("4/2/2",1.0);


	void testParam(string ex, double[] params, double expected) {
		int[string] parameter_index_lookup;
		const e = new Sum(ex, parameter_index_lookup);
		import std.stdio;
		//writeln(e.eval(params), " =? ", expected);
		//writeln(parameter_index_lookup);
		import std.math;
		assert(isClose(e.eval(params),expected));
	}

	testParam("a+a", [1.0], 2.0);
	testParam("eins+zwei", [1.0, 2.0], 3.0);
	testParam("eins+vier/zwei+zwei", [1.0, 4.0, 2.0], 5.0);
	testParam("2*eins+vier/zwei-2*zwei", [1.0, 4.0, 2.0], 0.0);

	import std.math;
	testParam("sin(pi)", [  PI/2], sin(PI/2));
	testParam("sin(pi)", [1*PI/4], sin(1*PI/4));
	testParam("cos(pi)", [3*PI/4], cos(3*PI/4));
	testParam("exp(0.0)", null, exp(0.0));
	testParam("exp(1.0)", null, exp(1.0));
	testParam("exp(2.0)", null, exp(2.0));
	testParam("log(1.0)", null, log(1.0));
	testParam("log(2.0)", null, log(2.0));
	testParam("atan2(2.0,1.0)", null, atan2(2.0,1.0));
	testParam("gauss(1,1)", null, gauss(1,1));

	testParam("1+4/2/2-1-1",null,0.0);

}