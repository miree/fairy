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
import interactive;

class Function : Visual, Item
{
	import expression;
public:
	struct Data{
		@SERIALIZE string definition;
		@SERIALIZE string handles;
		@SERIALIZE double[] parameters;
		@SERIALIZE double[] fitresult;
	}

	struct HandleTree {
		long[2] param_idx; // for x and y coordinates ther is an index into the parameter array where the value of can be found
		HandleTree[] children;
	}
	// flatten the tree into a list of points (not the coordinates but the indices into the parameter array) and links between them from parent to all the children (and grand children)
	void convert_handle_tree(ref HandleTree[] tree) {
		// function is recursive an assumes that the parent was added into the list of indices
		// it then does for all children: add + recurse down, i.e. this is a depth-first traversal 
		void convert_recursive(ref HandleTree node) {
			int parent_idx = cast(int)handle_param_indices.length-1; // remember the index of the parent
			foreach(child; node.children) {
				handle_param_indices ~= child.param_idx;       
				// add the link from parent to child
				int child_idx = cast(int)handle_param_indices.length-1;
				handle_links ~= [parent_idx, child_idx];
				// add the child and recurse down
				convert_recursive(child);
			}
		}
		foreach(node; tree) {
			handle_param_indices ~= node.param_idx;
			convert_recursive(node);
		}
	}
	// syntax is like this [x0,y0]([x1,y1][x2,y2]([x3,y3]))[x4,y4]
	//            for loop ^      ^recursive-descent       ^ 
	HandleTree[] parse_handles(ref string definition, ref expression.Result expr) {
		import std.algorithm;
		HandleTree[] nodes;
		for (;;) {
			if (definition[0] != '[') throw new Exception("handle definition must start with \'[\'");
			// find the strings
			auto comma_pos = definition[0..$].countUntil(',');
			auto closing_pos = definition[0..$].countUntil(']');
			string x_definition = definition[1..comma_pos];
			string y_definition = definition[comma_pos+1..closing_pos];

			// map strings to indices in parameter array
			nodes ~= HandleTree();
			auto index0 = x_definition in expr.param_index_lookup;
			if (index0 is null) throw new Exception("unknown parameter (" ~ x_definition ~ ") in handle definition: " ~ definition);
			nodes[$-1].param_idx[0] = *index0;
			auto index1 = y_definition in expr.param_index_lookup;
			if (index1 is null) throw new Exception("unknown parameter (" ~ y_definition ~ ") in handle definition: " ~ definition);
			nodes[$-1].param_idx[1] = *index1;

			// termination
			definition = definition[closing_pos+1..$]; // eat up the [x,y] part
			// parse children if any are present
			if (definition.length == 0) break;
			if (definition[0] == ')') { // end of recursive call
				definition = definition[1..$];
				return nodes;
			}
			if (definition[0] == '[') continue;

			// recursion
			if (definition[0] == '(') {
				if (definition.length < 2) throw new Exception("unexpected end of handle definition \"" ~ definition ~ "\"");
				definition = definition[1..$]; // eat up opening '('
				nodes[$-1].children = parse_handles(definition, expr); // recursive call eats up all between '(' and ')'
				if (definition.length == 0) break;
				if (definition[0] != ')') throw new Exception("missing \')\' after \'(\' handle definition");
				definition = definition[1..$]; // eat up closing ')'
				if (definition.length == 0) break;
				continue;
			}
			throw new Exception("unexpected character in handle definition: " ~ definition);
		}
		return nodes;
	}

	void create_interactive_handles(string handles_definition) {
		is_interactive = true;
		// deal with the definition of parameter handles for user interactions
		parameter_deltas.length = data.parameters.length;
		foreach(ref d; parameter_deltas) d = 0.0;
		auto tree = parse_handles(handles_definition, expr);
		// convert the tree into a list of parameter references (indices into the parmater array) and a list of links from parent to child (indices into the former list)
		convert_handle_tree(tree);
		// convert the paramter references into actual double values
		handle_points.length = handle_param_indices.length;
		foreach(i, indices; handle_param_indices) {
			double x = data.parameters[indices[0]];
			double y = data.parameters[indices[1]];
			handle_points[i][] = [x,y][];
		}
		foreach(link; handle_links) {
			handle_points[link[1]][] += handle_points[link[0]][];
		}
		handle_deltas.length = handle_points.length;
		foreach(ref delta; handle_deltas) delta = [0,0];
	}

	this(string function_definition, double[string] parameters, string handle_definition) { 
		data.definition = function_definition;
		data.handles    = handle_definition;
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
		if (handle_definition !is null || handle_definition.length) create_interactive_handles(handle_definition.dup);
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
			expr = expression.evaluate(data.definition);
			if (data.handles.length) create_interactive_handles(data.handles.dup);
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


	void fit(FitDataSource source, double[2] region, bool verbose = true) {
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
		foreach(parameter_name,idx;expr.param_index_lookup) {
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i;

			if (verbose) writefln("%10s (par %s) = %10s +- %10s",parameter_name,i,fitter.result_params[i], fitter.result_errors[i]);
			else         write(fitter.result_params[i], " ", fitter.result_errors[i], " ");

			data.fitresult[i] = fitter.result_params[i];
		}
		if (!verbose) writeln;

	}



	void fit_loglikelihood(FitDataSource source, double[2] region, bool verbose = true) {
		import multifit_nlin;
		import std.algorithm, std.array;

		auto datapoints = source.get_data(region).map!(xyd=>Dp!double(xyd[0],xyd[1],xyd[2])).array;
		//import std.stdio;
		//writeln(datapoints);
		import std.stdio;
		if (verbose) writeln("fit with ", datapoints.length, " points");

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
		auto fitter = MultifitNlin!(double,typeof(fitdelegate),typeof(&loglikelihood))(fitdelegate, datapoints, fit_params, verbose, &loglikelihood);
		fitter.run();
		foreach(parameter_name,idx;expr.param_index_lookup) {
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i;

			if (verbose) writefln("%10s (par %s) = %10s +- %10s",parameter_name,i,fitter.result_params[i], fitter.result_errors[i]);
			else         write(fitter.result_params[i], " ", fitter.result_errors[i], " ");

			data.fitresult[i] = fitter.result_params[i];
		}		
		if (!verbose) writeln;

	}


private:
	ulong item_version = 0;
	Data data;
	expression.Result expr;

	// these are used to create handles for user interaction with function parameters
	  long[2][] handle_param_indices;
	  int [2][] handle_links;
	double[2][] handle_points;
	double[2][] handle_deltas;
	double[] parameter_deltas;

	bool is_interactive = false;
}



class FunctionVisualizer : HierarchicalPointsVisualizer
{
	Function funct;

public:

	import std.stdio;
	this(Function func)
	{
		funct = func;
		super(func.item_version, func.handle_points, func.handle_links, func.handle_deltas);
	}
	import graphics, transform;

	override string getXlabel() {
		return "x";
	}
	override string getYlabel() {
		return funct.data.definition;
	}

	override void draw(BackendInterface d, in Transform[3] t) const
	{
		import std.algorithm;
		auto local_fitresults = funct.data.fitresult.dup;  
		auto local_parameters = funct.data.parameters.dup; 
		if (funct.is_interactive) local_parameters[] += funct.parameter_deltas[];
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
					//funct.data.parameters[x_idx] = x;
					//y = funct.expr.e.eval(funct.data.parameters);
					local_parameters[x_idx] = x;
					y = funct.expr.e.eval(local_parameters);
				} else {
					//funct.data.fitresult[x_idx] = x;
					//y = funct.expr.e.eval(funct.data.fitresult);					
					local_fitresults[x_idx] = x;
					y = funct.expr.e.eval(local_fitresults);					
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
		super.draw(d,t);
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


	//override BoundingBox interactMouseMotion(double mouse_world_x, double mouse_world_y, in Transform[3] t) {
	//	return handles.interactMouseMotion(mouse_world_x, mouse_world_y, t);
	//}
	//override bool setHighlightHandle(long handle) {
	//	return handles.setHighlightHandle(handle);	
	//}
	//override void select(long handle, bool add_or_remove = false) {
	//	handles.select(handle, add_or_remove);
	//}
	//override void select_box(double x1, double y1, double x2, double y2, in Transform[3] t, bool add, bool remove) {
	//	handles.select_box(x1,y1, x2,y2, t, add, remove);
	//}
	override void drag(long handle, double x_canvas_start, double y_canvas_start, double x_canvas, double y_canvas, in Transform[3] t, bool ctrl = false, bool shift = false, bool end = false) {
		if (funct.is_interactive == false) return;
		if (end) {
			auto true_deltas = super.deltas.dup;
			foreach(link; funct.handle_links) {
				true_deltas[link[1]][] -= deltas[link[0]][];
			}
			foreach(i, indices; funct.handle_param_indices) {
				funct.data.parameters[indices[0]] += true_deltas[i][0];
				funct.data.parameters[indices[1]] += true_deltas[i][1];
				funct.parameter_deltas[indices[0]] = 0.0;
				funct.parameter_deltas[indices[1]] = 0.0;
			}
			super.drag(handle, x_canvas_start, y_canvas_start, x_canvas, y_canvas, t, ctrl, shift, end);
		} else {
			super.drag(handle, x_canvas_start, y_canvas_start, x_canvas, y_canvas, t, ctrl, shift, end);
			//import std.stdio;
			//writeln(funct.handle_links, "       ", super.deltas);
			auto true_deltas = super.deltas.dup;
			foreach(link; funct.handle_links) {
				true_deltas[link[1]][] -= deltas[link[0]][];
			}
			foreach(i, indices; funct.handle_param_indices) {
				funct.parameter_deltas[indices[0]] = true_deltas[i][0];
				funct.parameter_deltas[indices[1]] = true_deltas[i][1];
			}

		}
	}




}