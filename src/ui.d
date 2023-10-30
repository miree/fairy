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

///////////////////////////////////////////////////////////////////////
// all user interface functions are here
///////////////////////////////////////////////////////////////////////

@UI_EXPORT("save current session and open a new one",
	["new session name, file does not exist a new session is created"])
string session_open(string session_name) {
	import fairy, histogram;
	fairy.session.write_to_file();
	fairy.session.close();
	fairy.session.name = session_name;
	fairy.session.read_from_file();

	import std.stdio;
	fairy.session.windows.byKey.writeln();
	if (start_gui) {// gui is already running
		foreach (name, ref window; fairy.session.windows) {
			if (fairy.main_gui !is null) {
				fairy.main_gui.add_window(name,window);
			}
		}
	}
	return "";
}

@UI_EXPORT("save current session under new name",
	["new session name, file is immediately written"])
string session_save(string session_name) {
	import fairy, histogram;
	fairy.session.name = session_name;
	fairy.session.write_to_file();
	return "";
}


@UI_EXPORT("print info abut alsa", 
	["alsa device name"])
@trusted
string alsainfo(string alsa_device = "default") {
	import alsa;
	import std.conv;
	string result = "maximum number of channels " ~ alsa_get_max_channels(alsa_device).to!string;
	auto minmax_rates = alsa_get_minmax_rates(alsa_device);
	result ~= "\nminimum sampling rate " ~ minmax_rates[0].to!string;
	result ~= "\nmaximum sampling rate " ~ minmax_rates[1].to!string;

	return result;
}



@UI_EXPORT("list all items",
	["include items that are not initialized (because their type could not be recognized while reading the session file"])
@trusted
string ls(bool all = true) {
	import fairy;
	return fairy.session.list_items(all);
}


@UI_EXPORT("add histogram that refers to a file on disk",
	["filename to load the data from"])
string filehistogram(string filename) {
	import fairy, histogram;
	fairy.session.add_item(filename, new FileHistogram(FileHistogram.Data(filename)));
	return "";
}

@UI_EXPORT("add waveform ",
	["name for the new item",
	 "number of sample points"])
string wave(string name) {
	import fairy, waveform;
	double[] waveform_data = [
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
	 "name of window on which the item should be shown"])
string show(string item_name, string window_name) {
	import fairy;
	import std.algorithm;
	auto canvas = fairy.session.get_canvas(window_name);
	auto visual = fairy.session.get_visual_item(item_name);
	if (!canvas.itemnames.canFind(item_name)) {
		canvas.itemnames ~= item_name;
		if (canvas.itemnames.length==1) {
			import std.stdio;
			//canvas.fit_content = true;
			canvas.dim = 0; 
			//canvas.transform[0].logscale = false;
			//canvas.transform[1].logscale = false;
			//canvas.transform[2].logscale = false;
		}
	} else {
		string[] itemnames;
		foreach(item; canvas.itemnames) {
			if (item != item_name) {
				itemnames ~= item;
			}
		}
		canvas.itemnames = itemnames;
	}
	fairy.redraw_window(window_name);
	return "";
}




@UI_EXPORT("quit program")
@trusted
string quit() {
	import cmdline;
	import std.concurrency;
	import fairy;
	fairy.running = false;
	return "";
}

@UI_EXPORT("enable gui sysbem")
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


@UI_EXPORT("create new window")
@trusted
string win(string name, int width = 600, int height = 400, int xpos = -1, int ypos = -1) {
	import fairy;
	fairy.session.add_window(name, width, height, xpos, ypos);
	return "created new window "~name;
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
		fairy.redraw_window(window_name);
	}
}

@UI_EXPORT("set window mode to overlayed view of all items",
	["name of the window"])
void overlay(string window_name) {
	import graphics, fairy;
	auto canvas = fairy.session.get_canvas(window_name);
	if (canvas.display_mode != DisplayMode.overlay) {
		canvas.display_mode = DisplayMode.overlay;
		fairy.redraw_window(window_name);
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
		fairy.redraw_window(window_name);
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
		fairy.redraw_window(window_name);
	}
}

@UI_EXPORT("autoscale given axis in given window", 
	[ "name of the window",
	  "name of axis (x or y or z)",
	  "true enables, false disables, toggle changes automatic x-axis scaling"] )
void autoscale(string window_name, char axis, string action="toggle") {
	import graphics, fairy;
	if (toggle_action(action, fairy.session.get_canvas(window_name).autoscale[axis_helper_xyz(axis)])) {
		fairy.redraw_window(window_name);
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
			fairy.redraw_window(window_name);
		}
	} else if (toggle_action(action, fairy.session.get_canvas(window_name).grid[axis_helper_xy(axis[0])])) {
		fairy.redraw_window(window_name);
	}
}


@UI_EXPORT("draw color bar in window",
	["name of the window",
	 "true, false, or toggle"])
void colorbar(string window_name, string action = "toggle") {
	import graphics, fairy;
	if (toggle_action(action, fairy.session.get_canvas(window_name).color_bar)) {
		fairy.redraw_window(window_name);
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
	auto renderer = scoped!AsciiRender(w,h,m);

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
