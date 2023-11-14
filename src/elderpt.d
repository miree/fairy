module elderpt;
@trusted:

pragma(lib, "elderpt-0.1");


import std.concurrency;
Tid main_thread;

bool running = false;
bool paused  = false;
Tid  tid;


@trusted
static ~this() {
	if (running) {
		tid.send(MsgStop());
		receive((MsgAck msg) {});
	}
}


// D bindings for the elderpt C interface
extern(C) void* elder_pt_interface_create(ElderPT_VisConInterface iface);
extern(C) void* elder_pt_controller_create(const char *filename, void *iface);
extern(C) void  elder_pt_controller_clear(void *controller);
extern(C) void  elder_pt_controller_unpack(void *controller, void *iface, void *evt);
extern(C) void  elder_pt_controller_process(void *controller, void *iface);
extern(C) void  elder_pt_controller_idle(void *controller, void *iface);
extern(C) void 	elder_pt_interface_destroy(void *iface);
extern(C) void 	elder_pt_controller_destroy(void *ctrl);
extern(C) void* elder_pt_event_create();
extern(C) void  elder_pt_event_destroy(void *evt);
extern(C) void  elder_pt_event_clear(void *evt, 
						  uint number,
						  uint type,
						  uint trigger,
						  uint time,
						  uint msec,
						  ulong timestamp);
extern(C) void  elder_pt_event_add_subevent(void *evt, 
								 uint procid, 
								 uint type, 
								 uint subtype, 
								 uint control, 
								 uint subcrate, 
								 uint length, 
								 const uint *data,
								 uint more_data_length = 0,
								 const uint *more_data = null);

// implementation of the elderpt VisCon-Interface
string fix_name(string itemname) {
	import std.range, std.string;
	string[] parts = itemname.split("/");
	if (parts[0] == "crates") {
		parts = parts[1..$];
	}
	parts[$-1] = parts[$-1].chompPrefix(parts[0..$-1].join("_")~"_");
	itemname = parts.join("/");
	return itemname;
}

import histogram;
Hist1[] elder_histograms_1D;
int elder_histograms_1D_count;
struct MsgHist1dCreate {
	string name;
	shared Hist1 hist;
}
extern(C) int hist1d_create(const char *name,
			   const char *title,
			   const char *axis,
			   int n_bins,
			   double left,
			   double right) 
{
	import std.conv;
	int handle = elder_histograms_1D_count++;
	string itemname = fix_name(name.to!string);
	if (elder_histograms_1D.length <= handle) {
		elder_histograms_1D.length = handle+1;
	}
	elder_histograms_1D[handle] = new Hist1(n_bins, left, right);
	main_thread.send(MsgHist1dCreate(itemname, cast(shared Hist1)(elder_histograms_1D[handle])));
	return handle;
}
//void handle_MsgHist1dCreate(MsgHist1dCreate msg) {
//	import fairy, item;
//	import std.stdio;
//	bool allow_replace = true;
//	fairy.session.add_item(msg.name, cast(Hist1)msg.hist, NameCollisionPolicy.replace);
//}

extern(C) void hist1d_fill(int handle, double value) {
	if (handle < elder_histograms_1D.length) {
		elder_histograms_1D[handle].fill(value);
	}
}
extern(C) void hist1d_set_bin(int handle, int bin, double value) {
	import std.stdio;
	//writeln("hist1d_set_bin " , handle, " ", bin, " ", value);
	if (handle < elder_histograms_1D.length) {
		elder_histograms_1D[handle].set_bin(bin, value);
	}
}

Hist2[] elder_histograms_2D;
int elder_histograms_2D_count;
struct MsgHist2dCreate {
	string name;
	shared Hist2 hist;
}
extern(C) int hist2d_create(const char *name,
							const char *title,
							const char *axis1,
							int n_bins1,
							double left1,
							double right1,
							const char *axis2,
							int n_bins2,
							double left2,
							double right2)
{
	import std.conv;
	int handle = elder_histograms_2D_count++;
	string itemname = fix_name(name.to!string);
	if (elder_histograms_2D.length <= handle) {
		elder_histograms_2D.length = handle+1;
	}
	elder_histograms_2D[handle] = new Hist2(n_bins1, n_bins2, 
											left1, right1, 
											left2, right2);
	main_thread.send(MsgHist2dCreate(itemname, cast(shared Hist2)(elder_histograms_2D[handle])));
	return handle;
}
//void handle_MsgHist2dCreate(MsgHist2dCreate msg) {
//	import fairy, item;
//	import std.stdio;
//	fairy.session.add_item(msg.name, cast(Hist2)msg.hist, NameCollisionPolicy.replace);
//}

extern(C) void hist2d_fill(int handle, double value1, double value2) {
	if (handle < elder_histograms_2D.length) {
		elder_histograms_2D[handle].fill(value1, value2);
	}	
}
extern(C) void hist2d_set_bin(int handle, int bin1, int bin2, double value) {
	if (handle < elder_histograms_2D.length) {
		elder_histograms_2D[handle].set_bin(bin1, bin2, value);
	}
}

//import range;
//Range[] elder_ranges_1D;
//import std.datetime.stopwatch;
//StopWatch[int] sw_1d_gates;
//struct MsgRange1dCreate {
//	int handle;
//	string name;
//	double left;
//	double right;
//}
extern(C) int cond1d_create(const char *name,
							double left,
							double right,
							int handle) {
	//// ignore handle argument (this refers to an exisiting histogram, but our ranges are standalone) 
	//import std.conv;
	//int rhandle = cast(int)elder_ranges_1D.length;
	//elder_ranges_1D ~= new Range(left,right);
	//main_thread.send(MsgRange1dCreate(rhandle, name.to!string, left, right));
	//sw_1d_gates[rhandle] = StopWatch();
	//sw_1d_gates[rhandle].start();
	//return rhandle;
	return 0;
}
//struct MsgRange1dChange {
//	int handle;
//	double left;
//	double right;
//}
extern(C) void cond1d_get(int handle,
							double *left,
							double *right) {
	//import std.datetime;
	//*left  = elder_ranges_1D[handle].getValue1();
	//*right = elder_ranges_1D[handle].getValue2();
	//if (sw_1d_gates[handle].peek.total!"msecs" > 100) { // limit the rate of checking for changes
	//	main_thread.send(MsgRange1dChange(handle,*left,*right));
	//	sw_1d_gates[handle].reset();
	//}
}

//import rectangle;
//import polygon;
//Rectangle[] elder_rectangles;
//Polygon[]   elder_polygons;
//StopWatch[int] sw_2d_gates;
//struct MsgRectangleCreate {
//	int handle;
//	string name;
//	double x1,y1,x2,y2;
//}
//struct MsgPolygonCreate {
//	int handle;
//	string name;
//	immutable(double)[] points;
//}
extern(C) int cond2d_create(const char *name,
							int num_points,
							double *points,
							int handle) {
	//// ignore handle 
	//import std.conv;
	//string itemname = name.to!string;
	//if (num_points == 4) {
	//	int rhandle = cast(int)elder_rectangles.length;
	//	// elder uses the four values as: left,right,bottom,top 
	//	// while the fairy rectangle uses x1,y1, x2,y2
	//	elder_rectangles ~= new Rectangle(points[0], points[2], points[1], points[3]);
	//	elder_polygons ~= null;
	//	main_thread.send(MsgRectangleCreate(rhandle, name.to!string, points[0], points[2], points[1], points[3]));
	//	sw_2d_gates[rhandle] = StopWatch();
	//	sw_2d_gates[rhandle].start();
	//	return rhandle;
	//} else if (num_points > 4) {
	//	int rhandle = cast(int)elder_polygons.length;
	//	double[] values = new double[num_points];
	//	for (int i = 0; i < num_points; ++i) {
	//		values[i] = points[i];
	//	}
	//	elder_polygons ~= new Polygon(values);
	//	elder_rectangles ~= null;
	//	main_thread.send(MsgPolygonCreate(rhandle, name.to!string, values.idup));
	//	sw_2d_gates[rhandle] = StopWatch();
	//	sw_2d_gates[rhandle].start();
	//	return rhandle;
	//}
	//return -1;
	return 0;
}
//struct MsgRectangleChange {
//	int handle;
//	double x1,y1,x2,y2;
//}
//struct MsgPolygonChange {
//	int handle;
//	immutable(double)[] points;
//}
extern(C) void cond2d_get(int handle,
							int *num_points,
							double **points) {
	//import std.datetime : dur;
	//import std.datetime.stopwatch;
	//static StopWatch sw;
	//static double[4] rect_return_values;
	//if (!sw.running) {
	//	sw.start();
	//}
	//if (elder_rectangles[handle] !is null) {
	//	rect_return_values[0] = elder_rectangles[handle].getX1();
	//	rect_return_values[1] = elder_rectangles[handle].getX2();
	//	rect_return_values[2] = elder_rectangles[handle].getY1();
	//	rect_return_values[3] = elder_rectangles[handle].getY2();
	//	*num_points = 4;
	//	*points = &rect_return_values[0];
	//	if (sw_2d_gates[handle].peek.total!"msecs" > 100) { // limit the rate of checking for changes
	//		main_thread.send(MsgRectangleChange(handle,rect_return_values[0],rect_return_values[2],rect_return_values[1],rect_return_values[3]));
	//		sw_2d_gates[handle].reset();
	//	}
	//	return;
	//}
	//if (elder_polygons[handle] !is null) {
	//	double[] values = elder_polygons[handle].getValues;
	//	*num_points = cast(int)values.length;
	//	*points = values.ptr;
	//	if (sw_2d_gates[handle].peek.total!"msecs" > 100) { // limit the rate of checking for changes
	//		main_thread.send(MsgPolygonChange(handle,values.dup));
	//		sw_2d_gates[handle].reset();
	//	}
	//	return;
	//}
	//*num_points = 0;
	return;
}

struct ElderPT_VisConInterface
{
	extern(C) int function(const char *name,
	                       const char *title,
	                       const char *axis,
	                       int n_bins,
	                       double left,
	                       double right) _hist1d_create = &hist1d_create;
	extern(C) void function(int handle, double value ) _hist1d_fill = &hist1d_fill;
	extern(C) void function(int handle, int bin, double value) _hist1d_set_bin = &hist1d_set_bin;
	extern(C) int function(const char *name,
	                       const char *title,
	                       const char *axis1,
	                       int n_bins1,
	                       double left1,
	                       double right1,
	                       const char *axis2,
	                       int n_bins2,
	                       double left2,
	                       double right2) _hist2d_create = &hist2d_create;
	extern(C) void function(int handle, double value1, double value2 ) _hist2d_fill = &hist2d_fill;
	extern(C) void function(int handle, int bin1, int bin2, double value) _hist2d_set_bin = &hist2d_set_bin;

	extern(C) int function(const char *name,
	                       double left,
	                       double right,
	                       int handle) _cond1d_create = &cond1d_create;
	extern(C) void function(int handle,
	                        double *left,
	                        double *right) _cond1d_get = &cond1d_get;
	extern(C) int function(const char *name,
	                       int num_points,
	                       double *points,
	                       int handle) _cond2d_create = &cond2d_create;
	extern(C) void function(int handle,
	                        int *num_points,
	                        double **points) _cond2d_get = &cond2d_get;
}
ElderPT_VisConInterface elder_interface;



// Elder settings window
// all the GtkD stuff start an application and make GUI windows
/+import gio.Application : GioApplication = Application;
import gtk.Application;
import gtk.ApplicationWindow;

import item, app;
import std.concurrency;

private bool          elderpt_paused;
private bool          elderpt_running;
private bool          elderpt_closed;
private string        elderpt_old_status_label;
private uint          elderpt_gdk_thread;

class ElderPtWindow : ApplicationWindow
{

	import gtk.RadioButton;
	import gtk.Box;
	import gtk.Button;
	import gtk.Label;
	import gtk.Separator;
	import gtk.Entry;
	import gtk.ToggleButton;
	import gtk.Button;
	import std.stdio;
	import gtk.FileChooserButton;

	Tid _acquisition_thread;

	Button        _start_acquisition_button;
	Button        _pause_acquisition_button;
	Button        _stop_acquisition_button;
	Label         _status_label;
	Label 		  _rate_label;
	FileChooserButton _elder_config_file_chooser_button;
	string _elder_toplevel_config_file;
	version(MbsApi_support) {
		import mbsapi;
		Entry           _mbs_source;
		Button          _mbs_source_select_button;
		string[]        _mbs_source_files;
		void*           _mbs_channel;
		sMbsFileHeader* _mbs_file_header;
		bool            _mbs_file_open;
		bool            _mbs_end_of_file;
		void*           _elderpt_event;
	}

	bool _end_thread_idle_process = false;

	static void quit_acquisition_thread() {
		elderpt_running = false;
		elderpt_closed = true;
		elderpt_paused = false;
	}
	this(Application application) {
		super(application);
		setDefaultSize( 100, 100 );
		elderpt_closed = false;

		auto box = new Box(GtkOrientation.VERTICAL,0);

		auto elder_config_file_box = new Box(GtkOrientation.HORIZONTAL,0);
		elder_config_file_box.add(new Label(" ElderPT toplevel config file: "));
		_elder_config_file_chooser_button = new FileChooserButton("choose file", FileChooserAction.OPEN);
		_elder_config_file_chooser_button.addOnFileSet((button) {
			auto filenamelist = button.getFilenames();
			if (filenamelist !is null) {
				string[]  filenames = filenamelist.toArray!string;
				if (filenames !is null && filenames.length > 0) {
					_elder_toplevel_config_file = filenames[0];
				}
			} else {
				_elder_toplevel_config_file = null;
			}
		});
		elder_config_file_box.add(_elder_config_file_chooser_button);
		box.add(elder_config_file_box);

		version(MbsApi_support) {
			//auto mbs_source_box = new Box(GtkOrientation.HORIZONTAL,0);
			//mbs_source_box.add(new Label(" MBS Source: "));
			//_mbs_source = new Entry;
			//mbs_source_box.add(_mbs_source);
			//_mbs_source_select_button = new Button("Choose file", (widget) {
			//	import gtk.FileChooserDialog, gtk.Dialog, gtk.FileFilter; 
			//	auto dialog = new FileChooserDialog("choose MBS source files", /*parent_window=*/this, FileChooserAction.OPEN);
			//		auto lmd_fiter = new FileFilter; 
			//		     lmd_fiter.addPattern("*.lmd");
			//		     lmd_fiter.setName("*.lmd");
			//		dialog.addFilter(lmd_fiter);
			//		dialog.setSelectMultiple(true);
			//		dialog.addOnResponse((int response, Dialog dialog) {
			//			if (response == ResponseType.OK) {
			//				import std.algorithm, std.path, std.file, std.string, std.stdio, platform, histogram;
			//				auto cwd = getcwd().fixWindowsPaths();
			//				auto filenames = (cast(FileChooserDialog)dialog).getFilenames().toArray!string.map!(a=>a.fixWindowsPaths().chompPrefix(cwd~"/"));
			//				string sources;
			//				foreach(filename; filenames) { sources ~= filename ~ " "; }
			//				writeln("sources = ", sources);
			//				_mbs_source.setText(sources);
			//			} 
			//			if (response == ResponseType.CANCEL) dialog.close(); 
			//		});
			//	dialog.show();

			//});
			//mbs_source_box.add(_mbs_source_select_button);
			//box.add(mbs_source_box);

		}


		auto control_box = new Box(GtkOrientation.HORIZONTAL,0);
		_status_label = new Label(elderpt_running?" Running ":" Stopped ");
		_rate_label = new Label(" Rate(evt/s) = 0");
		control_box.add(new Label(" Acquisition Control: "));
		_start_acquisition_button = new Button("start", 
			delegate(Button button) {
				thisTid().setMaxMailboxSize(10000, OnCrowding.block);
				_status_label.setLabel(" Running ");// ~ _filename);
				import std.concurrency;
				import gdk.Threads;

				if (_elder_toplevel_config_file !is null) {
					button.setSensitive(false);
					import threads;
					_acquisition_thread = spawn(&elderpt_thread_function, thisTid, _elder_toplevel_config_file);
					register_thread(_acquisition_thread);
					thisTid.setMaxMailboxSize(1024, OnCrowding.block);
					import core.time;
					//_events_per_second = 0;
					//_t_events_per_second_reset = MonoTime.currTime();
					_end_thread_idle_process = false;
					elderpt_gdk_thread = gdk.Threads.threadsAddIdle(&elderptThreadIdleProcess, cast(void*)this);
					_stop_acquisition_button.setSensitive(true);
					_pause_acquisition_button.setSensitive(true);
					elderpt_running = true;
				} else {
					import gtk.MessageDialog, gtk.Dialog;
					auto message = new MessageDialog(this, 
													 DialogFlags.MODAL, 
													 MessageType.ERROR, 
													 ButtonsType.CLOSE, 
													 "select device or file!");
					message.addOnResponse( delegate void(int, Dialog d) {d.hide();} );
					message.showAll();
				}
			});
		_pause_acquisition_button = new Button(elderpt_paused?"continue":"pause", delegate(Button button) {
				if (elderpt_paused) {
					_status_label.setLabel(elderpt_old_status_label);
					_pause_acquisition_button.setLabel("pause");
					elderpt_paused = false;
					//_events_per_second = 0;
					//_t_events_per_second_reset = MonoTime.currTime();
					_acquisition_thread.send(MsgContinue());
				} else {
					elderpt_old_status_label = _status_label.getLabel();
					_status_label.setLabel("Paused");
					_pause_acquisition_button.setLabel("continue");
					elderpt_paused = true;
					_acquisition_thread.send(MsgPause());
				}
			});

		_stop_acquisition_button = new Button("stop", delegate(Button button) {
				if (elderpt_paused == true) {
					_pause_acquisition_button.setLabel("pause");
					elderpt_paused = false;
				}
				_end_thread_idle_process = true;
				_status_label.setLabel(" Stopped ");
				_stop_acquisition_button.setSensitive(false);
				_start_acquisition_button.setSensitive(true);
				_pause_acquisition_button.setSensitive(false);	
				version(MbsApi_support) {
					_mbs_source_select_button.setSensitive(true);
				}
				elderpt_running = false;	
				_acquisition_thread.send(MsgStop());
				receiveTimeout(2000.msecs, (MsgStopAck stopack) { 
						import std.stdio;
						//writeln("received MsgStopAck");
					});
			});
		control_box.add(_start_acquisition_button);
		control_box.add(_pause_acquisition_button);
		control_box.add(_stop_acquisition_button);
		if (!elderpt_running) {
			_pause_acquisition_button.setSensitive(false);
			 _stop_acquisition_button.setSensitive(false);
		} else {
			_start_acquisition_button.setSensitive(false);
		}
		box.add(control_box);
		box.add(new Separator(GtkOrientation.HORIZONTAL));

		auto status_box = new Box(GtkOrientation.HORIZONTAL,0);
		status_box.add(_status_label);
		box.add(status_box);

		auto rate_box = new Box(GtkOrientation.HORIZONTAL,0);
		rate_box.add(_rate_label);
		box.add(rate_box);


		import gtk.Widget;
		addOnHide(delegate(Widget widget){ 
			import std.stdio;
			_end_thread_idle_process = true;
			if (_acquisition_thread !is Tid.init) {
				//writeln("send MsgStop() to _acquisition_thread");
				_acquisition_thread.send(MsgStop());
				if (elderpt_running || elderpt_paused) {
					//writeln("_acquisition_thread active... wait for MsgStopAck");
					receiveTimeout(2000.msecs, (MsgStopAck stopack) { 
							import std.stdio;
							//writeln("received MsgStopAck");
						});
				}
				
			}
			elderpt_running = false;
			elderpt_paused = false;
			elderpt_closed = true;
			//writeln("exit onHide callback");
		});
		add(box);
		showAll();
	}
	~this() {
		_end_thread_idle_process = true;
		if (_acquisition_thread !is Tid.init) {
			_acquisition_thread.send(MsgStop());
			receiveTimeout(2000.msecs, (MsgStopAck stopack) { 
					import std.stdio;
					//writeln("elderpt destructor received MsgStopAck");
				});		
		}
	}
}
+/
struct MsgPause {}
struct MsgContinue {}
struct MsgStop {}
struct MsgAck {}
//struct MsgStopAck {} // sent in response to MsgStop
//struct MsgEventsPerSecond {long events;}
void run_elderpt(Tid main_thread_tid, string config_filename) {
	import std.datetime;
	main_thread = main_thread_tid;

	void *iface = elder_pt_interface_create(elder_interface);
	string name = "analysis.config";
	if (config_filename !is null) {
		name = config_filename;
	}
	name ~= '\0';
	void *ctrl = elder_pt_controller_create(name.ptr, iface);

	scope(exit) { // clean up
		import std.stdio;
		writeln("run elderpt -> scope(exit): destroy ctrl and iface");
		elder_pt_controller_destroy(ctrl);
		ctrl = null;
		elder_pt_interface_destroy(iface);
		iface = null;
	}

	import std.datetime;

	auto evt = elder_pt_event_create();
	bool paused = false;
	bool stop = false;
	for (uint i; ;++i) {
		if (!paused) {
			auto t = Clock.currTime;
			uint time_secs = cast(uint)t.toUnixTime;
			auto timeval = t.toTimeVal;
			uint timestamp = 0;
			uint frac_msecs = cast(uint)(timeval.tv_usec/1e3);
			elder_pt_event_clear(evt, i, 1, 1, time_secs, frac_msecs, timestamp);
			elder_pt_controller_clear(ctrl);
			elder_pt_controller_unpack(ctrl, iface, evt);
			elder_pt_controller_process(ctrl, iface);
		}
		receiveTimeout(paused?100.msecs:Duration.zero,
			(MsgPause    msg) { paused = true;  main_thread.send(MsgAck()); },
			(MsgContinue msg) { paused = false; main_thread.send(MsgAck()); },
			(MsgStop     msg) { stop   = true;  main_thread.send(MsgAck()); });
		if (stop) break;
	}
	elder_pt_event_destroy(evt);
}


//extern(C) nothrow static int elderptThreadIdleProcess(void* data) {
//	//Don't let D exceptions get thrown from this function
//	try {
//		import std.stdio, std.datetime;
//		import app;
//		ElderPtWindow window = cast(ElderPtWindow)data;
		
//		// only handle a maximum number of events in one go, because 
//		// this function runs in the same thread as the GUI, and the 
//		// GUI will become unresponsive if we spent too much time here.
//		// Measure the time taken to handle max_in_one_go events
//		// and adapt the value if the time is above or below optimum_duration.
//		static int max_in_one_go = 1000;
//		import std.datetime.stopwatch : benchmark, StopWatch, AutoStart;
//		auto optimum_duration = 20.msecs;
//		auto sw = StopWatch(AutoStart.yes);

//		for (int i = 0; i < max_in_one_go; i++) {

//			if (!receiveTimeout(1.msecs,//Duration.zero,
//					(MsgHist1dCreate msg) {
//						runningSession.addItem(msg.name, cast(Hist1)msg.hist);
//					},
//					//(MsgHist1dFill   msg) {
//					//	if (msg.handle < elder_histograms_1D.length) {
//					//		elder_histograms_1D[msg.handle].fill(msg.value);
//					//	}
//					//},
//					//(MsgHist1dSetBin msg) {
//					//	if (msg.handle < elder_histograms_1D.length) {
//					//		elder_histograms_1D[msg.handle].setBin(msg.bin, msg.value);
//					//	}
//					//},
//					(MsgHist2dCreate msg) {
//						//string itemname = fix_name(msg.name);
//						//if (elder_histograms_2D.length <= msg.handle) {
//						//	elder_histograms_2D.length = msg.handle+1;
//						//}
//						//elder_histograms_2D[msg.handle] = new Hist2(msg.n_bins1, msg.n_bins2, 
//						//											msg.left1, msg.right1, msg.axis1,
//						//											msg.left2, msg.right2, msg.axis2,
//						//											"Counts");

//						runningSession.addItem(msg.name, cast(Hist2)msg.hist);
//					},
//					//(MsgHist2dFill   msg) {
//					//	if (msg.handle < elder_histograms_2D.length) {
//					//		elder_histograms_2D[msg.handle].fill(msg.value1, msg.value2);
//					//	}
//					//},
//					//(MsgHist2dSetBin msg) {
//					//	if (msg.handle < elder_histograms_2D.length) {
//					//		elder_histograms_2D[msg.handle].setBin(msg.bin1, msg.bin2, msg.value);
//					//	}
//					//},
//					(MsgRange1dCreate msg) {
//						string itemname = fix_name(msg.name);
//						if (elder_ranges_1D.length <= msg.handle) {
//							elder_ranges_1D.length = msg.handle + 1;
//						}
//						elder_ranges_1D[msg.handle] = new Range(msg.left, msg.right);
//						runningSession.addItem(itemname, elder_ranges_1D[msg.handle]);
//					}, 
//					(MsgRange1dChange msg) {
//						if (msg.handle < elder_ranges_1D.length) {
//							double left = elder_ranges_1D[msg.handle].getValue1();
//							double right = elder_ranges_1D[msg.handle].getValue2();
//							if (left != msg.left || 
//								right != msg.right) {
//								window._acquisition_thread.send(MsgRange1dChange(msg.handle, left, right));
//							}
//						}
//					},
//					(MsgRectangleCreate msg) {
//						string itemname = fix_name(msg.name);
//						if (elder_rectangles.length <= msg.handle) {
//							elder_rectangles.length = msg.handle + 1;
//						}
//						elder_rectangles[msg.handle] = new Rectangle(msg.x1, msg.y1, msg.x2, msg.y2);
//						runningSession.addItem(itemname, elder_rectangles[msg.handle]);
//					},
//					(MsgRectangleChange msg) {
//						if (msg.handle < elder_rectangles.length) {
//							double x1 = elder_rectangles[msg.handle].getX1();
//							double y1 = elder_rectangles[msg.handle].getY1();
//							double x2 = elder_rectangles[msg.handle].getX2();
//							double y2 = elder_rectangles[msg.handle].getY2();
//							if (x1 != msg.x1 || x2 != msg.x2 || y1 != msg.y1 || y2 != msg.y2) {
//								//import std.stdio;
//								//writeln("window different");
//								window._acquisition_thread.send(MsgRectangleChange(msg.handle, x1,y1, x2,y2));
//							}
//						}
//					},
//					(MsgPolygonCreate msg) {
//						string itemname = fix_name(msg.name);
//						if (elder_polygons.length <= msg.handle) {
//							elder_polygons.length = msg.handle + 1;
//						}
//						elder_polygons[msg.handle] = new Polygon(msg.points.dup);
//						runningSession.addItem(itemname, elder_polygons[msg.handle]);
//					},
//					(MsgPolygonChange msg) {
//						if (msg.handle < elder_polygons.length) {
//							//import std.stdio;
//							//writeln("MsgPolygonChange");
//							double[] points = elder_polygons[msg.handle].getValues();
//							if (points.length != msg.points.length || points[] != msg.points[]) {
//								//writeln("polygon different");
//								window._acquisition_thread.send(MsgPolygonChange(msg.handle, points.idup));
//							}
//						}
//					},
//					(MsgEventsPerSecond msg) {
//						import std.conv;
//						window._rate_label.setLabel(" Rate(evt/s) = " ~ std.conv.to!string(msg.events));
//					}
//				)) { 
//				// if receiveTimout returns false, i.e. timeout was hit, break the for loop
//				break; 
//			} 

//			if (i==max_in_one_go-1) {
//				// adapt the max_in_one_go number of events
//				// based on the measured time it took to process
//				sw.stop();
//				if (sw.peek() > optimum_duration) {
//					max_in_one_go /= 2;
//					if (max_in_one_go < 10) {
//						max_in_one_go = 10;
//					}
//				} else {
//					max_in_one_go *= 2;
//					if (max_in_one_go > 100000) {
//						max_in_one_go = 100000;
//					}
//				}
//			}
//		}


//		if (window._end_thread_idle_process) {
//			//writeln("return false on idle thread");
//			return false;
//		}

//		return true;
//	} catch (Throwable t) {
//		return false;
//	}
//}	


