// Convenience wrapper around some functionality of the GNU Scientific Library
// Copyright (C) 2014  Michael Reese
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

module multifit_nlin;
@trusted:

pragma(lib, "gsl");
pragma(lib, "gslcblas");
pragma(lib, "m");

import std.stdio;
import std.math;
import std.traits;
import multifit_nlin_import;

/+ C is coordinate type of data point
 + Data points alwas have coordinate (c), value (v) and uncertainty called sigma (s).
 +/ 
struct Dp(C)
{
	C  c; 		// coordinate
	double v = 0;	// value
	double s = 1;	// sigma
};

/+ F function to fit
 + E function to evaluate the difference between fitfunction and data point
 + C coordinate type of the data points
 +/
struct Fs(C,F,E) 
{
	F f;
	E eval;
	Dp!C[] data;
	double h = 1e-10;	// step size during derivative calculation
};

struct LenPtr(T) { typeof(T[0].length) len; const(T)* ptr; }
union Conv(T) {	LenPtr!T lenptr; T[] array; }
Conv!double conv_global;
// convert gsl_vector to D array
double[] conv(const(gsl_vector) *x)
{
	conv_global.lenptr.len = x.size;
	conv_global.lenptr.ptr = gsl_vector_const_ptr(cast(gsl_vector*)x,0);
	return conv_global.array;
}

// function for the gsl
extern(C) int fit_f_pp(C,F,E) (const(gsl_vector) *x, void *params, gsl_vector *f)
{
	auto fs = cast(Fs!(C,F,E) *) params;
	double[] ps = conv(x);

	foreach(i, ref d; fs.data)
		gsl_vector_set(f, i, fs.eval(fs.f(d.c, ps), d.v, d.s));
	return GSL_SUCCESS;
}

// helper struct to build a gsl-derivative-calculation compatible function
// Func  function type
// Eval  evaluation function type
// Coord coordinate type
struct Ds(C,F,E) // drivative structure
{
	F f;						// function
	E eval;	    				// evaluation function
	Dp!C   *dp;					// coordintate
	double[] ps;            	// parameter array
	uint n; 					// the n-th parameter will be modified
};

// gsl derivative of a function F with respect to a certain parameter
extern(C) double deriv_f(C,F,E)(double x, void *p)
{
	auto ds = cast(Ds!(C,F,E)*) p;
	double tmp = ds.ps[ds.n];				// save n-th parameter
	ds.ps[ds.n] = x;						// overwrite n-th parameter with x
	double f = ds.f(ds.dp.c, ds.ps);
	double v = ds.eval(f, ds.dp.v, ds.dp.s);// evaluate function value
	ds.ps[ds.n] = tmp;		                // put the n-th parameter back on its place
	return v;
}

extern(C) int fit_df_pp(C,F,E)(const(gsl_vector) *x, void *params, gsl_matrix *J)
{
	auto fs = cast(Fs!(C,F,E)*) params;
	double[] ps = conv(x);
	Ds!(C,F,E) ds = {fs.f, fs.eval, null, ps, 0};
	
	foreach(m, ref data; fs.data)
	{
		ds.dp = &data;
		gsl_function gslf = {&deriv_f!(C,F,E), &ds};
		
		for (uint n = 0; n < x.size; ++n)
		{
			ds.n = n;
			double result, abserr;
			gsl_deriv_central(&gslf, ds.ps[n], fs.h, &result, &abserr);
			gsl_matrix_set(J, m, n, result);
		}
	}
	return GSL_SUCCESS;
}

extern(C) int fit_fdf_pp(C,F,E)(const(gsl_vector) *x, void *params, gsl_vector *f, gsl_matrix *J)
{
	if (fit_f_pp!(C,F,E)(x,params,f) == GSL_SUCCESS &&
		fit_df_pp!(C,F,E)(x,params,J) == GSL_SUCCESS)
		return GSL_SUCCESS;
	return GSL_SUCCESS;
}

// this is the default evaluator function
double residues(double f, double v, double s)
{
	return (f-v)/s;
}
struct MultifitNlin(C,F,E=typeof(&residues))
{
	F f;
	E eval;
	Dp!C[] data;
	double[] pars;
	Fs!(C,F,E) fs;
	gsl_multifit_function_fdf gslf;
	gsl_multifit_fdfsolver *s;
	gsl_vector *param;
	gsl_matrix *result_covar_gsl;
	int status;
	int iter;
	double res_chi;
	bool verbose;
	
	this(F f, Dp!C[] data, double[] pars, bool verbose = false, E eval = &residues,
		 double hstep = 1e-10)
	{
		this.f    = f;
		this.eval = eval;
		this.data = data;
		this.pars = pars;
		this.fs   = Fs!(C,F,E)(f, eval, data, hstep);
		this.gslf = gsl_multifit_function_fdf(&fit_f_pp!(C,F,E), 
											  &fit_df_pp!(C,F,E), 
											  &fit_fdf_pp!(C,F,E),
											  data.length,
											  pars.length,
											  cast(void*)(&fs));
		this.s = gsl_multifit_fdfsolver_alloc(gsl_multifit_fdfsolver_lmsder, 
										 data.length, pars.length);
		this.verbose = verbose;
		param = gsl_vector_alloc(pars.length);
		result_covar_gsl = gsl_matrix_alloc(pars.length, pars.length);
		foreach(i, par; pars) gsl_vector_set(param, i, par);
		gsl_multifit_fdfsolver_set(s, &gslf, param);
		if (verbose) 
		{
			foreach (i; 0 .. pars.length)
				writef("%12s",cast(double)gsl_vector_get(param, i));
			writefln("  (%3s)",0);	
		}	
	}
	~this()
	{
		gsl_vector_free(param);
		gsl_multifit_fdfsolver_free(s);
		gsl_matrix_free(result_covar_gsl);
	}
	bool fit_continue(double epsilon)
	{
		return GSL_CONTINUE == gsl_multifit_test_delta(s.dx, s.x, 0.0, epsilon);
	}
	
	int fit_step()
	{
		status = gsl_multifit_fdfsolver_iterate(s);
		++iter;

		if (verbose)
		{
			foreach (i; 0 .. pars.length)
				writef("%12s",cast(double)gsl_vector_get(s.x, i));
			writefln("  (%3s)     chi=%s",iter,gsl_blas_dnrm2(s.f));	
		}	
		
		return iter;
	}
	int run(int steps = 50, double epsilon = 1e-5)
	{
		int iter = 0;
		do 
		{
			fit_step();
			++iter;
		}
		while(fit_continue(epsilon) && iter < steps);
		calc_covar();
		calc_chi();
		return iter;
	}
	void calc_covar()
	{
		gsl_matrix *J = gsl_matrix_alloc(data.length, pars.length);
		gsl_multifit_fdfsolver_jac(s, J);
		gsl_multifit_covar(J, 0.0, result_covar_gsl);
		gsl_matrix_free(J);
		//gsl_multifit_covar(s.J, 0.0, result_covar_gsl);
	}
	void calc_chi()
	{
		res_chi = gsl_blas_dnrm2(s.f);
	}
	@property double[] result_params()
	{
		double[] ps = new double[pars.length];
		foreach(i, ref p; ps) p = gsl_vector_get(s.x, i);
		return ps;
	}
	@property double[] result_errors()
	{
		double[] es = new double[pars.length];
		foreach(i, ref e; es) e = std.math.sqrt(gsl_matrix_get(result_covar_gsl,i,i));
		return es;
	}
	@property double[][] result_covar()
	{
		double[][] css = new double[][pars.length];
		foreach(i, ref cs; css)
		{
			cs = new double[pars.length];
			foreach(j, ref c; cs)
				c = gsl_matrix_get(result_covar_gsl,i,j);
		}
		return css;
	}
	@property double result_chi()
	{
		return res_chi;
	}
	@property double result_red_chi_sqr()
	{
		return res_chi^^2 / (data.length - pars.length);
	}
	
	// derivative of f with respect to parameter i at coordinate 
	double df_d(ulong i, C x, double[] params)
	{
		assert(i < params.length);
		real eps = params[i]*1e-8;
		real tmp = params[i];
		params[i] += eps;
		real f_plus = f(x,params);
		params[i] -= 2*eps;
		real f_minus = f(x,params);
		params[i] = tmp;
		return (f_plus-f_minus)/(2*eps);
	}
	
	static if (isFloatingPoint!(C)) 
	auto result_function_values(C x1, C x2, int n = 1000)
	{
		double[3][] result;
		auto result_par = result_params();
		auto result_cov = result_covar();
		for (C x = x1; x <= x2; x+=(x2-x1)/n)
		{
			double func = f(x,result_par);
			double dfunc = 0;
			foreach(i; 0..pars.length)
			{
				double df_di = df_d(i, x, result_par);
				foreach(j; 0..pars.length)
				{
					double df_dj = df_d(j, x, result_par);
					dfunc += result_cov[i][j]*df_di*df_dj;
				}
			}
			result ~= [x,func,std.math.sqrt(dfunc)];
		}
		return result;
	}
}



