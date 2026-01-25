module ui;
@safe:

// struct for user defined attribute
struct UI_EXPORT {
	string   description;
	string[] arg_descriptions;
}
auto getAttribute(alias mem, T)() {
	foreach (attr; __traits(getAttributes, mem)) {
		static if (is(typeof(attr) == T)) {
			return attr;
		}
	}
	return T.init;
}
bool hasUiExport(alias mem)() {
	foreach (attr; __traits(getAttributes, mem)) {
		static if (is(typeof(attr) == UI_EXPORT)) {
			return true;
		}
	}
	return false;
}


///////////////////////////////////////////////////////////////////////
// some helper functions for the ui commands
///////////////////////////////////////////////////////////////////////

auto check_action_helper(string action) {
	if (action != "toggle" && action != "true" && action != "false") {
		throw new Exception("invalid action: " ~ action ~ ", expect true, false, or toggle");
	}
}

auto axis_helper_xyz(char axis) {
	if (axis=='x'||axis=='y'||axis=='z') {
		return axis-'x';
	}
	throw new Exception("invalid axis: "~ axis~ ", possible values are x, y, or z");
}
auto axis_helper_xy(char axis) {
	if (axis=='x'||axis=='y') {
		return axis-'x';
	}
	throw new Exception("invalid axis: "~ axis~ ", possible values are x or y");
}

bool toggle_action(string action, ref bool property) {
	if (action != "toggle" && action != "true" && action != "false") {
		throw new Exception("invalid action: " ~ action ~ ", expect true, false, or toggle");
	}
	bool active = (action=="true");
	bool toggle = (action=="toggle");
	if (toggle) active = !property;
	if (property != active) {
		property = active;
		return true;
	}
	return false;
}

void update_window_gui(string window_name, bool canvas_items_changed = false) {
	import fairy;
	if (start_gui && main_gui !is null) {
		if (canvas_items_changed) main_gui.update_from_canvas(window_name);
		main_gui.redraw_window(window_name);
	}
}


///////////////////////////////////////////////////////////////////////
// all user interface functions are here
///////////////////////////////////////////////////////////////////////
@UI_EXPORT("save current session and open a new one")
string session_close() {
	import fairy, histogram;
	import std.algorithm;
	if (start_gui) foreach (name; fairy.session.windows.byKey) if (fairy.main_gui !is null) fairy.main_gui.save_window(name);

	version(elderpt) {
		import elderpt;
		//bool elderpt_was_running = elderpt.running;
		if (elderpt.running) {
			ui.elderpt("stop");
			assert(elderpt.running == false);
		}
	}

	import std.stdio;
	//writeln("before closing: ", fairy.session.windows);
	fairy.session.write_to_file();
	fairy.session.close();
	fairy.session.name = "";

	import core.thread;
	Thread.sleep(500.msecs);

	return "";
}


@UI_EXPORT("save current session and open a new one",
	["new session name, file does not exist a new session is created"])
string session_open(string session_name) {
	import fairy, histogram;
	import std.algorithm;
	if (session_name.endsWith(".session")) {
		session_name = session_name[0..$-8];
	}
	if (fairy.session.name != "") return "running session must be closed first";

	//if (start_gui) foreach (name; fairy.session.windows.byKey) if (fairy.main_gui !is null) fairy.main_gui.save_window(name);

	//version(elderpt) {
	//	import elderpt;
	//	//bool elderpt_was_running = elderpt.running;
	//	if (elderpt.running) {
	//		ui.elderpt("stop");
	//		assert(elderpt.running == false);
	//	}
	//}

	//import std.stdio;
	////writeln("before closing: ", fairy.session.windows);
	//fairy.session.write_to_file();
	//fairy.session.close();
	////writeln("after closing: ", fairy.session.windows);

	// there is something wrong when a windowname from the loaded session has existed in the closed session. That window shows on the screen but not in the session.windows map.
	// Don't exactly understand yet why this happens.... but waiting one seconde before recreating the gui windows seems to be a workaround. 
	import core.thread;
	Thread.sleep(500.msecs);

	fairy.session.name = session_name;
	fairy.session.read_from_file();

	import core.thread;
	Thread.sleep(500.msecs);

	if (start_gui) {// gui is already running
		foreach (name, ref window; fairy.session.windows) {
			if (fairy.main_gui !is null) {
				//writeln("gui add window ", name);
				fairy.main_gui.add_window(name,window);
			}
		}
	}
	//writeln("after opening: ", fairy.session.windows);

	//version(elderpt) {
	//	if (elderpt_was_running) {
	//		ui.elderpt("start");
	//	}
	//}

	return "";
}

@UI_EXPORT("save current session under new name",
	["new session name, file is immediately written"])
string session_save(string session_name) {
	import fairy, histogram;
	import std.algorithm;
	if (session_name.endsWith(".session")) {
		session_name = session_name[0..$-8];
	}
	fairy.session.name = session_name;
	fairy.session.write_to_file();
	return "";
}


version(alsa) {

//@UI_EXPORT("print info abut alsa", 
//	["alsa device name"])
//@trusted
//string alsainfo(string alsa_device = "default") {
//	import alsa;
//	import std.conv;
//	string result = "maximum number of channels " ~ alsa_get_max_channels(alsa_device).to!string;
//	auto minmax_rates = alsa_get_minmax_rates(alsa_device);
//	result ~= "\nminimum sampling rate " ~ minmax_rates[0].to!string;
//	result ~= "\nmaximum sampling rate " ~ minmax_rates[1].to!string;

//	return result;
//}
@trusted
@UI_EXPORT("control audio DAQ",
	["command (info, start, pause, continue, stop)",
	 "trigger level (default=auto)",
	 "trigger slope (rising, falling, either)",
	 "trigger position as fraction of trace length: must be >= 0.0 and <= 1.0 (default 0.5)",
	 "number of samples in the captured trace (default=1024)",
	 "number of channels (default=max)",
	 "sampling rate (default=max)",
	 "list of filters (default=[])",
	 "interpolation mode: (no, linear, sinc=default)",
	 "device name of the audio backend"
	 ]) 
string audiodaq(string command, string trigger_level = "0", string trigger_slope = "rising", double trigger_position = 0.5,  string tracelength = "1024", string channels = "max", string rate = "max", string[] filter_list = [], string interpolation = "linear", string device = "default") {
	import audiodaq;
	import std.concurrency;
	if (command == "info") {
		//import std.typecons, std.algorithm, std.conv, std.array;
		//auto daq = scoped!Alsa(device);
		//auto rates    = daq.get_allowed_rates.map!(to!string).join(", ").array;
		//auto allowed_channels = daq.get_allowed_channels.map!(to!string).join(", ").array;
		//return "allowed rates: " ~ rates.to!string ~ "\nallowed channels: " ~ allowed_channels.to!string;
		return "";
	}
	if (command == "start") {
		import std.typecons, std.algorithm, std.conv, std.array;

		double trig_level;
		if (trigger_level != "auto") trig_level = trigger_level.to!double;
		int trig_slope = 0;
		if (trigger_slope == "rising") trig_slope = 1;
		else if (trigger_slope == "falling") trig_slope = -1;
		else if (trigger_slope == "either") trig_slope = 0;
		else throw new Exception("trigger_slope must be one of: rising, falling, either");

		//auto daq = scoped!Alsa(device);


		int trace_length = tracelength.to!int;
		if (trace_length < 1) throw new Exception("tracelength must be larger than 1");

		//auto allowed_channels = daq.get_allowed_channels;
		//if (allowed_channels.empty) throw new Exception("cannot detect channel count on device ", device);
		int num_channels;
		//if (channels == "max") num_channels = daq.get_allowed_channels[$-1];
		//else  
		                 num_channels = channels.to!int;
		if (!num_channels) throw new Exception("channel number must be larger than 0");
		
		//auto allowed_rates = daq.get_allowed_rates;
		//if (allowed_rates.empty) throw new Exception("cannot detect allowed sampling rates on device ", device);
		int samplingrate;
		//if (rate == "max") samplingrate = allowed_rates[$-1];
		//else               
			samplingrate = rate.to!int;

		audiodaq.InterpolationMode interpolation_mode;
		if (interpolation == "no") interpolation_mode = InterpolationMode.no;
		else if (interpolation == "linear") interpolation_mode = InterpolationMode.linear;
		else if (interpolation == "sinc") interpolation_mode = InterpolationMode.sinc;
		else throw new Exception("unsupported interpolation mode: "~interpolation~" . Allowed modes are no,linear,sinc");

		if (audiodaq.running) throw new Exception("audiodaq already running");
		audiodaq.running = true;
		audiodaq.tid = spawn(&run_audiodaq, thisTid, trace_length, num_channels, samplingrate, trig_level, trig_slope, trigger_position, filter_list.idup, interpolation_mode, device);
		return "started audiodaq device "~device~" with rate="~samplingrate.to!string~" on "~num_channels.to!string~" channels. tracelength is "~tracelength.to!string;
	}
	if (command == "pause") {
		if (!audiodaq.running) throw new Exception("audiodaq is not running");
		if (audiodaq.paused)   throw new Exception("audiodaq is already paused");
		audiodaq.paused = true;
		audiodaq.tid.send(MsgPause());
		receive((MsgAck msg) {});
		return "paused";
	}
	if (command == "continue") {
		if (!audiodaq.running) throw new Exception("audiodaq is not running");
		if (!audiodaq.paused)   throw new Exception("audiodaq is not paused");
		audiodaq.paused = false;
		audiodaq.tid.send(MsgContinue());
		receive((MsgAck msg) {});
		return "continued";
	}
	if (command == "stop") {
		if (!audiodaq.running) throw new Exception("audiodaq is not running");
		audiodaq.running = false;
		audiodaq.tid.send(MsgStop());
		import std.stdio;
		//writeln("sent MsgStop, wait for MsgAck");
		receive((MsgAck msg) {});
		return "stopped";
	}
	throw new Exception("unknown command for audiodaq");
}

} // version(alsa)


@UI_EXPORT("list all items",
	["include items that are not initialized (because their type could not be recognized while reading the session file"])
@trusted
string ls(bool all = true) {
	import fairy;
	return fairy.session.list_items(all);
}

@UI_EXPORT("define a function",
	["name of the function",
	 "definition of the function. the parameter \'binwidth\' can be used to get the bin width of the fit data source",
	 "function parameters",
	 "handles for gui manipulation",
	 "name of histogram item",
	 "name of gate",
	 "fit is updated while dragging",
	 "do loglikelihood fit instead of chisquare"])
@trusted
string funct(string name, string definition, string[] parameters = null, string handles = null, string hist1dname = null, string gate1dname = null, string[] results = null, bool dragupdate = true, bool loglikelihood = false) {
	import std.algorithm, std.conv, std.stdio, std.array;
	import fairy, functions;
	double[string] pars;
	if (parameters !is null) {
		foreach(par; parameters) {
			auto pv = par.split('=');
			pars[pv[0]] = pv[1].to!double;
		}
	}
	pars["x"]=0.0;
	fairy.session.add_item(name, new Function(definition, pars, handles, hist1dname, gate1dname, results, dragupdate, loglikelihood));
	return "";
}
@UI_EXPORT("set dragupdate property of function",
	["name of the function",
	 "true or false"])
string dragupdate(string functname, bool dragupdate = true) {
	import fairy, functions;
	auto f1_ptr = functname in fairy.session.items;
	if (f1_ptr is null) {
		throw new Exception("no item with name " ~ functname);
	}
	Function f = cast(Function)(f1_ptr.item);
	if (f is null) {
		throw new Exception("item " ~ functname ~ " is not of tyep Function");
	}
	f.set_dragupdate(dragupdate);
	return "";
}

@UI_EXPORT("create a 1D gate",
	["itemname",
	 "left limit", 
	 "right limit",
	 "x|y"])
@trusted
string gate1d(string name, double  min, double max, char direction = 'x') {
	import fairy, gate;
	if (direction != 'x' && direction != 'y') {
		throw new Exception("direction must be x or y");
	}
	int dir = (direction=='x')?0:1;
	fairy.session.add_item(name, new Gate1D(min,max,dir));
	return "";
}

@UI_EXPORT("create a 2D gate",
	["itemname",
	 "left limit", 
	 "right limit",
	 "bottom limit",
	 "top limit"])
@trusted
string gate2d(string name, double  xmin, double xmax, double ymin, double ymax) {
	import fairy, gate;
	fairy.session.add_item(name, new Gate2D(xmin,xmax,ymin,ymax));
	return "";
}

@UI_EXPORT("create a polygon gate",
	["itemname"
	 ])
@trusted
string polygate(string name) {
	import fairy, gate;
	fairy.session.add_item(name, new PolyGate([[1,1],[1,2],[2,2]]));
	return "";
}

@UI_EXPORT("fit function to histogram",
	["name of functiton item",
	 "name of histogram item",
	 "left end of fit region",
	 "right end of fit region"])
string fit2(string function_name, string histogram_name, double left, double right) {
	import fairy, functions;
	auto h1_ptr = histogram_name in fairy.session.items;
	if (h1_ptr is null) {
		throw new Exception("no item with name " ~ histogram_name);
	}
	FitDataSource source = cast(FitDataSource)(h1_ptr.item);
	if (source is null) {
		throw new Exception("item " ~ histogram_name ~ " is not of type functions.FitDataSource");
	}
	auto f1_ptr = function_name in fairy.session.items;
	if (f1_ptr is null) {
		throw new Exception("no item with name " ~ function_name);
	}
	Function fun = cast(Function)(f1_ptr.item);
	if (fun is null) {
		throw new Exception("item " ~ function_name ~ " is not of type functions.Function");
	}
	fun.fit(source,[left,right]);
	return "";
}

@UI_EXPORT("log likelihood fit function to histogram",
	["name of functiton item",
	 "name of histogram item",
	 "left end of fit region",
	 "right end of fit region"])
string fitLL(string function_name, string histogram_name, double left, double right) {
	import fairy, functions;
	auto h1_ptr = histogram_name in fairy.session.items;
	if (h1_ptr is null) {
		throw new Exception("no item with name " ~ histogram_name);
	}
	FitDataSource source = cast(FitDataSource)(h1_ptr.item);
	if (source is null) {
		throw new Exception("item " ~ histogram_name ~ " is not of type functions.FitDataSource");
	}
	auto f1_ptr = function_name in fairy.session.items;
	if (f1_ptr is null) {
		throw new Exception("no item with name " ~ function_name);
	}
	Function fun = cast(Function)(f1_ptr.item);
	if (fun is null) {
		throw new Exception("item " ~ function_name ~ " is not of type functions.Function");
	}
	fun.fit_loglikelihood(source,[left,right]);
	return "";
}


@UI_EXPORT("series of log likelihood fit function to 2dhistogram line by line",
	["name of functiton item",
	 "name of 2d histogram item",
	 "left end of fit region",
	 "right end of fit region",
	 "sum that many y bins together"])
string fit2dseriesLL(string function_name, string histogram2d_name, double left, double right, int nybins) {
	import fairy, functions, histogram, gate;
	auto h2_ptr = histogram2d_name in fairy.session.items;
	if (h2_ptr is null) {
		throw new Exception("no item with name " ~ histogram2d_name);
	}
	Hist2ProjectionSource source = cast(Hist2ProjectionSource)(h2_ptr.item);
	if (source is null) {
		throw new Exception("item " ~ histogram2d_name ~ " is not of type functions.Hist2ProjectionSource");
	}
	auto f1_ptr = function_name in fairy.session.items;
	if (f1_ptr is null) {
		throw new Exception("no item with name " ~ function_name);
	}
	Function fun = cast(Function)(f1_ptr.item);
	if (fun is null) {
		throw new Exception("item " ~ function_name ~ " is not of type functions.Function");
	}

	// prepare projector
	auto data = source.get_projection_data();
	double bottom = data.bottom;
	double height = (data.top-data.bottom)/data.bins_y;
	double top = bottom + height*nybins;
	bottom -= height*0.1;
	top    += height*0.1;
	string tmp_gatename = histogram2d_name~"_tmp_gate__";
	gate1d(tmp_gatename, bottom,top, 'y');
	auto gate_ptr = tmp_gatename in fairy.session.items;
	assert(gate_ptr !is null);
	auto tmpgate = cast(Gate1D)(gate_ptr.item);
	assert(tmpgate !is null);
	scope(exit) rm(tmp_gatename);
	auto projection = new Hist2Projection(histogram2d_name, tmp_gatename);

	foreach(i;0..data.bins_y) {
		tmpgate.item_version++;
		projection.getVersion();
		projection.do_project();
		import std.stdio;
		write(0.5*(tmpgate.data.min+tmpgate.data.max), "    ");
		fun.fit_loglikelihood(projection,[left,right], false);
		tmpgate.data.min += height; 
		tmpgate.data.max += height;
		tmpgate.item_version++;
		//import std.stdio;
		//writeln("minmax = ", tmpgate.data.min, " ", tmpgate.data.max);
	}
	return "";
}

@UI_EXPORT("fit function to data
  example: fit a+b*x*x [\"a=40\",\"b=2\"] fitpoints.dat",
	["fit function to datapoints in file using given start parameters"])
@trusted
string fit(string fun, string[] start_params, string datafilename) {
	import expression, multifit_nlin;
	import std.algorithm, std.conv, std.stdio, std.array;
	auto data = File(datafilename,"r").byLine
	                                   .map!(l=>l.split.map!(to!double))
	                                   .map!(d=>Dp!double(d[0],d[1],d[2]))
	                                   .array;
	auto fitfunc = evaluate(fun);
	start_params ~= "x=0";
	double[] params = new double[](start_params.length);

	auto func_params = fitfunc.param_index_lookup.byKey;
	auto start_param_names = start_params.map!(pn=>pn.split('=')[0]);
	string[] missing;
	foreach(fp; func_params) {
		if (!start_param_names.canFind(fp)) missing ~= fp;
	}
	if (missing.length > 0) throw new Exception("missing start parmeters for: " ~ missing.join(", "));
	//writeln(params);
	start_params.map!(sp=>sp.split('='))
	            .each!((pv) {
	            	if (pv[0] in fitfunc.param_index_lookup) {
		            	const idx = fitfunc.param_index_lookup[pv[0]];
		            	params[idx] = pv[1].to!double;
	            	} else writeln("warning: no parameter with name "~pv[0]~" in function");
	            });
	//writeln(params);
	const x_idx = fitfunc.param_index_lookup["x"];
	//writeln(x_idx);
	auto fitdelegate = delegate double(double x, double[] pars) {
		pars[x_idx] = x; 
		return fitfunc.e.eval(pars);
	};
	auto fitter = MultifitNlin!(double,typeof(fitdelegate))(fitdelegate, data, params, false);
	fitter.run();

	writeln("fit result: (chi_red^2 = ", fitter.result_red_chi_sqr, ")");
	start_params.map!(sp=>sp.split('='))
	            .each!((pv) {
	            	if (pv[0] in fitfunc.param_index_lookup) {
		            	const idx = fitfunc.param_index_lookup[pv[0]];
		            	if (pv[0]!="x") writeln(pv[0], " = " ,fitter.result_params[idx], " +- ", fitter.result_errors[idx]);
		            }
	            });
	return "";
}



@UI_EXPORT("reset item",
	["name of item to be reset"])
@trusted
string reset(string item_name) {
	import fairy;
	fairy.session.reset_item(item_name);
	return "";
}

@UI_EXPORT("remove item",
	["name of item to be removed"])
@trusted
string rm(string name) {
	import fairy;
	fairy.session.remove_item(name);
	return "";
}



@UI_EXPORT("add 1D-histogram that refers to a file on disk",
	["name of histogram",
	 "value",
	 "y, z, or z"])
string value(string name, double x, char dimension = 'x') {
	import fairy, value;
	fairy.session.add_item(name, new Value(x, 0));
	return "";
}



@UI_EXPORT("add histogram that refers to a file on disk",
	["filename to load the data from"])
string filehistogram(string filename) {
	import fairy, histogram;
	fairy.session.add_item(filename, new FileHistogram(FileHistogram.Data(filename)));
	return "";
}

@UI_EXPORT("add waveform that refers to a file on disk",
	["filename to load the data from"])
string filewaveform(string filename) {
	import fairy, waveform;
	fairy.session.add_item(filename, new FileWaveform(FileWaveform.Data(filename)));
	return "";
}

@UI_EXPORT("add 1D-histogram that refers to a file on disk",
	["name of histogram",
	 "number of bins",
	 "x-axis label",
	 "left border of leftmost bin",
	 "right border of rightmost bin"])
string hist1(string name, ulong bins, string xlabel, double left = double.init, double right = double.init) {
	import fairy, histogram;
	fairy.session.add_item(name, new Hist1(bins,left,right,xlabel));
	return "";
}



@UI_EXPORT("get statistics for histogram",
	["name of histogram",
	 "left of region of interest",
	 "right or region of interest"])
string stats(string name, double left = double.init, double right = double.init) {
	import fairy, histogram;
	auto h1_ptr = name in fairy.session.items;
	if (h1_ptr is null) {
		throw new Exception("no item with name " ~ name);
	}
	Hist1 h1 = cast(Hist1)(h1_ptr.item);
	if (h1 is null) {
		throw new Exception("item " ~ name ~ " is not of type histogram.Hist1");
	}
	h1.write_stats(left,right);
	return "";
}

@UI_EXPORT("get statistics for histogram",
	["name of histogram",
	"filename to write to",
	"rebin so many bins before exporting"])
string hist1export(string name, string filename, int rebin = 1) {
	import fairy, histogram;
	auto h1_ptr = name in fairy.session.items;
	if (h1_ptr is null) {
		throw new Exception("no item with name " ~ name);
	}
	Hist1Export h1 = cast(Hist1Export)(h1_ptr.item);
	if (h1 is null) {
		throw new Exception("item " ~ name ~ " is not of type histogram.Hist1Export");
	}
	try {
		h1.export_to_file(filename, rebin);
	} catch (Exception e) {
		import std.stdio;
		writeln("cannot export ", name, " because ", e.msg);
	}
	return "";
}

@UI_EXPORT("get statistics for histogram",
	["name of histogram",
	"filename to write to"])
string hist2export(string name, string filename) {
	import fairy, histogram;
	auto h2_ptr = name in fairy.session.items;
	if (h2_ptr is null) {
		throw new Exception("no item with name " ~ name);
	}
	Hist2Export h2 = cast(Hist2Export)(h2_ptr.item);
	if (h2 is null) {
		throw new Exception("item " ~ name ~ " is not of type histogram.Hist2Export");
	}
	try {
		h2.export_to_file(filename);
	} catch (Exception e) {
		import std.stdio;
		writeln("cannot export ", name, " because ", e.msg);
	}
	return "";
}

@UI_EXPORT("add projection from 2D-histogram to 1D-histogram using a 1D-gate",
	["name of projector",
	 "name of 2D source histogram",
	 "name of gate"])
string hist2projector(string name, string sourcename, string gatename) {
	import fairy, histogram;
	fairy.session.add_item(name, new Hist2Projection(sourcename, gatename));
	return "";
}

@UI_EXPORT("add set of points as interactive demo",
	["name of point set",
	 "number of points"])
string points(string name, uint n) {
	import fairy, interactive_demo;
	fairy.session.add_item(name, new Points(n));
	return "";
}

@UI_EXPORT("add set of hierarchial points as interactive demo",
	["name of point set"])
string hpoints(string name) {
	import fairy, interactive;                         ///  0     1     2     3     4     5          
	//fairy.session.add_item(name, new HierarchicalPoints( [[0,0],[1,0],[0,1],[1,1],[2,2],[2,-2]],   [[0,1],[0,2],[1,3],[3,4],[3,5]] ));
	fairy.session.add_item(name, new HierarchicalPoints( [[0,0],[1,0]],   [[0,1]] ));
	return "";
}

@UI_EXPORT("add an ellipse as interactive demo",
	["name of the ellipse"])
string ellipse(string name) {
	import fairy, interactive_demo;
	fairy.session.add_item(name, new Ellipse());
	return "";
}

@UI_EXPORT("fill value into the bin of a 1D-histogram",
	["name of histogram",
	 "position",
	 "add so much to the bin content(default is 1.0)",
	 "rebin histogram to capture the count if it is not covered"])
string fill1(string name, double position, double amount = 1.0, bool expand = false) {
	import fairy, histogram;
	auto h1_ptr = name in fairy.session.items;
	if (h1_ptr is null) {
		throw new Exception("no item with name " ~ name);
	}
	Hist1 h1 = cast(Hist1)(h1_ptr.item);
	if (h1 is null) {
		throw new Exception("item " ~ name ~ " is not of type histogram.Hist1");
	}
	h1.fill(position,amount,expand);
	return "";
}

@UI_EXPORT("add 2D-histogram",
	["name of histogram",
	 "number of bins in x-direction",
	 "number of bins in y-direction",
	 "x-axis label",
	 "y-axis label",
	 "left border of leftmost bin",
	 "right border of rightmost bin",
	 "bottom border of lowest bin",
	 "top border of highest bin"])
string hist2(string name, ulong bins_x, ulong bins_y, string xlabel, string ylabel, double left = double.init, double right = double.init, double bottom = double.init, double top = double.init) {
	import fairy, histogram;
	fairy.session.add_item(name, new Hist2(bins_x,bins_y, left,right,xlabel, bottom,top,ylabel));
	return "";
}

@UI_EXPORT("fill value into the bin of a 2D-histogram",
	["name of histogram",
	 "x position",
	 "y position",
	 "add so much to the bin content (default is 1.0)",
	 "rebin histogram to capture the count if it is not covered by current range"])
string fill2(string name, double position_x, double position_y, double amount = 1.0, bool expand = false) {
	import fairy, histogram;
	auto h2_ptr = name in fairy.session.items;
	if (h2_ptr is null) {
		throw new Exception("no item with name " ~ name);
	}
	Hist2 h2 = cast(Hist2)(h2_ptr.item);
	if (h2 is null) {
		throw new Exception("item " ~ name ~ " is not of type histogram.Hist2");
	}
	h2.fill(position_x, position_y,amount,expand);
	return "";
}





@UI_EXPORT("add waveform ",
	["name for the new item",
	 "number of sample points"])
string wave(string name) {
	import fairy, waveform;
	shared(double[]) waveform_data = [
		0,1,
		0,1,
		0,1,
		0,1,
		0,1,
		0,1,
		0,1,
		0,1,
		0,1,
		0,1
	];
	fairy.session.add_item(name, new Waveform(waveform_data, 2, 0, 10));
	return "";
}

@UI_EXPORT("show item in window",
	["name of item to display",
	 "name of window on which the item should be shown",
	 "true, false, all, none: true/false add/remove exact match, add/none add/remove also children"])
string show(string item_name, string window_name, string action = "true", bool update_window = true) {
	import fairy;
	import std.algorithm, std.array;
	auto canvas = fairy.session.get_canvas(window_name);
	if (action == "true") {
		if (session.items.byKey.canFind(item_name) && !canvas.itemnames.canFind(item_name)) {
			canvas.itemnames ~= item_name;
			if (canvas.itemnames.length == 1) canvas.dim = 0;
		}
	}
	if (action == "false") {
		string[] itemnames;
		foreach(itemname; canvas.itemnames) {
			if(itemname != item_name) {
				itemnames ~= itemname;
			}
		}
		canvas.itemnames = itemnames;
	}
	if (action == "all") {
		item_name ~= '/';
		foreach(itemname; session.items.byKey.array.sort) {
			if (itemname == item_name[0..$-1] || (itemname.startsWith(item_name))) {
				if (!canvas.itemnames.canFind(itemname)) {
					canvas.itemnames ~= itemname;
					if (canvas.itemnames.length == 1) canvas.dim = 0;
				}
			} 
		}
	} 
	if (action == "none") {
		item_name ~= '/';
		string[] itemnames;
		foreach(itemname; canvas.itemnames) {
			if(!(itemname == item_name[0..$-1] || itemname.startsWith(item_name))) {
				itemnames ~= itemname;
			}
		}
		canvas.itemnames = itemnames;
	}
	//auto visual = fairy.session.get_visual_item(item_name);
	//if (!canvas.itemnames.canFind(item_name) && action == "true") { // add item
	//	canvas.itemnames ~= item_name;
	//	if (canvas.itemnames.length==1) {
	//		import std.stdio;
	//		//canvas.fit_content = true;
	//		canvas.dim = 0;  // 0 means to determine the dim from frist drawn item
	//		//canvas.transform[0].logscale = false;
	//		//canvas.transform[1].logscale = false;
	//		//canvas.transform[2].logscale = false;
	//	}
	//} else if (action == "false") { // remove item
	//	string[] itemnames;
	//	foreach(item; canvas.itemnames) {
	//		if (item != item_name) {
	//			itemnames ~= item;
	//		}
	//	}
	//	canvas.itemnames = itemnames;
	//}
	if (update_window) update_window_gui(window_name, true);
	return "";
}



@UI_EXPORT("quit program")
@trusted
string quit() {
	import fairy;
	fairy.running = false;
	return "";
}

@UI_EXPORT("enable gui system")
@trusted
string gui() {
	import fairy;
	if (fairy.start_gui) {
		throw new Exception("gui already started");
	}
	fairy.start_gui = true;
	return "gui system started";
}


@UI_EXPORT("set global font size. Windows can overwrite this setting with setwinfontsize",
	["size of fonts in the window (e.g. 10 or 20)"])
void fontsize(int size = 0) {
	if (size < 0) {
		throw new Exception("size must be >= 0");
	}
	import fairy, graphics;
	graphics.set_global_text_size(size);
	fairy.redraw_windows();
}

@UI_EXPORT("set window font size (overwrites global font size setting). When size is 0 the global font size is used for this window",
	["name of the affected window",
	 "size of fonts in the window (e.g. 10 or 20)"])
void winfontsize(string window_name, int size = 0) {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	canvas.text_size = size;
	fairy.redraw_window(window_name);
}


@UI_EXPORT("create new window",
	["name of window",
	 "width of window",
	 "height of window",
	 "x-position on screen",
	 "y-position on screen"])
@trusted
string win(string name, int width = 600, int height = 400, int xpos = -1, int ypos = -1) {
	import fairy;
	fairy.session.add_window(name, width, height, xpos, ypos);
	return "created new window "~name;
}
@UI_EXPORT("close window",
	["name of window"])
@trusted
string close(string name) {
	import fairy;
	fairy.session.close_window(name);
	return "";
}


@UI_EXPORT("set visible range for given window and axis", 
	[ "name of the window",
	  "name of axis (x or y or z)",
	  "minimum value of visible range",
	  "maximum value of visible range"] )
void winrange(string window_name, char axis, double min, double max) {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	auto a = axis_helper_xyz(axis);
	min = canvas.transform[a].log(min);
	max = canvas.transform[a].log(max);
	canvas.transform[a].set_minmax(min, max);
	fairy.redraw_window(window_name);
}

@UI_EXPORT("move visible range axis", 
	[ "name of the window",
	  "name of axis (x or y or z)",
	  "move by that fraction of width"] )
void winmove(string window_name, char axis, double amount) {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	int axis_idx = axis_helper_xyz(axis);
	canvas.transform[axis_idx]
	      .set_minmax(canvas.transform[axis_idx].min + canvas.transform[axis_idx].width*amount,
	                  canvas.transform[axis_idx].max + canvas.transform[axis_idx].width*amount);
	fairy.redraw_window(window_name);
}

@UI_EXPORT("set zoom for given window", 
	[ "name of the window",
	  "zoom by that fraction of width"] )
void winzoom(string window_name, double amount) {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	foreach (i; 0..2) {
		canvas.transform[i].set_minmax(canvas.transform[i].max - canvas.transform[i].width*amount,
		                               canvas.transform[i].min + canvas.transform[i].width*amount);
	}
	fairy.redraw_window(window_name);
}

@UI_EXPORT("fit window to all items ", 
	[ "name of the window"])
void winfit(string window_name) {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	canvas.fit_content = true;
	fairy.redraw_window(window_name);
}

@UI_EXPORT("update all visualizers in window", 
	[ "name of the window"])
void winrefresh(string window_name) {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	canvas.refresh = true;
	fairy.redraw_window(window_name);
}

@UI_EXPORT("periodic update of all visualizers in window", 
	["name of the window",
	 "\"true\" enables, \"false\" disables, \"toggle\" toggles automatic refresh for given window"])
void winpoll(string window_name, string action="toggle") {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	if (toggle_action(action, canvas.autorefresh)) {
		update_window_gui(window_name,true);
	}
}

@UI_EXPORT("histogram width will be measured on the filled bins instead of histogram borders", 
	["name of the window",
	 "\"true\" enables, \"false\" disables, \"toggle\" toggles autozoom setting for the given window"])
void winautozoom(string window_name, string action="toggle") {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	if (toggle_action(action, canvas.zoom)) {
		update_window_gui(window_name,true);
	}
}

@UI_EXPORT("show histogram statistics in the window", 
	["name of the window",
	 "\"true\" enables, \"false\" disables, \"toggle\" toggles statistics display for the given window"])
void winshowstats(string window_name, string action="toggle") {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	if (toggle_action(action, canvas.stats)) {
		update_window_gui(window_name,true);
	}
}

@UI_EXPORT("draw items filled, exact effect depends on itemtype.", 
	["name of the window",
	 "\"true\" enables, \"false\" disables, \"toggle\" toggles filled"])
void windrawfilled(string window_name, string action="toggle") {
	import fairy, graphics;
	auto canvas = fairy.session.get_canvas(window_name);
	if (toggle_action(action, canvas.filled)) {
		update_window_gui(window_name,true);
	}
}



@UI_EXPORT("enable/disable logscale for given axis",
		["name of window to affect",
		 "name of axis: x y z",
		 "true enables, false disables, toggle toggles logscale for given axis"
		])
void logscale(string window_name, char axis, string action="toggle") {
	import fairy, graphics;
	int axis_idx = axis_helper_xyz(axis);
	auto canvas = fairy.session.get_canvas(window_name);
	bool logscale = canvas.transform[axis_idx].logscale;
	if (toggle_action(action, logscale)) {
		if (logscale)  canvas.transform[axis_idx].set_logscale(0.1);
		if (!logscale) canvas.transform[axis_idx].set_linscale();
		update_window_gui(window_name, true);
	}
}

@UI_EXPORT("set window mode to overlayed view of all items",
	["name of the window"])
void overlay(string window_name) {
	import graphics, fairy;
	auto canvas = fairy.session.get_canvas(window_name);
	if (canvas.display_mode != DisplayMode.overlay) {
		canvas.display_mode = DisplayMode.overlay;
		update_window_gui(window_name, true);
	}
}

@UI_EXPORT("set window mode to grid mode and specify a fixed number of rows",
	["name of the window",
	 "number of rows"])
void rows(string window_name, int rows) {
	import graphics, fairy;
	auto canvas = fairy.session.get_canvas(window_name);
	if (canvas.display_mode != DisplayMode.rows || canvas.columns_or_rows != rows) {
		canvas.display_mode = DisplayMode.rows;
		canvas.columns_or_rows = rows;
		update_window_gui(window_name);
	}
}

@UI_EXPORT("set window mode to grid mode and specify a fixed number of columns",
	["name of the window",
	 "number of columns"])
void columns(string window_name, int columns) {
	import graphics, fairy;
	auto canvas = fairy.session.get_canvas(window_name);
	if (canvas.display_mode != DisplayMode.columns || canvas.columns_or_rows != columns) {
		canvas.display_mode = DisplayMode.columns;
		canvas.columns_or_rows = columns;
		update_window_gui(window_name);
	}
}

@UI_EXPORT("autoscale given axis in given window", 
	[ "name of the window",
	  "name of axis (x or y or z)",
	  "true enables, false disables, toggle changes automatic x-axis scaling"] )
void autoscale(string window_name, char axis, string action="toggle") {
	import graphics, fairy;
	if (toggle_action(action, fairy.session.get_canvas(window_name).autoscale[axis_helper_xyz(axis)])) {
		update_window_gui(window_name, true);
	}
}

@UI_EXPORT("show grid for given axis", 
	[ "name of the window",
	  "\"top\" or name of axis (x or y)",
	  "true enables, false disables, toggle changes automatic x-axis scaling"] )
void grid(string window_name, string axis, string action="toggle") {
	import graphics, fairy;
	if (axis == "top") {
		if (toggle_action(action, fairy.session.get_canvas(window_name).grid_ontop)) {
			update_window_gui(window_name, true);
		}
	} else if (toggle_action(action, fairy.session.get_canvas(window_name).grid[axis_helper_xy(axis[0])])) {
		update_window_gui(window_name, true);
	}
}

@UI_EXPORT("show numbers for given axis", 
	[ "name of the window",
	  "\"top\" or name of axis (x or y)",
	  "true enables, false disables, toggle changes automatic x-axis scaling"] )
void numbers(string window_name, string axis, string action="toggle") {
	import graphics, fairy;
	if (axis == "top") {
		if (toggle_action(action, fairy.session.get_canvas(window_name).numbers_ontop)) {
			update_window_gui(window_name, true);
		}
	} else if (toggle_action(action, fairy.session.get_canvas(window_name).numbers[axis_helper_xy(axis[0])])) {
		update_window_gui(window_name, true);
	}
}

@UI_EXPORT("show axis label for given axis", 
	[ "name of the window",
	  "name of axis (x or y)",
	  "true enables, false disables, toggle changes current setting"] )
void label(string window_name, string axis, string action="toggle") {
	import graphics, fairy;
  if (toggle_action(action, fairy.session.get_canvas(window_name).axislabel[axis_helper_xy(axis[0])])) {
		update_window_gui(window_name, true);
	}
}


@UI_EXPORT("draw color bar in window",
	["name of the window",
	 "true, false, or toggle"])
void colorbar(string window_name, string action = "toggle") {
	import graphics, fairy;
	if (toggle_action(action, fairy.session.get_canvas(window_name).color_bar)) {
		update_window_gui(window_name, true);
	}
}


@UI_EXPORT("render window in ascii text")
@trusted
string winshow(string name, string mode = "double", int w = -1, int h = -1) {
	import std.stdio;
	import std.typecons, std.array, std.algorithm, std.conv;
	// find terminal dimensions (lines and columns)
	int tty_w, tty_h;	
	version(windows) {
		// TODO: implement
	} else {
		import core.sys.posix.unistd, core.sys.posix.sys.ioctl;
		winsize ws;
		ioctl(STDIN_FILENO, TIOCGWINSZ, &ws);
		tty_h = ws.ws_row;
		tty_w = ws.ws_col;
	}
	if (w<0) w = tty_w;
	if (h<0) h = tty_h-2;

	// create a renderer with the correct mode
	import fairy, asciirender;
	import std.typecons;
	AsciiRender.Mode m = (mode=="quad")?AsciiRender.Mode.quad_pixel:(
		               	 (mode=="double")?AsciiRender.Mode.double_pixel:AsciiRender.Mode.single_pixel
		                 );
	if (m==AsciiRender.Mode.quad_pixel || m==AsciiRender.Mode.double_pixel) h *= 2;
	if (m==AsciiRender.Mode.quad_pixel) w *= 2;
	auto renderer = new AsciiRender(w,h,m);

	// adapt the canvas properties to better match the requirements of ascii rendering
	// e.g. a grid is only disturbing at such low resolutions
	import fairy, graphics;
	CanvasProperties* canvas = fairy.session.get_canvas(name);
	auto w_safe = canvas.width;
	auto h_safe = canvas.height;
	bool[2] grid_safe = canvas.grid;
	canvas.width  = w;
	canvas.height = h;
	canvas.grid = [false,false]; 
	CanvasPainter(canvas, renderer).draw_content;

	canvas.width = w_safe;
	canvas.height = h_safe;
	canvas.grid = grid_safe;

	// return the output of the ascii renderer
	return name~"("~w.to!string~"x"~h.to!string~")\n"~renderer.render;
}

@UI_EXPORT("list all windows")
@trusted
string winls() {
	import fairy;
	return fairy.session.list_windows();
}

@UI_EXPORT("execute shell command",
	       ["Command and arguments, for example: shell [\"ls\",\"..\"]"])
@trusted
string shell(string[] args) {
	import std.process;
	return execute(args).output;
}

//////////////////////////////////////
// elderpt user interface
//////////////////////////////////////
version (elderpt) {

@UI_EXPORT("control elderpt thread", 
	["start restart status pause continue stop rate config",
	 "elderpt configuration file",
	 "mbs source: eg. file:run001.lmd or stream:x86l-xyz"])
@trusted
string elderpt(string command, string config_file = null, string mbs_source = null, string[] more_sources = null) {
	import elderpt;
	import std.concurrency;
	string[] sources;
	if (mbs_source !is null && mbs_source != "") sources ~= mbs_source;
	if (more_sources !is null) sources ~= more_sources;
	if (command == "start") {
		if (elderpt.running) throw new Exception("elderpt already running, try \"elderpt stop\" or \"elderpt restart\"");

		if (config_file is null) config_file = "analysis.config";
		elderpt.configname = config_file;
		elderpt.sourcename = sources.dup;
		elderpt.tid = spawn(&run_elderpt, thisTid, config_file, sources.idup);
		receive(
			(MsgAck msg) {elderpt.running = true;},
			(MsgErr msg) {throw new Exception("elderpt couldn't start");}	
		);
	}
	if (command == "restart") {
		if (!elderpt.running) throw new Exception("elderpt is not running");
		else { // stop first
			elderpt.tid.send(MsgStop());
			receive((MsgAck msg) {});
			elderpt.running = false;
		}
		elderpt.tid = spawn(&run_elderpt, thisTid, elderpt.configname, elderpt.sourcename.idup);
		receive(
			(MsgAck msg) {elderpt.running = true;},
			(MsgErr msg) {throw new Exception("elderpt couldn't start");}	
		);
	}
	if (command == "status") {
		if (!elderpt.running) return "stopped";
		if (elderpt.running && elderpt.paused)   return "paused";
		return "running";
	}
	if (command == "config") {
		if (config_file !is null) elderpt.configname = config_file;
		return elderpt.configname;
	}
	if (command == "source") {
		import std.array;
		if (mbs_source !is null) elderpt.sourcename = [mbs_source];
		if (more_sources !is null) elderpt.sourcename ~= more_sources;
		return elderpt.sourcename.join(' ');
	}
	if (command == "pause") {
		if (!elderpt.running) throw new Exception("elderpt is not running");
		if (elderpt.paused)   throw new Exception("elderpt is already paused");
		elderpt.paused = true;
		elderpt.tid.send(MsgPause());
		receive((MsgAck msg) {});
	}
	if (command == "continue") {
		if (!elderpt.running) throw new Exception("elderpt is not running");
		if (!elderpt.paused)   throw new Exception("elderpt is not paused");
		elderpt.paused = false;
		elderpt.tid.send(MsgContinue());
		receive((MsgAck msg) {});
	}
	if (command == "stop") {
		if (!elderpt.running) throw new Exception("elderpt is not running");
		elderpt.running = false;
		elderpt.paused = false;
		elderpt.tid.send(MsgStop());
		receive((MsgAck msg) {});
	}
	if (command == "rate") {
		if (!elderpt.running) throw new Exception("elderpt is not running");
		elderpt.tid.send(MsgGetRate());
		double rate_result = 0.0;
		receive((MsgRate msg) {
			rate_result = msg.rate;
		});
		import std.conv;
		return rate_result.to!string;
	}
	return "";
}

}



//////////////////////////////////////
// help command
//////////////////////////////////////

alias helper(alias T) = T;
@UI_EXPORT("display help for exported functions", 
	["name of a specific function"])
string help(string name = "__all") {
	import std.traits, std.conv;
	string result;
	if (name == "__all") result ~= "available commands:\n\n";

	alias mod = helper!(mixin(__MODULE__));
	static foreach(memberName; __traits(allMembers, mod)) {{
		alias member = helper!(__traits(getMember, mod, memberName));
		static if (__traits(isStaticFunction, member) && hasUiExport!member) {
			alias func = member;
			if (name == "__all") { // no specific function was requested
				auto num_spaces = 20 - memberName.length;
				result ~= memberName;
				foreach(i;0..num_spaces) result ~= ' ';
				result ~= getAttribute!(func,UI_EXPORT).description ~ "\n";
			} else {
				if (name == memberName) {
					result ~= "usage: " ~ name ~ " ";
					foreach(argName; ParameterIdentifierTuple!func) {
						result ~= " " ~ argName;
					}
					result ~= "\n\n" ~ getAttribute!(func,UI_EXPORT).description ~ "\n";
					if (ParameterTypeTuple!func.length) {
						result ~= "Arguments:\n";
						auto arg_descriptions = getAttribute!(func,UI_EXPORT).arg_descriptions;
						foreach(idx, argName; ParameterIdentifierTuple!func) {
							static if (is(ParameterDefaultValueTuple!func[idx] == void)) {
								string defaultValue = null;
							} else {
								string defaultValue = ParameterDefaultValueTuple!func[idx].to!string;
							}
							string argDesc = "?";
							if (idx < arg_descriptions.length) {
								argDesc = arg_descriptions[idx];
							}
							string argType = ParameterTypeTuple!func[idx].stringof;
							result ~= "    " ~ argName ~ " (" ~ argType ~ "): " ~ argDesc;
							if (defaultValue !is null) {
								result ~= " [default=" ~ defaultValue ~ "]";
							} 
							result ~= "\n";
						}
					}
				}
			}
		}
	}}
	if (name == "__all") result ~= "\n\"help <command>\" provides details about a specific command";
	return result;
}
