module elderpt;
@trusted:

pragma(lib, "elderpt-0.1");


import std.concurrency;
Tid main_thread;

bool running = false;
bool paused  = false;
__gshared bool done = false; // this is only written by this thread, but may be read by other threads

import serializeJSON;
struct State {
	@SERIALIZE string configname = "analysis.config";
	@SERIALIZE string[] sourcename = [];
	@SERIALIZE bool winopen;
	@SERIALIZE int winpos_x;
	@SERIALIZE int winpos_y;
}
State state;
//string configname = "analysis.config";
//string[] sourcename = [];
Tid  tid;

// D bindings for the elderpt C interface
extern(C) void* elder_pt_interface_create(ElderPT_VisConInterface iface);
extern(C) void* elder_pt_controller_create(const char *filename, void *iface);
extern(C) int   elder_pt_controller_errors(void *controller);
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

string[] elder_traces; // traces are anyway expensive. They are not shared but completely send via message passing after filling is finished
double[][] elder_trace_buffers;
int elder_trace_count;
struct MsgTraceCreate {
	string name;
	string title;
	string axis;
	int length;
}
struct MsgTraceUpdate {
	immutable string name;
	immutable double[] content;
}
extern(C) int trace_create(const char *name,
	                       const char *title,
	                       const char *axis,
	                       int length) 
{
	import std.conv;
	int handle = elder_histograms_1D_count++;
	string itemname = fix_name(name.to!string);
	import std.string;
	if (elder_traces.length <= handle) {
		elder_traces.length = handle+1;
	}
	if (elder_trace_buffers.length <= handle) {
		elder_trace_buffers.length = handle+1;
	}

	elder_traces[handle] = itemname;
	elder_trace_buffers[handle] = new double[length];
	elder_trace_buffers[handle][] = 0.0;
	main_thread.send(MsgTraceCreate(itemname, title.to!string, axis.to!string, length));
	return handle;
}
extern(C) void trace_set_value(int handle, int position, double value) 
{
	if (handle < elder_traces.length) {
		if (position >= 0 && position < elder_trace_buffers[handle].length) {
			elder_trace_buffers[handle][position] = value;
			if (position == elder_trace_buffers[handle].length-1) {
				main_thread.send(MsgTraceUpdate(elder_traces[handle],elder_trace_buffers[handle].idup));
			}
		}
	}
}

Hist1[] elder_histograms_1D;
bool[] elder_histograms_1D_is_smart;
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
	import std.string;
	bool is_smart = itemname.endsWith("_smart");
	if (elder_histograms_1D.length <= handle) {
		//import std.stdio;
		//writeln(itemname, " is smart");
		elder_histograms_1D.length = handle+1;
	}
	if (elder_histograms_1D_is_smart.length <= handle) {
		elder_histograms_1D_is_smart.length = handle+1;
	}

	elder_histograms_1D[handle] = new Hist1(n_bins, left, right, axis.to!string, true);
	elder_histograms_1D_is_smart[handle] = is_smart;
	main_thread.send(MsgHist1dCreate(itemname, cast(shared Hist1)(elder_histograms_1D[handle])));
	return handle;
}

extern(C) void hist1d_fill(int handle, double value) {
	if (handle < elder_histograms_1D.length) {
		elder_histograms_1D[handle].fill(value, 1.0, elder_histograms_1D_is_smart[handle]);
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
bool[] elder_histograms_2D_is_smart;
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
	import std.string;
	bool is_smart = itemname.endsWith("_smart");

	if (elder_histograms_2D.length <= handle) {
		elder_histograms_2D.length = handle+1;
	}
	if (elder_histograms_2D_is_smart.length <= handle) {
		elder_histograms_2D_is_smart.length = handle+1;
	}
	elder_histograms_2D[handle] = new Hist2(n_bins1, n_bins2, 
											left1, right1, axis1.to!string,
											left2, right2, axis2.to!string);
	elder_histograms_2D_is_smart[handle] = is_smart;
	main_thread.send(MsgHist2dCreate(itemname, cast(shared Hist2)(elder_histograms_2D[handle])));
	return handle;
}

extern(C) void hist2d_fill(int handle, double value1, double value2) {
	if (handle < elder_histograms_2D.length) {
		elder_histograms_2D[handle].fill(value1, value2, 1, elder_histograms_2D_is_smart[handle]);
	}	
}
extern(C) void hist2d_set_bin(int handle, int bin1, int bin2, double value) {
	if (handle < elder_histograms_2D.length) {
		elder_histograms_2D[handle].set_bin(bin1, bin2, value);
	}
}

import gate;
Gate1D[] elder_ranges_1D;
struct MsgGate1DCreate {
	string name;
	shared Gate1D gate;
}
extern(C) int cond1d_create(const char *name,
							double left,
							double right,
							int handle) {
	import std.conv;
	int rhandle = cast(int)elder_ranges_1D.length;
	elder_ranges_1D ~= new Gate1D(left,right,0);
	string itemname = fix_name(name.to!string);
	main_thread.send(MsgGate1DCreate(itemname, cast(shared Gate1D)elder_ranges_1D[rhandle]));
	return rhandle;
}
extern(C) void cond1d_get(int handle,
							double *left,
							double *right) {
	//import std.datetime;
	*left  = elder_ranges_1D[handle].data.min;
	*right = elder_ranges_1D[handle].data.max;
}

Gate2D[] elder_ranges_2D;
double[][] elder_range_points_2D;
struct MsgGate2DCreate {
	string name;
	shared Gate2D gate;
}

PolyGate[] elder_polygons;
double[][] elder_polygate_points;
struct MsgPolyGateCreate {
	string name;
	shared PolyGate gate;
}
extern(C) int cond2d_create(const char *name,
							int num_points,
							double *points,
							int handle) {

	if (num_points == 4) {
		import std.conv;
		int rhandle = cast(int)elder_ranges_2D.length;
		elder_ranges_2D ~= new Gate2D(points[0],points[1],points[2],points[3]);
		elder_range_points_2D ~= [points[0],points[1],points[2],points[3]];
		string itemname = fix_name(name.to!string);
		main_thread.send(MsgGate2DCreate(itemname, cast(shared Gate2D)elder_ranges_2D[rhandle]));

		elder_polygons        ~= null;
		elder_polygate_points ~= null;
		return rhandle;
	}

	if (num_points > 4) {
		import std.conv;
		int rhandle = cast(int)elder_polygons.length;
		double[2][] new_polygate_points;
		double[] new_elder_polygate_points;
		for (long i = 0; i < num_points/2; ++i) {
			new_polygate_points ~= [points[2*i],points[2*i+1]];
			new_elder_polygate_points ~= points[2*i];
			new_elder_polygate_points ~= points[2*i+1];
		}
		elder_polygate_points ~= new_elder_polygate_points;
		elder_polygons ~= new PolyGate(new_polygate_points);
		string itemname = fix_name(name.to!string);
		main_thread.send(MsgPolyGateCreate(itemname, cast(shared PolyGate)elder_polygons[rhandle]));

		elder_ranges_2D       ~= null;
		elder_range_points_2D ~= null;
		return rhandle;
	}
	return 0;
}

extern(C) void cond2d_get(int handle,
							int *num_points,
							double **points) {
	if (elder_ranges_2D[handle] !is null) {
		*num_points = 4;
		elder_range_points_2D[handle][0] = elder_ranges_2D[handle].data.xmin;
		elder_range_points_2D[handle][1] = elder_ranges_2D[handle].data.xmax;
		elder_range_points_2D[handle][2] = elder_ranges_2D[handle].data.ymin;
		elder_range_points_2D[handle][3] = elder_ranges_2D[handle].data.ymax;
		*points = elder_range_points_2D[handle].ptr;
	} 

	if (elder_polygons[handle] !is null) {
		elder_polygate_points[handle].length = 0;
		foreach(point; elder_polygons[handle].data.points) {
			elder_polygate_points[handle] ~= point[0];
			elder_polygate_points[handle] ~= point[1];
		}
		*num_points = cast(int)elder_polygate_points[handle].length;
		*points = elder_polygate_points[handle].ptr;
	}
	return;
}

struct ElderPT_VisConInterface
{
	extern(C) int function ( const char *name,
								   const char *title,
								   const char *axis,
								   int length) _trace_create = &trace_create;
	extern(C) void function ( int handle, int bin, double value) _trace_set_value = &trace_set_value;

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


struct MsgPause {}
struct MsgContinue {}
struct MsgStop {}
struct MsgAck {}
struct MsgErr {}
struct MsgGetRate{}
struct MsgRate{double rate;}
struct MsgGetCurrentSource{}
struct MsgCurrentSource{string name;}
//struct MsgStopAck {} // sent in response to MsgStop
//struct MsgEventsPerSecond {long events;}
void run_elderpt(Tid main_thread_tid, const string config_filename, const string[] mbs_sourcesc) {
	auto mbs_sources = mbs_sourcesc.dup;
	import mbsapi_import;
	enum GETEVT_FILE       = 1;
	enum GETEVT_STREAM     = 2;
	enum GETEVT_TRANS      = 3;
	enum GETEVT_EVENT      = 4;
	enum GETEVT_REVSERV    = 5;
	enum GETEVT_RFIO       = 6;
	enum GETEVT_TAGINDEX   = 10;
	enum GETEVT_TAGNUMBER  = 11;
	enum GETEVT_SUCCESS    = 0;
	enum GETEVT_FAILURE    = 1;
	enum GETEVT_FRAGMENT   = 2;
	enum GETEVT_NOMORE     = 3;
	enum GETEVT_NOFILE     = 4;
	enum GETEVT_NOSERVER   = 5;
	enum GETEVT_RDERR      = 6;
	enum GETEVT_CLOSE_ERR  = 7;
	enum GETEVT_NOCHANNEL  = 8;
	enum GETEVT_TIMEOUT    = 9;
	enum GETEVT_NOTAGFILE  = 10;
	enum GETEVT_NOTAG      = 11;
	enum GETEVT_TAGRDERR   = 12;
	enum GETEVT_TAGWRERR   = 13;
	enum GETEVT_NOLMDFILE  = 14;
	enum PUTEVT_SUCCESS    = 0;
	enum PUTEVT_FILE_EXIST = 101;
	enum PUTEVT_FAILURE    = 102;
	enum PUTEVT_TOOBIG     = 103;
	enum PUTEVT_TOO_SMALLS = 104;
	enum PUTEVT_CLOSE_ERR  = 105;
	enum PUTEVT_WRERR      = 106;
	enum PUTEVT_NOCHANNEL  = 107;
	import std.stdio, std.conv;
	bool zipped = false;
	auto mbs_channel = f_evt_control();
	scope(exit) { 
		import core.stdc.stdlib;
		free(mbs_channel); 
	}
	int source_idx = 0;
	string mbs_source;
	string active_source;

	string open_mbs_source(ref s_evt_channel* mbs, string mbs_source) {
		if (mbs_source !is null && mbs_source.length > 0) {
			import std.stdio;
			writeln("mbs_source: ", mbs_source);
			import std.algorithm, std.array;
			int source_type = GETEVT_STREAM; // stream server is the default
			if (mbs_source.canFind(':')) {
				auto parts = mbs_source.split(':');
				if (parts[0] == "file")    source_type = GETEVT_FILE;
				else if (parts[0] == "stream")  source_type = GETEVT_STREAM;
				else if (parts[0] == "trans")   source_type = GETEVT_TRANS;
				else if (parts[0] == "event")   source_type = GETEVT_EVENT;
				else if (parts[0] == "revserv") source_type = GETEVT_REVSERV;
				else throw new Exception("unknown source type: " ~ parts[0] ~ ".  Possible source types are: file stream trans event revserv");
				mbs_source = parts[1];
				active_source = mbs_source;
			} else if (mbs_source.endsWith(".lmd")) {
				source_type = GETEVT_FILE;
				active_source = mbs_source;
			} else if (mbs_source.endsWith(".lmd.gz")) {
				writeln("zipped lmd file");
				active_source = mbs_source;
				import std.process;
				auto command = "gunzip -k -c " ~mbs_source~ " > /tmp/current.lmd";
				writeln("unzip command: ", command);
				auto unzip = pipeShell(command);
				wait(unzip.pid);
				mbs_source = "/tmp/current.lmd";
				//auto tmp = File(mbs_source);
				//foreach(chunk; unzip.stdout.byChunk(256)) 
				//	tmp.rawWrite(chunk);
				writeln("source name ", mbs_source);
				source_type = GETEVT_FILE;
				zipped = true;
			}
			import std.string;
			char *file_header;
			if (f_evt_get_open(source_type,
				           cast(char*)mbs_source.dup.toStringz, 
				           mbs,
				           &file_header,
				           1,0) != GETEVT_SUCCESS) {
				writeln("failed to open file \'", mbs_source,"\'");
				active_source = null;
				return null;
			}
			writeln("opening file ", mbs_source);
			return mbs_source;
		}
		return null;
	}
	if (mbs_sources !is null && mbs_sources.length > 0) {
		mbs_source = open_mbs_source(mbs_channel, mbs_sources[0]);
	}

	elder_histograms_2D_count = 0;
	elder_histograms_1D_count = 0;

	import std.datetime;
	main_thread = main_thread_tid;

	void *iface = elder_pt_interface_create(elder_interface);
	string name = "analysis.config";
	if (config_filename !is null) {
		name = config_filename;
		import std.stdio;
		writeln("config_filename ", config_filename);
	}
	name ~= '\0';
	void *ctrl = elder_pt_controller_create(name.ptr, iface);
	if (elder_pt_controller_errors(ctrl) > 0) {
		main_thread.send(MsgErr());
		f_evt_get_close(mbs_channel);
		return;
	}

	scope(exit) { // clean up
		elder_pt_controller_destroy(ctrl);
		ctrl = null;
		elder_pt_interface_destroy(iface);
		iface = null;
	}

	import std.datetime;

	auto evt = elder_pt_event_create();

	main_thread.send(MsgAck()); // main thread is waiting for this to see if everything started up properly
	// from here on the main_thread is set to state "running". 
	// This function should only return after main_thread sends MsgStop. If analysis is done (e.g. because file is completed)
	// the analysis should stay active, doing nothing and check for messages every few milliseconds.

	bool paused = false;
	bool stop = false;
	     done = false;
	double rate = 0;
	ulong seconds = 0;
	ulong events = 0;
	import std.datetime, std.datetime.stopwatch;
	StopWatch measure_time = StopWatch(AutoStart.yes);

	for (ulong i; ;++i) {
		//writeln("event ", i);
		ulong new_seconds = measure_time.peek.total!"seconds";
		if (new_seconds > seconds) {
			rate = (i - events)/(new_seconds-seconds);
			events = i;
			seconds = new_seconds;
		}
		elder_pt_controller_clear(ctrl);
		if (paused||done) {
			elder_pt_controller_idle(ctrl, iface);
			--i; // don't count idle events into the "rate" number
		} else {
			auto t = Clock.currTime;
			uint time_secs = cast(uint)t.toUnixTime;
			auto timeval = t.toTimeVal;
			uint timestamp = 0;
			uint frac_msecs = cast(uint)(timeval.tv_usec/1e3);
			elder_pt_event_clear(evt, cast(uint)i, 1, 1, time_secs, frac_msecs, timestamp);

			if (mbs_source !is null) { // fill with event with data from file
				int *i_event_header;
				int *i_buffer_header;
				int result = f_evt_get_event(mbs_channel, &i_event_header, &i_buffer_header);
				if (result != GETEVT_SUCCESS) {
					writeln("end of file");
					mbs_sources = mbs_sources[1..$];
					if (mbs_sources !is null && mbs_sources.length > 0) {
						mbs_source = open_mbs_source(mbs_channel, mbs_sources[0]);
					}
					if (mbs_source is null || mbs_sources is null || mbs_sources.length == 0) {
						writeln("all files processed");
						f_evt_get_close(mbs_channel);
						done = true;						
					}
					continue;
				}
				auto event_header = cast(sMbsEventHeader*) i_event_header;
				auto buffer_header = cast(sMbsBufferHeader*) i_buffer_header;

				int event_data_length   = (event_header.iWords);
				int event_type          = (event_header.iType&0x0000FFFF);
				int event_subtype       = (event_header.iType>>16);
				int event_trigger       = (event_header.iTrigger>>16);
				int event_count         = (event_header.iEventNumber);
				int event_size          = (event_header.iWords-2)/2;
				int buffer_sec          = buffer_header.iTimeSpecSec;
				int buffer_msecs        = buffer_header.iTimeSpecNanoSec; // the name is misleading. These are apparently miliseconds
				elder_pt_event_clear(evt, event_count, event_type, /+event_subtype,+/ event_trigger, buffer_sec, buffer_msecs, timestamp);
				const(uint*)  event_ptr = cast(const(uint*))event_header;
				//write(i, ": trig=",event_trigger, "event size = ", event_size, " subevents: ", );
				if (event_size >= 4) {
					int MBStrigger = (event_header.iTrigger>>16);
					int index = 4; // index of the first subevent header. 
					//writeln("trigger = ", MBStrigger, " event_size = ", event_size, " index+3 = ", index);
					while ((index) < event_size) // the MBS subevent header has 3 32-bit-words 
					{
						sMbsSubeventHeader *subevent_header = cast(sMbsSubeventHeader*)(&event_ptr[index]);

						int subevent_length = ( subevent_header.iWords - 2 ) / 2 + 3;
						int data_length     = subevent_length - 3;
						//writeln("data_length = ", data_length);
						const uint *subev_data_ptr = &event_ptr[index+3];
						int length   = subevent_header.iWords;
						int type     = ((subevent_header.iType)&0xFF); 
						int subtype  = ((subevent_header.iType>>16)&0xFFFF);
						int procid   = (subevent_header.iSubeventID&0xFFFF);
						int subcrate = ((subevent_header.iSubeventID>>16)&0xFF); 
						int control  = ((subevent_header.iSubeventID>>24)&0xFF);  
						elder_pt_event_add_subevent(evt,procid,type,subtype,control,subcrate,data_length,subev_data_ptr);
				        index += subevent_length;       
					}
				}
			} else {
				//writeln("mbs source is null");
			}
			elder_pt_controller_unpack(ctrl, iface, evt);
			elder_pt_controller_process(ctrl, iface);
		}
		receiveTimeout((paused||done)?(100.msecs):(Duration.zero),
			(MsgPause            msg) { paused = true;  main_thread.send(MsgAck()); },
			(MsgContinue         msg) { paused = false; main_thread.send(MsgAck()); },
			(MsgStop             msg) { paused = false; stop = true;  done = false; main_thread.send(MsgAck()); },
			(MsgGetRate          msg) { main_thread.send(MsgRate(rate)); },
			(MsgGetCurrentSource msg) { main_thread.send(MsgCurrentSource(active_source.idup)); }
		);
		if (stop) break;
	}
	f_evt_get_close(mbs_channel);
	elder_pt_event_destroy(evt);
}
