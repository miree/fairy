module app;
@safe:

double fun(double[] ax, double[] pars) {
	assert(ax.length == 1);
	assert(pars.length == 2);
	double b = pars[0];
	double c = pars[1];
	double x = ax[0];
	return x*x+b*x+c;
}

int main(string[] args) {
	import multifit_nlin;
	Dp!(double[])[] data;
	double[] params = [1,1];
	import std.random;
	foreach(x;0..100) data ~= Dp!(double[])([x],uniform(-1,1)+x,2);
	auto fitter = MultifitNlin!(double[],typeof(&fun))(&fun, data, params, true);
	fitter.run();
	


	import fairy;
	try {
		fairy.run(args);
	} catch (Exception e) {
		import std.stdio;
		writeln("Exception: ", e.file ,":", e.line, " : ", e.msg);
		return -1;
	}
	return 0;
}
