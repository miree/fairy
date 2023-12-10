module functions;
@safe:

import item;
import std.json;
import serializeJSON;

interface FitDataSource {
	double[3][] get_data(double[2] region);
}

class FunctionFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Function(json);
	}
}

import graphics;

class Function : Visual, Item
{
	import expression;
public:
	struct Data{
		@SERIALIZE string definition;
		@SERIALIZE double[] parameters;
		@SERIALIZE double[] fitresult;

	}
	this(string function_definition, double[string] parameters) { 
		data.definition = function_definition;
		expr = expression.evaluate(data.definition);

		string[] missing_parameters;
		foreach(par_name; expr.param_index_lookup.byKey) {
			if ((par_name in parameters) is null) missing_parameters ~= par_name;
		}
		import std.array;
		if (missing_parameters.length > 0) throw new Exception("missing start parmeters for: " ~ missing_parameters.join(", "));

		data.parameters = new double[](expr.param_index_lookup.length);
		data.fitresult = new double[](expr.param_index_lookup.length);
		foreach(par_name, par_value; parameters) {
			if ((par_name in expr.param_index_lookup) is null) {
				import std.stdio;
				writeln("warning: parameter ", par_name, " not found in function definition");
				continue;
			}
			const idx = expr.param_index_lookup[par_name];
			data.parameters[idx] = par_value;
			data.fitresult[idx] = par_value;
		}
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
			expr = expression.evaluate(data.definition);
		} catch(Exception e) {
			writeln("Function deserialize error: ", e.msg);
		} 
	}
	override JSONValue toJSON()  { return serialize(data); }
	override string get_type()  {
		return "functions.Function";
	}
	override void reset() {
	}
	override ulong getVersion() {
		return item_version;
	}
	override void overrideVersion(ulong new_version) {
		item_version = new_version;
	}

	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) 
	{
		return new FunctionVisualizer(this);
	}


	void fit(FitDataSource source, double[2] region) {
		import multifit_nlin;
		import std.algorithm, std.array;

		auto datapoints = source.get_data(region).map!(xyd=>Dp!double(xyd[0],xyd[1],xyd[2])).array;

		import std.stdio;
		writeln("fit with ", datapoints.length, " points");

		const x_idx = expr.param_index_lookup["x"];
		double[] all_params = data.parameters.dup;
		auto fitdelegate = delegate double(double x, double[] pars) {
			foreach(i; 0..x_idx) all_params[i] = pars[i];
			all_params[x_idx] = x;
			foreach(i; x_idx+1 ..all_params.length) all_params[i] = pars[i-1];
			return expr.e.eval(all_params);
		};
		double[] fit_params;
		foreach(i,par; all_params) {
			if (i != x_idx) {
				fit_params ~= par;
			}
		}
		auto fitter = MultifitNlin!(double,typeof(fitdelegate))(fitdelegate, datapoints, fit_params, true);
		fitter.run();
		foreach(i,rpar; fitter.result_params) {
			if (i<x_idx) {
				data.fitresult[i] = rpar;
			} else {
				data.fitresult[i+1] = rpar;
			}
		}	

	}


private:
	ulong item_version = 0;
	Data data;
	expression.Result expr;
}




class FunctionVisualizer : Visualizer 
{
	Function funct;
public:

	import std.stdio;
	this(Function func)
	{
		funct = func;
		ulong dim;
		super(func.item_version, dim=1);
	}
	import graphics, transform;
	@trusted override void draw(BackendInterface d, in Transform[3] t)   
	{
		import std.algorithm;
		for (int n = 0; n < 2; ++n) {
			if (n == 0) {
				d.set_color(0,0.3,0);
				d.set_line_width(4);				
			} else {
				d.set_color(0,0,0.3);
				d.set_line_width(4);								
			}

			const points = 1000;
			double left  = t[0].min;
			double right = t[0].max;
			// function does not depend on x
			if (("x" in funct.expr.param_index_lookup) is null) {
				double y = funct.expr.e.eval(funct.data.parameters);
				d.line(t[0].world2canvas(left) , t[1].world2canvas(t[1].log(y)), 
					   t[0].world2canvas(right), t[1].world2canvas(t[1].log(y)));
				d.stroke();
				continue;
			}
			// function does depend on x
			auto x_idx = funct.expr.param_index_lookup["x"];
			double x_old, y_old;
			foreach(i;0..points+1) {
				double x = t[0].exp(left+i*(right-left)/points);
				double y;
				if (n == 0) {
					funct.data.parameters[x_idx] = x;
					y = funct.expr.e.eval(funct.data.parameters);
				} else {
					funct.data.fitresult[x_idx] = x;
					y = funct.expr.e.eval(funct.data.fitresult);					
				}
				if (i>0) {
					d.line(t[0].world2canvas(t[0].log(x_old)),t[1].world2canvas(t[1].log(y_old)), 
						   t[0].world2canvas(t[0].log(x)),    t[1].world2canvas(t[1].log(y)));
				}
				x_old = x;
				y_old = y;
			}
			d.stroke();

		}
	}

	override double getValue(double x, double y) {
		// function does not depend on x
		if (("x" in funct.expr.param_index_lookup) is null) {
			return funct.expr.e.eval(funct.data.parameters);
		}
		auto x_idx = funct.expr.param_index_lookup["x"];
		funct.data.parameters[x_idx] = x;
		return funct.expr.e.eval(funct.data.parameters);
	}

	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) {
		import std.algorithm;
		const points = 1000;
		double ymin, ymax;
		if (("x" in funct.expr.param_index_lookup) is null) {
			double y = funct.expr.e.eval(funct.data.parameters);
			bt[0] = t[1].log(y);
			bt[1] = t[1].log(y);
			return true;
		}
		auto x_idx = funct.expr.param_index_lookup["x"];
		foreach(i;0..points+1) {
			double x = t[0].exp(lr[0]+i*(lr[1]-lr[0])/points);
			funct.data.parameters[x_idx] = x;
			double y = funct.expr.e.eval(funct.data.parameters);
			if (ymin is double.init) ymin = t[1].log(y);
			if (ymax is double.init) ymax = t[1].log(y);
			ymin = min(ymin,t[1].log(y));
			ymax = max(ymax,t[1].log(y));
		}
		bt[0] = ymin;
		bt[1] = ymax;
		if (ymin !is double.init && ymax !is double.init) return true;
		return false;
	}

}