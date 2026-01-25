module functions;
@safe:

import item;
import std.json;
import serializeJSON;


interface FitDataSource {
	double[3][] get_data(double[2] region);
	double get_bin_width();
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
		@SERIALIZE string   definition;
		@SERIALIZE string   handles;
		@SERIALIZE string   hist1dname;
		@SERIALIZE string   gate1dname;
		@SERIALIZE string[] results;       // result expressions defined by the user
		@SERIALIZE double[] result_values; // numerical value of the result expression after the fit
		@SERIALIZE double[] result_errors; // numerial error of the result expression after the fit
		@SERIALIZE bool     dragupdate;
		@SERIALIZE bool     loglikelihood; // if true performs log likelihood fit instead of chisquare fit
		@SERIALIZE double[] parameters;
		@SERIALIZE double[] fitresult;
		@SERIALIZE double   result_red_chi_sqr;
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

	//// helper function to calculate result values from fit parameters and some formulas
	//void calculate_results() {
	//	foreach(result_formula; data.results) {

	//	}
	//}


	this(string function_definition, double[string] parameters, string handle_definition, string hist, string gate, string[] results, bool dragupdate, bool loglikelihood) { 
		data.definition  = function_definition;
		data.handles     = handle_definition;
		data.hist1dname  = hist;
		data.gate1dname  = gate;
		data.results     = results;
		data.dragupdate  = dragupdate;
		data.loglikelihood = loglikelihood;
		expr = expression.evaluate(data.definition);
		import std.stdio;
		//writeln("loglikelihood = ", loglikelihood);
		// prepare display of results after fitting
		foreach(result_expr; results) {
			import std.algorithm, std.array;
			if (!result_expr.canFind('=')) throw new Exception("missing '=' in expression " ~ result_expr);
			result_exprs ~= expression.evaluate(result_expr.split('=')[1]);
		}
		data.result_values.length  = results.length;
		data.result_errors.length  = results.length;
		result_params.length        = results.length;
		result_derivatives.length   = results.length;
		result_param_indices.length = results.length;

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

			// prepare display of results after fitting
			foreach(result_expr; data.results) {
				import std.algorithm, std.array;
				if (!result_expr.canFind('=')) throw new Exception("missing '=' in expression " ~ result_expr);
				result_exprs ~= expression.evaluate(result_expr.split('=')[1]);
			}
			data.result_values.length   = data.results.length;
			data.result_errors.length   = data.results.length;
			result_params.length        = data.results.length;
			result_derivatives.length   = data.results.length;
			result_param_indices.length = data.results.length;

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



	void fit(FitDataSource source, double[2] region, bool verbose = true, bool quiet = false, bool with_deltas = false, int max_steps=250) {
		import multifit_nlin;
		import std.algorithm, std.array;

		auto datapoints = source.get_data(region).map!(xyd=>Dp!double(xyd[0],xyd[1],xyd[2])).array;

		import std.stdio;

		const x_idx = expr.param_index_lookup["x"];
		double[] all_params = data.parameters.dup; // original set of parameters. What is actually used as fit paramters is an array of 1.0
		double[] all_params_mod = data.parameters.dup; // each fit parameter is then multiplied with all_params during function execution and stored here (modified parameters)
													   // this is necessary because the GSL-fitter becomes unreliable if the paramteres are too big 

		if (datapoints.length < all_params.length) {
			writeln("not enough datapoints. not fit");
			return;
		}

		if (with_deltas) {
			all_params[]     += parameter_deltas[];
			all_params_mod[] += parameter_deltas[];
		}

		auto fitdelegate = delegate double(double x, double[] pars) {
			foreach(i; 0..x_idx) all_params_mod[i] = all_params[i]*pars[i];
			all_params_mod[x_idx] = x;
			foreach(i; x_idx+1 ..all_params.length) all_params_mod[i] = all_params[i]*pars[i-1];
			return expr.e.eval(all_params_mod);
		};
		double[] fit_params;
		foreach(i,ref par; all_params) {
			if (i != x_idx) {
				import std.math;
				if (abs(par) > 1) { // do the parameter rescaling only for parameters > 1. Small parameters are handled by GSL well and if we happen to have 0 as start parameter that rescaling doesn't  work
					//fit_params ~= par;
					fit_params ~= 1.0; // initialze all fit parameters with 1.0. These will be multiplied with the actual start parameter before evaluating the function
				} else {
					fit_params ~= par;
					par = 1.0;
				}
			}
		}
		auto fitter = MultifitNlin!(double,typeof(fitdelegate))(fitdelegate, datapoints, fit_params, false);
		fitter.run(max_steps);
		if (verbose) writeln("Fit Results:");
		foreach(parameter_name,idx;expr.param_index_lookup) { // idx is the index into the parameter array of the function definition expression "expr" (which includes "x")
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i; // i is the index into the fit parameter array (which doesn't include "x")

			if (verbose) writefln("%10s (par %s) = %10s +- %10s   [ %s %%]",parameter_name,i,fitter.result_params[i]*all_params[idx], fitter.result_errors[i]*all_params[idx], 100*fitter.result_errors[i]*all_params[idx]/(fitter.result_params[i]*all_params[idx]));
			else if (!quiet) write(fitter.result_params[i]*all_params[idx], " ", fitter.result_errors[i]*all_params[idx], " ");

			// now look in each of the result expressions "result_exprs" if the parameter "parameter_name" occurs in there
			// if yes: copy the fitresult (corrected for rescaling) into the "result_pars" array at the position that matches the "parameter_name" of the function definition expression (outer loop)
			foreach(index, ref result_pars; result_params) {
				auto par = parameter_name in result_exprs[index].param_index_lookup;
				if (par !is null) {
					//import std.stdio;
					//writeln("found parameter ", parameter_name, " in result expression ", data.results, " at index ", result_exprs[index].param_index_lookup[parameter_name], " and it hast value ", fitter.result_params[i]*all_params[idx]);
					result_pars.length = result_exprs[index].param_index_lookup.length;
					result_pars[result_exprs[index].param_index_lookup[parameter_name]] = fitter.result_params[i]*all_params[idx]; // assign the numerical value to the paramter that occurs in the result expression

					result_param_indices[index].length = result_exprs[index].param_index_lookup.length;
					result_param_indices[index][result_exprs[index].param_index_lookup[parameter_name]] = i;
				}
				auto bin_width_par = "binwidth" in  result_exprs[index].param_index_lookup;
				if (bin_width_par !is null) {
					result_pars.length = result_exprs[index].param_index_lookup.length;
					result_pars[result_exprs[index].param_index_lookup["binwidth"]] = source.get_bin_width();

					result_param_indices[index].length = result_exprs[index].param_index_lookup.length;
					result_param_indices[index][result_exprs[index].param_index_lookup["binwidth"]] = -1; // -1 is a made-up index for the binwidth (which is not a fit parameter and has no error)
				}
			}
		}
		if (!verbose && !quiet) writeln;
		else if (verbose || !quiet) writeln("=============== Covariance Matrix =================");

		// calculate covariance matrix (it to be corrected because of the parameter rescaling)
		fitter.calc_covar();
		auto covar = fitter.result_covar();
		if (verbose) {
			foreach(parameter_name2,idx2;expr.param_index_lookup) {
				if (idx2==x_idx) continue;
				uint j = idx2;
				if (idx2>x_idx) --j;
				if (verbose) writef("%20s",parameter_name2);
			}
			writeln();
		}
		foreach(parameter_name,idx;expr.param_index_lookup) {
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i;

			foreach(parameter_name2,idx2;expr.param_index_lookup) {
				if (idx2==x_idx) continue;
				uint j = idx2;
				if (idx2>x_idx) --j;
				covar[i][j] *= all_params[idx] * all_params[idx2];
				if (verbose) writef("%20s",covar[i][j]);
			}
			if (verbose) writeln();
		}
		if (verbose) writeln("================ Correlation Matrix =================");
		foreach(parameter_name,idx;expr.param_index_lookup) {
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i;

			foreach(parameter_name2,idx2;expr.param_index_lookup) {
				if (idx2==x_idx) continue;
				uint j = idx2;
				if (idx2>x_idx) --j;
				import std.math;
				if (verbose) writef("%20s",covar[i][j]/sqrt(covar[i][i]*covar[j][j]));
			}
			if (verbose) writeln();
		}
		if (verbose) writeln("================");


		// copy result parameters back into our local array
		foreach(i,rpar; fitter.result_params) {
			if (i<x_idx) {
				data.fitresult[i] = rpar*all_params[i];
			} else {
				data.fitresult[i+1] = rpar*all_params[i+1];
			}
		}

		// calculate the resulting qantities as function of parameters
		foreach(index, ref result_expr; result_exprs) {
			data.result_values[index] = result_expr.e.eval(result_params[index]);
			// compute the errors of the result expression : dfunc = sqrt( sum_ij result_cov[i][j] * df_di * df_dj );

			// get the first derivative of the result expression for each parameter
			import std.stdio;
			//writeln("derivatives of ", data.results[index]);
			result_derivatives[index].length = result_params[index].length;
			foreach(i,ref rpar; result_params[index]) {
				string parname;
				import std.array,std.range,std.algorithm;
				foreach(e;result_expr.param_index_lookup.byKeyValue) if (e.value==i) parname=e.key;
				//write(i, ":",parname,"(", rpar, ") : ");
				double rpar_1 = rpar;
				double result_value_1 = data.result_values[index];
				rpar *= 1.001; // make a 1 permil shift
				double rpar_2         = rpar;
				double result_value_2 = result_expr.e.eval(result_params[index]);
				double derivative = (result_value_2-result_value_1)/(rpar_2-rpar_1);
				result_derivatives[index][i] = derivative;
				rpar = rpar_1; // 'repair' the modified parameter
				//writeln(derivative);
			}
			//writeln("------------------");
			//writeln("computing the error using derivatives and covariance matrix");
			data.result_errors[index] = 0;
			foreach(i; 0..result_params[index].length) {
				auto idx_i = result_param_indices[index][i];
				if (idx_i == -1) continue; // skip the "binwidth" parameter
				foreach(j; 0..result_params[index].length) {
					auto idx_j = result_param_indices[index][j];
					if (idx_j == -1) continue; // skip the "binwidth" parameter
					double covar_ij = covar[idx_i][idx_j];
					//writeln("covar ", i, " ", j, " (",idx_i,",",idx_j,")  = ", covar_ij);
					data.result_errors[index] +=  covar_ij * result_derivatives[index][i] * result_derivatives[index][j];
				}
			}
			import std.math;
			//writeln("error = ", sqrt(data.result_errors[index]));
			//writeln("====================");
			data.result_errors[index] = sqrt(data.result_errors[index]);


			//import std.stdio;
			//writeln("result ", index, " params ", result_params[index], " expression " , data.results[index]  ,"  result value ", data.result_values[index]);
		}
		auto fitresults = data.fitresult.dup;
		double red_chisqr = 0; // vairance of the residuals
		foreach(datapoint; datapoints) {
			double yi = datapoint.v;
			fitresults[x_idx] = datapoint.c;
			double fi = expr.e.eval(fitresults);
			double delta = (yi-fi)/datapoint.s;
			//writeln(delta);
			red_chisqr += delta*delta;
		}
		import std.math;
		red_chisqr /= (datapoints.length-fit_params.length); // variance of residuals 
		if (verbose) writeln("variance of residuals (Chi^2/ndf) = ", red_chisqr, "    rms of residuals = ", sqrt(red_chisqr));
		data.result_red_chi_sqr = red_chisqr;
		if (verbose) {
			foreach(idx,value; data.result_values) {
				import std.conv;
				import std.stdio;
				import std.format;
				import std.array;
				if (value is double.init) continue;
				writefln("%20s : %20s +- %20s [ %s %%]",data.results[idx].split('=')[0], value, data.result_errors[idx], 100*data.result_errors[idx]/value, );
			}			
		}
	}

	void fit_loglikelihood(FitDataSource source, double[2] region, bool verbose = true, bool quiet = false, bool with_deltas = false, int max_steps=250) {
		import multifit_nlin;
		import std.algorithm, std.array;

		auto datapoints = source.get_data(region).map!(xyd=>Dp!double(xyd[0],xyd[1],xyd[2])).array;

		import std.stdio;

		const x_idx = expr.param_index_lookup["x"];
		double[] all_params = data.parameters.dup; // original set of parameters. What is actually used as fit paramters is an array of 1.0
		double[] all_params_mod = data.parameters.dup; // each fit parameter is then multiplied with all_params during function execution and stored here (modified parameters)
													   // this is necessary because the GSL-fitter becomes unreliable if the paramteres are too big 

		if (datapoints.length < all_params.length) {
			writeln("not enough datapoints. not fit");
			return;
		}

		if (with_deltas) {
			all_params[]     += parameter_deltas[];
			all_params_mod[] += parameter_deltas[];
		}

		auto fitdelegate = delegate double(double x, double[] pars) {
			foreach(i; 0..x_idx) all_params_mod[i] = all_params[i]*pars[i];
			all_params_mod[x_idx] = x;
			foreach(i; x_idx+1 ..all_params.length) all_params_mod[i] = all_params[i]*pars[i-1];
			return expr.e.eval(all_params_mod);
		};
		double[] fit_params;
		foreach(i,ref par; all_params) {
			if (i != x_idx) {
				import std.math;
				if (abs(par) > 1) { // do the parameter rescaling only for parameters > 1. Small parameters are handled by GSL well and if we happen to have 0 as start parameter that rescaling doesn't  work
					//fit_params ~= par;
					fit_params ~= 1.0; // initialze all fit parameters with 1.0. These will be multiplied with the actual start parameter before evaluating the function
				} else {
					fit_params ~= par;
					par = 1.0;
				}
			}
		}
		auto fitter = MultifitNlin!(double,typeof(fitdelegate),typeof(&loglikelihood))(fitdelegate, datapoints, fit_params, false, &loglikelihood);
		fitter.run(max_steps);
		if (verbose) writeln("Fit Results:");
		foreach(parameter_name,idx;expr.param_index_lookup) { // idx is the index into the parameter array of the function definition expression "expr" (which includes "x")
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i; // i is the index into the fit parameter array (which doesn't include "x")

			if (verbose) writefln("%10s (par %s) = %10s +- %10s   [ %s %%]",parameter_name,i,fitter.result_params[i]*all_params[idx], fitter.result_errors[i]*all_params[idx], 100*fitter.result_errors[i]*all_params[idx]/(fitter.result_params[i]*all_params[idx]));
			else if (!quiet) write(fitter.result_params[i]*all_params[idx], " ", fitter.result_errors[i]*all_params[idx], " ");

			// now look in each of the result expressions "result_exprs" if the parameter "parameter_name" occurs in there
			// if yes: copy the fitresult (corrected for rescaling) into the "result_pars" array at the position that matches the "parameter_name" of the function definition expression (outer loop)
			foreach(index, ref result_pars; result_params) {
				auto par = parameter_name in result_exprs[index].param_index_lookup;
				if (par !is null) {
					//import std.stdio;
					//writeln("found parameter ", parameter_name, " in result expression ", data.results, " at index ", result_exprs[index].param_index_lookup[parameter_name], " and it hast value ", fitter.result_params[i]*all_params[idx]);
					result_pars.length = result_exprs[index].param_index_lookup.length;
					result_pars[result_exprs[index].param_index_lookup[parameter_name]] = fitter.result_params[i]*all_params[idx]; // assign the numerical value to the paramter that occurs in the result expression

					result_param_indices[index].length = result_exprs[index].param_index_lookup.length;
					result_param_indices[index][result_exprs[index].param_index_lookup[parameter_name]] = i;
				}
				auto bin_width_par = "binwidth" in  result_exprs[index].param_index_lookup;
				if (bin_width_par !is null) {
					result_pars.length = result_exprs[index].param_index_lookup.length;
					result_pars[result_exprs[index].param_index_lookup["binwidth"]] = source.get_bin_width();

					result_param_indices[index].length = result_exprs[index].param_index_lookup.length;
					result_param_indices[index][result_exprs[index].param_index_lookup["binwidth"]] = -1; // -1 is a made-up index for the binwidth (which is not a fit parameter and has no error)
				}
			}
		}
		if (!verbose && !quiet) writeln;
		else if (verbose || !quiet) writeln("=============== Covariance Matrix =================");

		// calculate covariance matrix (it to be corrected because of the parameter rescaling)
		fitter.calc_covar();
		auto covar = fitter.result_covar();
		if (verbose) {
			foreach(parameter_name2,idx2;expr.param_index_lookup) {
				if (idx2==x_idx) continue;
				uint j = idx2;
				if (idx2>x_idx) --j;
				if (verbose) writef("%20s",parameter_name2);
			}
			writeln();
		}
		foreach(parameter_name,idx;expr.param_index_lookup) {
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i;

			foreach(parameter_name2,idx2;expr.param_index_lookup) {
				if (idx2==x_idx) continue;
				uint j = idx2;
				if (idx2>x_idx) --j;
				covar[i][j] *= all_params[idx] * all_params[idx2];
				if (verbose) writef("%20s",covar[i][j]);
			}
			if (verbose) writeln();
		}
		if (verbose) writeln("================ Correlation Matrix =================");
		foreach(parameter_name,idx;expr.param_index_lookup) {
			if (idx==x_idx) continue;
			uint i = idx;
			if (idx>x_idx) --i;

			foreach(parameter_name2,idx2;expr.param_index_lookup) {
				if (idx2==x_idx) continue;
				uint j = idx2;
				if (idx2>x_idx) --j;
				import std.math;
				if (verbose) writef("%20s",covar[i][j]/sqrt(covar[i][i]*covar[j][j]));
			}
			if (verbose) writeln();
		}
		if (verbose) writeln("================");


		// copy result parameters back into our local array
		foreach(i,rpar; fitter.result_params) {
			if (i<x_idx) {
				data.fitresult[i] = rpar*all_params[i];
			} else {
				data.fitresult[i+1] = rpar*all_params[i+1];
			}
		}

		// calculate the resulting qantities as function of parameters
		foreach(index, ref result_expr; result_exprs) {
			data.result_values[index] = result_expr.e.eval(result_params[index]);
			// compute the errors of the result expression : dfunc = sqrt( sum_ij result_cov[i][j] * df_di * df_dj );

			// get the first derivative of the result expression for each parameter
			import std.stdio;
			//writeln("derivatives of ", data.results[index]);
			result_derivatives[index].length = result_params[index].length;
			foreach(i,ref rpar; result_params[index]) {
				string parname;
				import std.array,std.range,std.algorithm;
				foreach(e;result_expr.param_index_lookup.byKeyValue) if (e.value==i) parname=e.key;
				//write(i, ":",parname,"(", rpar, ") : ");
				double rpar_1 = rpar;
				double result_value_1 = data.result_values[index];
				rpar *= 1.001; // make a 1 permil shift
				double rpar_2         = rpar;
				double result_value_2 = result_expr.e.eval(result_params[index]);
				double derivative = (result_value_2-result_value_1)/(rpar_2-rpar_1);
				result_derivatives[index][i] = derivative;
				rpar = rpar_1; // 'repair' the modified parameter
				//writeln(derivative);
			}
			//writeln("------------------");
			//writeln("computing the error using derivatives and covariance matrix");
			data.result_errors[index] = 0;
			foreach(i; 0..result_params[index].length) {
				auto idx_i = result_param_indices[index][i];
				if (idx_i == -1) continue; // skip the "binwidth" parameter
				foreach(j; 0..result_params[index].length) {
					auto idx_j = result_param_indices[index][j];
					if (idx_j == -1) continue; // skip the "binwidth" parameter
					double covar_ij = covar[idx_i][idx_j];
					//writeln("covar ", i, " ", j, " (",idx_i,",",idx_j,")  = ", covar_ij);
					data.result_errors[index] +=  covar_ij * result_derivatives[index][i] * result_derivatives[index][j];
				}
			}
			import std.math;
			//writeln("error = ", sqrt(data.result_errors[index]));
			//writeln("====================");
			data.result_errors[index] = sqrt(data.result_errors[index]);


			//import std.stdio;
			//writeln("result ", index, " params ", result_params[index], " expression " , data.results[index]  ,"  result value ", data.result_values[index]);
		}
		import std.math;
		auto fitresults = data.fitresult.dup;
		double red_deviance = 0; // vairance of the residuals
		foreach(datapoint; datapoints) {
			double ni = datapoint.v;
			fitresults[x_idx] = datapoint.c;
			double ui = expr.e.eval(fitresults);
			double delta = ui-ni+ni*log(ni/ui);
			//writeln("=>", delta);
			if (ni > 0) red_deviance += delta;
		}
		red_deviance *= 2;
		red_deviance /= (datapoints.length-fit_params.length);
		if (verbose) writeln("reduced deviance (D/ndf) = ", red_deviance);
		data.result_red_chi_sqr = red_deviance;
		if (verbose) {
			foreach(idx,value; data.result_values) {
				import std.conv;
				import std.stdio;
				import std.format;
				import std.array;
				if (value is double.init) continue;
				writefln("%20s : %20s +- %20s [ %s %%]",data.results[idx].split('=')[0], value, data.result_errors[idx], 100*data.result_errors[idx]/value, );
			}			
		}

	}


	//void fit_loglikelihood(FitDataSource source, double[2] region, bool verbose = true, bool quiet = false, bool with_deltas = false, int max_steps=250) {
	//	import multifit_nlin;
	//	import std.algorithm, std.array;

	//	auto datapoints = source.get_data(region).map!(xyd=>Dp!double(xyd[0],xyd[1],xyd[2])).array;
	//	//import std.stdio;
	//	//writeln(datapoints);
	//	import std.stdio;
	//	if (verbose) writeln("fit with ", datapoints.length, " points");

	//	const x_idx = expr.param_index_lookup["x"];
	//	double[] all_params = data.parameters.dup; // original set of parameters. What is actually used as fit paramters is an array of 1.0
	//	double[] all_params_mod = data.parameters.dup; // each fit parameter is then multiplied with all_params during function execution and stored here (modified parameters)
	//	                                               // this is necessary because the GSL-fitter becomes unreliable if the paramteres are too big 

	//	if (datapoints.length < all_params.length) {
	//		writeln("not enough datapoints. not fit");
	//		return;
	//	}

	//	if (with_deltas) {
	//		all_params[]     += parameter_deltas[];
	//		all_params_mod[] += parameter_deltas[];
	//	}

	//	auto fitdelegate = delegate double(double x, double[] pars) {
	//		foreach(i; 0..x_idx) all_params_mod[i] = all_params[i]*pars[i];
	//		all_params_mod[x_idx] = x;
	//		foreach(i; x_idx+1 ..all_params.length) all_params_mod[i] = all_params[i]*pars[i-1];
	//		return expr.e.eval(all_params_mod);
	//	};
	//	double[] fit_params;
	//	foreach(i,ref par; all_params) {
	//		if (i != x_idx) {
	//			import std.math;
	//			if (abs(par) > 1) { // do the parameter rescaling only for parameters > 1. Small parameters are handled by GSL well and if we happen to have 0 as start parameter that rescaling doesn't  work
	//				//fit_params ~= par;
	//				fit_params ~= 1.0; // initialze all fit parameters with 1.0. These will be multiplied with the actual start parameter before evaluating the function
	//			} else {
	//				fit_params ~= par;
	//				par = 1.0;
	//			}
	//		}
	//	}	
	//	auto fitter = MultifitNlin!(double,typeof(fitdelegate),typeof(&loglikelihood))(fitdelegate, datapoints, fit_params, false, &loglikelihood);
	//	fitter.run(max_steps);
	//	foreach(parameter_name,idx;expr.param_index_lookup) {
	//		if (idx==x_idx) continue;
	//		uint i = idx;
	//		if (idx>x_idx) --i;

	//		if (verbose) writefln("%10s (par %s) = %10s +- %10s",parameter_name,i,fitter.result_params[i]*all_params[idx], fitter.result_errors[i]*all_params[idx]);
	//		else if (!quiet) write(fitter.result_params[i]*all_params[idx], " ", fitter.result_errors[i]*all_params[idx], " ");

	//		foreach(index, ref result_pars; result_params) {
	//			auto par = parameter_name in result_exprs[index].param_index_lookup;
	//			if (par !is null) {
	//				//import std.stdio;
	//				//writeln("found parameter ", parameter_name, " in result expression ", data.results, " at index ", result_exprs[index].param_index_lookup[parameter_name], " and it hast value ", fitter.result_params[i]*all_params[idx]);
	//				result_pars.length = result_exprs[index].param_index_lookup.length;
	//				result_pars[result_exprs[index].param_index_lookup[parameter_name]] = fitter.result_params[i]*all_params[idx];
	//			}
	//		}
	//	}
	//	if (!verbose && !quiet) writeln;

	//	// copy result parameters back into our local array
	//	foreach(i,rpar; fitter.result_params) {
	//		if (i<x_idx) {
	//			data.fitresult[i] = rpar*all_params[i];
	//		} else {
	//			data.fitresult[i+1] = rpar*all_params[i+1];
	//		}
	//	}

	//	// calculate the resulting qantities as function of parameters
	//	foreach(index, ref result_expr; result_exprs) {
	//		data.result_values[index] = result_expr.e.eval(result_params[index]);
	//		//import std.stdio;
	//		//writeln("result ", index, " params ", result_params[index], " expression " , data.results[index]  ,"  result value ", data.result_values[index]);
	//	}
	//}

	void set_dragupdate(bool dragupdate) {
		data.dragupdate = dragupdate;
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

	expression.Result[] result_exprs;
	long[][] result_param_indices; // the result expression needs to be able to look up the position of its parameer in the fitresult-array
	double[][] result_params;      // for each result expression there needs to be a "flat" array of parameters that occur in that expression
	double[][] result_derivatives; // numerical derivative of the result with respect to each parameter

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


	string formatWithError(double value, double error) const
	{
		import std.math;
		import std.format;
		import std.string;
		import std.algorithm;
		import std.stdio;

		//writeln("==========================");
		//writeln(value, " ± ", error);
		int expVal = cast(int)floor(log10(abs(value)));
		int expErr = cast(int)floor(log10(error));
		int digits_after_point = max(-expErr+2,0);
		//writeln("digits after point: ", digits_after_point);
		double value_rescaled = value;
		string value_str = format("%.*f",digits_after_point,value);
		if (expVal<-2) value_str = format("%.*f",2,value/exp((expVal+1)*log(10.0)));
		string error_str = format("%d",cast(int)(error / exp(-digits_after_point*log(10.0))));
		string exp_str = "";
		if (digits_after_point > 0) {
			while (error_str[$-1]=='0' && value_str[$-1]=='0') {
				error_str = error_str[0..$-1];
				value_str = value_str[0..$-1];
				if (value_str[$-1]=='.') {
					value_str = value_str[0..$-1];
				}
			}
		}
		if (expVal<-2) exp_str = format("e%d",expVal+1);
		//writeln("expVal:",expVal, " expErr:",expErr, "   error order of magnitude:", exp(expErr*log(10.0)) , "    digits of err:", error_str , " value:", value_str, "(",error_str,")", exp_str);

		return value_str~"("~error_str~")"~exp_str;
	}


	override void draw(BackendInterface d, in Transform[3] t, bool modified) const
	{
		import std.algorithm;
		auto local_fitresults = funct.data.fitresult.dup;  
		auto local_parameters = funct.data.parameters.dup; 
		if (funct.is_interactive) local_parameters[] += funct.parameter_deltas[];
		double y_max;
		double x_at_y_max;
		// function does depend on x
		auto x_idx = funct.expr.param_index_lookup["x"];
		for (int n = 0; n < 2; ++n) {
			if (n == 0) {
				d.set_color(0,0.3,0,0.2);
				d.set_line_width(4);				
			} else {
				d.set_color(0.6,0,0);
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
			double x_old, y_old;
			double slope_old;
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
				if (n == 1) {
					// compute slope
					double slope = (y-y_old)/(x-x_old);
					bool extremum = slope*slope_old < 0;
					slope_old = slope;
					//writeln("x=",x,"    slope=",slope, extremum?" EXTREMUM":"", "  y_max=",y_max, " y=",y);
					if (extremum) {
						if (y_max is double.init || (y_max < y) )  {
							y_max = y;
							x_at_y_max = x;
						}
					}
				}
				x_old = x;
				y_old = y;
			}
			d.stroke();
		}
		// position the result text in the left-right center if no extremum was found
		const points = 1000;
		double left  = t[0].min;
		double right = t[0].max;
		if (y_max is double.init) {
			x_at_y_max = t[0].exp(left+points/2*(right-left)/points);
			local_fitresults[x_idx] = x_at_y_max;
			y_max = funct.expr.e.eval(local_fitresults);
		}
		super.draw(d,t,modified);

		double width,height;
		d.text_extent("x",width,height);
		height *= 1.7;


		if ( funct.data.result_red_chi_sqr !is double.init)
		{
			import std.conv;
			import std.format;
			double xpos = t[0].world2canvas(t[0].log(x_at_y_max));
			double ypos = t[1].world2canvas(t[1].log(y_max))-height*(0.5+0);
			string text;
			if (funct.data.loglikelihood) text = "deviance/ndf : ";
			else                          text = "Chi^2/ndf : ";
			text ~= format("%.2f",funct.data.result_red_chi_sqr);
			//text ~= funct.data.result_red_chi_sqr.to!string;
			//string text = funct.data.results[idx].split('=')[0] ~ " : " ~ value.to!string;
			if (d.text_with_border()) {
				d.set_color(0.9,0.9,0.9);
				d.text(xpos-1, ypos-1, text);
				d.text(xpos-1, ypos+1, text);
				d.text(xpos+1, ypos-1, text);
				d.text(xpos+1, ypos+1, text);
				d.stroke();
			}
			d.set_color(0,0,0);
			d.text(xpos,ypos, text);
			d.stroke();
		}


		foreach(idx,value; funct.data.result_values) {
			import std.conv;
			import std.format;
			import std.array;
			if (value is double.init) continue;
			double xpos = t[0].world2canvas(t[0].log(x_at_y_max));
			double ypos = t[1].world2canvas(t[1].log(y_max))-height*(1.5+idx);
			double err_percent = 100*(cast(int)100*funct.data.result_errors[idx]/value)/100.0;
			string err_percent_str = format("%.1f",err_percent);
			string err_str = format("%.2f",funct.data.result_errors[idx]);
			string text = funct.data.results[idx].split('=')[0] ~ " : " ~ formatWithError(value,funct.data.result_errors[idx]) ~ " [" ~ err_percent_str ~ "%]";
			//string text = funct.data.results[idx].split('=')[0] ~ " : " ~ value.to!string ~ " ± " ~ err_str ~ " [" ~ err_percent_str ~ "%]";
			//string text = funct.data.results[idx].split('=')[0] ~ " : " ~ value.to!string;
			if (d.text_with_border()) {
				d.set_color(0.9,0.9,0.9);
				d.text(xpos-1, ypos-1, text);
				d.text(xpos-1, ypos+1, text);
				d.text(xpos+1, ypos-1, text);
				d.text(xpos+1, ypos+1, text);
				d.stroke();
			}
			d.set_color(0,0,0);
			d.text(xpos,ypos, text);
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

	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t, bool zoom = false) {
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
	void do_fit(bool verbose, bool quiet, bool with_deltas, int Nmax, bool loglikelihood = false) {
		if (funct.data.hist1dname !is null && funct.data.gate1dname !is null) {
			import fairy, functions, std.stdio;
			auto h1_ptr = funct.data.hist1dname in fairy.session.items;
			if (h1_ptr is null) {
				writeln("drag fit: no item with name " ~ funct.data.hist1dname);
				return;
			}
			FitDataSource source = cast(FitDataSource)(h1_ptr.item);
			if (source is null) {
				writeln("drag fit: item " ~ funct.data.hist1dname ~ " is not of type functions.FitDataSource");
				return;
			}
			Function fun = cast(Function)(funct);
			if (fun is null) {
				writeln("drag fit: item  not of type functions.Function");
				return;
			}
			auto g1_ptr = funct.data.gate1dname in fairy.session.items;
			if (g1_ptr is null) {
				writeln("drag fit: no item with name " ~ funct.data.gate1dname);	
				return;
			}
			import gate;
			Gate1D gate1d = cast(Gate1D)(g1_ptr.item);
			if (gate1d is null) {
				writeln("drag fit: item " ~ funct.data.gate1dname ~ " is not of type Gate1d");	
				return;
			}
			double left = gate1d.data.min;
			double right = gate1d.data.max;

			if (with_deltas) {
				left += gate1d.min_delta;
				right += gate1d.max_delta;
			}
			if (left > right) {
				import std.algorithm;
				swap(left,right);
			}

			//writeln("left right = " , left, " ", right);
			if (loglikelihood) {
				fun.fit_loglikelihood(source,[left,right],verbose,quiet,with_deltas,Nmax);			
			} else {
				fun.fit(source,[left,right],verbose,quiet,with_deltas,Nmax);			
			}
		}
	}

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
			do_fit(true,false,false,250,funct.data.loglikelihood);
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
			if (funct.data.dragupdate) do_fit(false,true,true,20,funct.data.loglikelihood);
		}
	}




}