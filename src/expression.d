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
		while (!expression.empty && expression[0].isAlphaNum) {
			name ~= expression[0];
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

class Number : Expression {
	import std.range, std.string, std.format;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		if (expression.reached_end) throw new Exception("unexpected end");
		char next = expression[0];
		if (next == '(') {
			expression.popFront;
			e = new Sum(expression, parameter_index_lookup);
			if (expression.reached_end) throw new Exception("unexpected end");
			if (expression[0] != ')') throw new Exception("expecting \')\'");
			expression.popFront;
		} else if ((next >= 'a' && next <= 'z') ||
			       (next >= 'A' && next <= 'Z')) {
			e = new Parameter(expression, parameter_index_lookup);
		} else {
			e = new Literal(expression, parameter_index_lookup);
		}
	}
	override double eval(const double[] params = null) const {
		return e.eval(params);
	}
	Expression e;	
}

class Product : Expression {
	import std.range, std.string;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		e1 = new Number(expression, parameter_index_lookup);
		if (expression.reached_end) return;
		op = expression[0];
		switch(op) {
			case '*': case '/': 
				expression.popFront;
				e2 = new Product(expression, parameter_index_lookup); 
			break;
			case '+': case '-': break;
			case ')': break;
			default: throw new Exception("expect \'*\' or \'/\'");
		}
	}
	override double eval(const double[] params = null) const {
		double v1 = e1.eval(params);
		if (e2 is null) return v1;
		double v2 = e2.eval(params);
		if (op == '*') return v1*v2;
		if (op == '/') return v1/v2;
		assert(0);
	}
	char op;
	Expression e1, e2;
}

class Sum : Expression {
	import std.range, std.string;
	this(ref string expression, ref int[string] parameter_index_lookup) {
		e1 = new Product(expression, parameter_index_lookup);
		if (expression.reached_end) return;
		op = expression[0];
		switch(op) {
			case '+': case '-': 
				expression.popFront;
				e2 = new Sum(expression, parameter_index_lookup); 
			break;
			case ')': break;
			default: throw new Exception("expect \'+\' or \'-\'");
		}
	}
	override double eval(const double[] params = null) const {
		double v1 = e1.eval(params);
		if (e2 is null) return v1;
		double v2 = e2.eval(params);
		if (op == '+') return v1+v2;
		if (op == '-') return v1-v2;
		assert(0);
	}
	char op;
	Expression e1, e2;
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


	void testParam(string ex, double[] params, double expected) {
		int[string] parameter_index_lookup;
		const e = new Sum(ex, parameter_index_lookup);
		//import std.stdio;
		//writeln(parameter_index_lookup);
		assert(e.eval(params) == expected);
	}

	testParam("a+a", [1.0], 2.0);
	testParam("eins+zwei", [1.0, 2.0], 3.0);
	testParam("eins+vier/zwei+zwei", [1.0, 4.0, 2.0], 5.0);
	testParam("2*eins+vier/zwei-2*zwei", [1.0, 4.0, 2.0], 0.0);


}