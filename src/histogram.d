module histogram;
@safe:

import item;
import std.json;
import serializeJSON;



class Hist1Factory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Hist1(json);
	}
}

import graphics;

class Hist1 : Visual, FitDataSource, Item
{
public:
	struct Data{
		@SERIALIZE double[] bins;
		@SERIALIZE double left;
		@SERIALIZE double right;
		@SERIALIZE double overflow;
		@SERIALIZE double underflow;
	}
	this(ulong length, double left, double right) { 
		data.bins = new double[length];
		data.left = left;
		data.right = right;
		data.underflow = 0.0;
		data.overflow = 0.0;
		if (data.left is double.init) {
			data.left = 0.0;
		} 
		if (data.right is double.init) {
			data.right = data.bins.length;
		}
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
		} catch(Exception e) {
			writeln("XXX ", e.msg);
		} 
	}
	override JSONValue toJSON() { return serialize(data); }
	override string get_type()  {
		return "histogram.Hist1";
	}
	override void reset() {
		data.bins[] = double.init;
		++item_version;
	}

	void fill(double position, double value = 1.0, bool expand = false) {
		++item_version;
		ulong idx = cast(ulong)(1.0*data.bins.length*(position - data.left)/(data.right-data.left));
		//import std.stdio; writeln("fill pos ", idx);
		if (expand) {
			//import std.stdio;
			//writeln("histogram is filled in expand mode");
			if (idx < 0) {
				//writeln("underflow => need to expand left = ", data.left, " right = ", data.right);
				data.left = data.left - (data.right-data.left); // double the size
				//writeln("             expanded       left = ", data.left, " right = ", data.right);
				for(uint i = 0; i < data.bins.length/2; ++i) {
					long nfrom1 = cast(long)data.bins.length-2*(i+1);
					long nfrom2 = cast(long)data.bins.length-2*(i+1)+1;
					long nto    = cast(long)data.bins.length-(i+1);
					double sum = data.bins[cast(uint)nfrom1];
					if (nfrom2 >= 0) sum += data.bins[cast(uint)nfrom2];
					data.bins[nto] = sum;
				}
				for(uint i = 0; i < data.bins.length/2; ++i) {
					data.bins[i] = double.init;
				}
				fill(position,value,expand);
			} else if (idx >= data.bins.length) {
				//writeln("overflow => need to expand left = ", data.left, " right = ", data.right);
				data.right = data.right + (data.right-data.left); // double the size
				//writeln("                  expanded left = ", data.left, " right = ", data.right);
				for(uint i = 0; i < data.bins.length/2; ++i) {
					uint nfrom1 = 2*i;
					uint nfrom2 = 2*i+1;
					uint nto    = i;
					double sum = data.bins[nfrom1];
					if (nfrom2 < data.bins.length) sum += data.bins[nfrom2];
					data.bins[nto] = sum;
				}
				for(uint i = 0; i < data.bins.length/2; ++i) {
					data.bins[data.bins.length-(i+1)] = double.init;
				}
				fill(position,value,expand);
			} else {
				if (data.bins[cast(uint)idx] is double.init) {
					data.bins[cast(uint)idx] = value;
				} else {
					data.bins[cast(uint)idx] += value;
				} 
			}

		} else {
			     if (idx < 0)                 data.underflow += value;
			else if (idx >= data.bins.length) data.overflow  += value;
			else {
				if (data.bins[cast(uint)idx] is double.init) {
					data.bins[cast(uint)idx] = value;
				} else {
					data.bins[cast(uint)idx] += value;
				} 
			}

		}

	}

	void set_bin(int bin, double value) {
		if (bin >= 0 && bin < data.bins.length) {
			++item_version;
			data.bins[bin] = value;
		} 
	}

	override ulong getVersion() {
		return item_version;
	}
	override void overrideVersion(ulong new_version) {
		item_version = new_version;
	}

	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) 
	{
		return new Hist1Visualizer(old, item_version, data.bins, data.left, data.right);
	}

	override double[3][] get_data(double[2] region) {
		double left=region[0];
		double right=region[1];
		double bin_width = (data.right-data.left)/data.bins.length;
		double[3][] result;
		foreach(idx, y; data.bins) {
			double x = data.left+idx*(data.right-data.left)/data.bins.length;
			x += bin_width/2;
			if (x >= left && x < right) {
				import std.math;
				double[3] dp = [x,y,y>1?sqrt(y):1];
				result ~= dp;
			}
		}
		return result;
	}

private:
	Data data;
	ulong item_version = 0;
}




class Hist2Factory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Hist2(json);
	}
}

class Hist2 : Visual, Item
{
public:
	struct Data{
		@SERIALIZE double initial;
		@SERIALIZE double[] bins;
		@SERIALIZE ulong  bins_x;
		@SERIALIZE ulong  bins_y;
		@SERIALIZE double left;
		@SERIALIZE double right;
		@SERIALIZE double bottom;
		@SERIALIZE double top;
		@SERIALIZE double overflow;
		@SERIALIZE double underflow;
		@SERIALIZE double[9] quadrants;  // number of counts in the nine quadrants
		                                 // 0 1 2
		                                 // 3 4 5
		                                 // 6 7 8 
		                                 // counts[4] are inside the histogram
		                                 // counts[1] are above the histogram
		                                 // counts[5] are right outside
	}
	this(ulong nbins_x, ulong nbins_y, double left, double right, double bottom, double top, double initial = double.init) {
		data.initial     = initial;
		data.bins        = new double[cast(uint)nbins_x*cast(uint)nbins_y];
		data.bins[]      = initial;
		data.bins_x      = nbins_x;
		data.bins_y      = nbins_y;
		data.left        = left;
		data.right       = right;
		data.bottom      = bottom;
		data.top         = top;	
		data.quadrants[] = initial;
		if (left is double.init && right is double.init && bottom is double.init && top is double.init) {
			data.left   = 0; data.right = nbins_x;
			data.bottom = 0; data.top   = nbins_y;
			return;
		}
		if (left is double.init || right is double.init || bottom is double.init || top is double.init) {
			throw new Exception("left,right,bottom,top must be specified all together or not at all");
		}
	}
	this(ref JSONValue json) {
		import std.stdio;
		try{
			data = deserialize!Data(json);
		} catch(Exception e) {
			writeln("exception in JSON-constructor of histogram.Hist2 ", e.msg);
		} 
	}
	override JSONValue toJSON()  { return serialize(data); }
	override string get_type()  {
		return "histogram.Hist2";
	}
	override void reset() {
		data.bins[] = data.initial;
		++item_version;
	}

	void fill(double position_x, double position_y, double value = 1.0) {
		ulong idx_x = cast(ulong)(1.0*data.bins_x*(position_x - data.left)  /(data.right - data.left  ));
		ulong idx_y = cast(ulong)(1.0*data.bins_y*(position_y - data.bottom)/(data.top   - data.bottom));
		//import std.stdio; writeln("fill at idx_x ", idx_x, ":", _lower, " ", _data[idx], " ", _higher);
		ulong quadrant = 0;
		if (idx_x >= 0) quadrant += (idx_x < data.bins_x)?1:2;
		if (idx_y >= 0) quadrant += (idx_y < data.bins_y)?3:6;

		if (data.quadrants[quadrant] is double.init) data.quadrants[quadrant] = value;
		else                                         data.quadrants[quadrant] += value;

		if (quadrant == 4) {
			ulong idx = (idx_y*data.bins_x+idx_x);
			if (data.bins[idx] is double.init) data.bins[idx] = value;
			else                               data.bins[idx] += value;
		}
		++item_version;
	}
	void set_bin(int binx, int biny, double value) {
		if (binx >= 0 && binx < data.bins_x) {
			if (biny >= 0 && biny < data.bins_y) {
				++item_version;
				ulong idx = biny*data.bins_x+binx;
				data.bins[idx] = value;
			}
		}
	}

	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) 
	{
		return new Hist2Visualizer(old, item_version, backend, data.bins, 
								   data.bins_x, data.bins_y, 
								   data.left, data.right, data.bottom, data.top);
	}
	override ulong getVersion() {
		return item_version;
	}
	override void overrideVersion(ulong new_version) {
		item_version = new_version;
	}
private:
	ulong item_version = 0;
	Data data;
}






class FileHistogramFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new FileHistogram(json);
	}
}

import graphics, functions;
class FileHistogram : Visual, FitDataSource, Item {
	struct Data {
		@SERIALIZE string filename;
	}
	Data data;
	this(Data d)             { data = d; }
	this(ref JSONValue json) { data = deserialize!Data(json); }
	// Item Interface
	override JSONValue toJSON()  { return serialize(data); }
	override string get_type()  { 
		return "histogram.FileHistogram"; 
	}
	override void reset() {
		++item_version;
	}
	override ulong getVersion() {
		need_to_reload();
		return item_version;
	}
	override void overrideVersion(ulong new_version) {
		item_version = new_version;
	}

	// Visual Interface
	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) {
		HistData hist_data = read_file(data.filename);
		switch(hist_data.dim) {
			case 1: return new Hist1Visualizer(old, item_version, hist_data.data, hist_data.left, hist_data.right);
			break;
			case 2: 
				return new Hist2Visualizer(old, item_version, backend, hist_data.data, 
										   hist_data.bins_x, hist_data.bins_y, 
										   hist_data.left, hist_data.right, hist_data.bottom, hist_data.top);
			break;
			default: return null; //assert(false);
		}
	}

	override double[3][] get_data(double[2] region) {
		double left=region[0];
		double right=region[1];
		HistData hist_data = read_file(data.filename);
		double bin_width = (hist_data.right-hist_data.left)/hist_data.data.length;
		double[3][] result;
		if (hist_data.dim == 1) {
			foreach(idx, y; hist_data.data) {
				double x = hist_data.left+idx*(hist_data.right-hist_data.left)/hist_data.data.length;
				x += bin_width/2;
				if (x >= left && x < right) {
					import std.math;
					double[3] dp = [x,y,y>1?sqrt(y):1];
					result ~= dp;
				}
			}
		} else {
			throw new Exception("fit for 2D-histograms not implemented yet");
		}
		return result;
	}

private:
	import std.datetime : abs, DateTime, hnsecs, SysTime;
	import std.datetime : Clock, seconds;		
	import std.file;

	ulong item_version = 0;
	SysTime _time_of_last_update;

	bool need_to_reload() {
		bool need_update = false;
		import std.stdio;
		// test different conditions that make reload necessary
		SysTime time_last_file_modification = timeLastModified(data.filename);
		SysTime time_of_last_update = _time_of_last_update;
		if (time_of_last_update == SysTime.init ) need_update = true;
		if (time_of_last_update < time_last_file_modification) need_update = true;
		_time_of_last_update = time_last_file_modification;

		if (need_update) ++item_version;
		return need_update;
	}	


}
















struct HistData {
	double[] data;
	ulong    dim;
	double left, right;
	double bottom, top;
	ulong bins_x, bins_y;
}
auto read_file(string filename) {
	//import std.random, std.math;
	//auto histo = new double[10000];
	//foreach(i, ref bin; histo) {
	//	double x = 6.0*(-0.5*histo.length+i)/histo.length;
	//	bin = 400.0*exp(-(x*x))-200;
	//	bin -= uniform(0,50);
	//}
	//return histo;

	import std.stdio, std.file, std.algorithm, std.array, std.conv;

	try {
		//if (filename.endsWith(".mtx")) {
		//	return read_mtx_file(filename);
		//}

		//auto file = open_file(filename);
		// reading content from file
		double hist_left, hist_right, hist_bottom, hist_top;
		double[] bin_data;
		ulong max_width = 0;
		bool has_fairy_header_1d = false;
		bool has_fairy_header_2d = false;
		foreach(line; readText!string(filename).split("\n"))	{
			if (line.startsWith("#")) {
				import std.format;
				// read something like this
				//# 2 500 0 0 3 500 1 0 3
				int dim, nbins;
				string name;
				double left, binwidth;
				int nbinsx, nbinsy;
				string xlabel, ylabel;
				double bottom, binheight;
				if (!(has_fairy_header_1d || has_fairy_header_2d)) {
					try { // try to read 2d fairy histogram
						line.dup.formattedRead("# %s %s %s %s %s %s %s %s %s", dim, nbinsx, xlabel, left,   binwidth, 
							                                                    nbinsy, ylabel, bottom, binheight);
						hist_left = left;
						hist_right = left+binwidth*nbinsx;
						hist_bottom = bottom;
						hist_top    = bottom+binheight*nbinsy;
						if (hist_left !is double.init && hist_right !is double.init &&
							hist_bottom !is double.init && hist_top !is double.init) {
							has_fairy_header_2d = true;
							//writeln("read 2d fairy header");
						}
						//writeln("left = ", hist_left, " right = ", hist_right, "\r");
					} catch (Exception e) {
					//writeln("Exception caught\r");
					}
				}
				if (!(has_fairy_header_1d || has_fairy_header_2d)) {
					try { // try to read 1d fairy histogram
						line.dup.formattedRead("# %s %s %s %s %s", dim, nbins, name, left, binwidth);
						hist_left = left;
						hist_right = left+binwidth*nbins;
						if (hist_left !is double.init && hist_right !is double.init) {
							has_fairy_header_1d = true;
							//writeln("read 1d fairy header");
						}
						//writeln("left = ", hist_left, " right = ", hist_right, "\r");
					} catch (Exception e) {
						//writeln("Exception caught\r");
					}
				}
			}

			if (!line.startsWith("#") && line.length > 0) {
				ulong width = 0;
				foreach(number; split(line.dup(), " ")) {
					if (number.length > 0) {
						try {
							if (number.length==1 && number[0]=='_') {
								bin_data ~= double.init;
							} else {
								double value = std.conv.to!double(number);
								bin_data ~= value;
							}
						} catch(Exception e) {
							bin_data ~= double.init;
						}
						++width;
					}
				}
				max_width = max(max_width, width);
			}

			//if (!line.startsWith("#") && line.length > 0) {
			//	foreach(number; split(line.dup(), " ")) {
			//		if (number.length > 0) {
			//			bin_data ~= std.conv.to!double(number);
			//		}
			//	}
			//}
		}
		//file.close();

		// some heuristics to find the correct way to interpret the data
		// is first column only increasing?
		//if (max_width == 2 && 
		//	(bin_data.length%2) == 0 ) { // sparse 1d histogram
		//	double min_gap;
		//	bool only_increasing = true;
		//	if (bin_data.length > 4)
		//	foreach(idx; 2..bin_data.length/2) {
		//		double gap = bin_data[idx]-bin_data[idx-2];
		//		if (gap <= 0) {
		//			only_increasing = false;
		//			break;
		//		}
		//		if (min_gap is min_gap.init || min_gap > gap) {
		//			min_gap = gap;
		//		}
		//	}
		//	if ()
		//}
		// did we read a 1d histogram?
		ulong dim = 0;
		if (max_width == 1 || max_width == bin_data.length) {
			dim = 1;
			if (!has_fairy_header_1d) {
				hist_left = 0;
				hist_right = bin_data.length;
			}
			return HistData(bin_data, dim, hist_left, hist_right);
		} else if (bin_data.length % max_width == 0) {
			dim = 2;
			ulong w = max_width;
			ulong h = bin_data.length / max_width;
			if (!has_fairy_header_2d) {
				hist_left = 0;
				hist_right = w;
				hist_bottom = 0;
				hist_top = h;
			}
			//foreach(ref bin; bin_data) {
			//	if (bin == 0) {
			//		bin = double.init;
			//	}
			//}
			return HistData(bin_data, dim, hist_left, hist_right, hist_bottom, hist_top, w, h);
		}
		return HistData();
		//// if the file didn't contain left/right information
		//if (hist_left is double.init || hist_right is double.init) {
		//	hist_left = 0;
		//	hist_right = bin_data.length;
		//}
		////writeln("read file left=",hist_left,"   right=",hist_right,"\r");
		//_dim = 1;
		//return HistData(bin_data, hist_left, hist_right);
	} catch (Exception e) {
		writeln("Can not read file ", filename, "\r");
		return HistData();
	}
}


















class Hist1Visualizer : Visualizer 
{
public:

	import std.stdio;
	this(Visualizer old, ulong itemversion,/+ulong colorIdx, +/double[] data, double left, double right)//, string xlabel = null, string ylabel = null)
	{
		//writeln("Hist1Visualizer constructor ", left, " ", right);
		ulong dim;
		//super(colorIdx, dim=1);
		super(itemversion, dim=1);
		_bin_data = data.idup;
		_left     = left;
		_right    = right;
		_mipmap_data = make_mipmap_data();
		//_xlabel = xlabel;
		//_ylabel = ylabel;
	}
	//override string getLabelX() {
	//	return _xlabel;
	//}
	//override string getLabelY() {
	//	return _ylabel;
	//}
	//import cairo.Context, cairo.Surface;
	import graphics, transform;
	@trusted override void draw(BackendInterface d, in Transform[3] t) const  
	{
		//writeln("Hist1Visualizer draw");

		//import primitives;
		if (_bin_data is null) {
			return;
		}
		try {
			//auto pixel_width = t[0].pixel_width;
			//auto bin_width = getBinWidth;
			//double line_width = t[0].world2canvas_delta(1);
			//d.set_color(0.0,0.0,0.0);
			//d.set_line_width(line_width);
			//foreach(bin, content; _bin_data) {
			//	double x =  t[0].world2canvas(t[0].log(bin));
			//	double y0 = t[1].world2canvas(t[1].log(0));
			//	double y1 = t[1].world2canvas(t[1].log(content));
			//	d.rectangle(x,y0,x+line_width,y1);
			//	d.fill();
			//}
			double line_width = 2.0;
			d.set_color(1.0,0.5,0.5);
			drawMixedHistogram(d,t, _left,_right, _bin_data, _mipmap_data, line_width, true);
			d.set_color(1.0,0.0,0.0);
			drawMixedHistogram(d,t, _left,_right, _bin_data, _mipmap_data, line_width, false);
		} catch(Exception e) {
			import std.stdio;
			writeln ("there was an Exception: ", e.file, ":", e.line, " -> ", e.msg, "\r");
		}
	}

	double getBinWidth() const pure
	{
		return (_right - _left) / _bin_data.length;
	}

	override double getValue(double x, double y) {
		auto x_idx = ((x-_left)*_bin_data.length/(_right-_left));
		if (x_idx > 0 && x_idx < _bin_data.length) {
			return _bin_data[cast(uint)x_idx];
		}
		return double.init;
	}

	override bool get_leftright(out double[2] lr, in Transform[3] t) 
	{
		import std.stdio;
		if (t[0].logscale && _left <= 0 && _right <= 0) return false;
		if (_left == _right)                      return false;
		lr[0] = t[0].log(_left, getBinWidth()/2.0);
		lr[1] = t[0].log(_right);
		return true;
	}

	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) 
	{
		import std.stdio;
		if (_bin_data is null) {
			return false;
		}
		if (_bin_data.length == 0) {
			return false;
		}
		if (_left is _left.init || _right is _right.init) {
			return false;
		}


		import std.math, std.algorithm;
		double left = lr[0];
		double right = lr[1];
		if (t[0].logscale) { // special treatment for logx case
			right = exp(right);
			left = exp(left);
		}

		// transform into bin numbers
		left  = (left-_left)/getBinWidth();
		right = (right-_left)/getBinWidth();

		// prevent overflow when converting to in further down in the code
		if (left >= int.max/2) left = int.max/2;
		if (right >= int.max/2) right = int.max/2;


		if (left >= _bin_data.length || right <= 0) {
			return false;
		}

		int leftbin  = max(cast(int)left,0);
		int rightbin = min(cast(int)(right+1),_bin_data.length);
		if (leftbin > rightbin) {
			import std.stdio;
			writeln("unexpected leftbin,rightbin: ", leftbin, "," , rightbin, "\r");
			return false;
		}
		import std.algorithm;
		auto good_bins = _bin_data[leftbin..rightbin].filter!(bin=>bin !is double.init);
		if (good_bins.empty) return false;
		
		double maximum = good_bins.maxElement();
		double minimum = good_bins.minElement();

		if (t[1].logscale) {
			import std.stdio;
			auto bins_larger_0 = good_bins.filter!(x=>x>0.0);
			double minimum_larger_0;
			if (bins_larger_0.empty) return false;
			minimum_larger_0 = _bin_data.filter!(x=>x>0.0).minElement();
			bt[0] = t[1].log(minimum, minimum_larger_0/2.0);
			bt[1] = t[1].log(maximum, minimum_larger_0/2.0);
			return true;
		}
		bt[0] = minimum;
		bt[1] = maximum;
		return true;
	}


private:

	/////////////////////////////////////////////////////////
	// calculate mipmap data from _bin_data
	// has to be pure to be allowed to return immutable
	immutable(MinMax[][]) make_mipmap_data() pure 
	{
		if (_bin_data is null) {
			return null;
		}
		import std.algorithm, std.stdio;
		auto mipmap_data = new MinMax[][0];
		for (int idx = 0;; ++idx) {
			if (idx == 0) {
				// special case for histograms with only 1 bin
				if (_bin_data.length == 1) {
					mipmap_data ~= new MinMax[1];
					mipmap_data[$-1][0].min = mipmap_data[$-1][0].max = _bin_data[0];
				} else {
					mipmap_data ~= new MinMax[_bin_data.length-1];
					foreach(n, ref mip; mipmap_data[$-1]) {
						mip.min = min(_bin_data[n],_bin_data[n+1]);
						mip.max = max(_bin_data[n],_bin_data[n+1]);
					}
				}
			} else {
				auto parent_len = mipmap_data[idx-1].length;
				if (parent_len == 1) {
					break;
				}
				mipmap_data ~= new MinMax[(mipmap_data[idx-1].length+1) / 2];
				foreach(n, ref mip; mipmap_data[$-1]) {
					auto n2 = n*2, n2_plus_1 = n2+1;
					if (n2_plus_1 >= mipmap_data[idx-1].length) {
						n2_plus_1 = n2;
					}
					double minA = mipmap_data[idx-1][n2].min;
					double minB = mipmap_data[idx-1][n2_plus_1].min;
					if (minA is double.init || minB < minA) mip.min = minB;
					else mip.min = minA;

					double maxA = mipmap_data[idx-1][n2].max;
					double maxB = mipmap_data[idx-1][n2_plus_1].max;
					if (maxA is double.init || maxB > maxA) mip.max = maxB;
					else mip.max = maxA;
				}
			}
		}
		return mipmap_data;
	}

private: // state	
	immutable(double[]) _bin_data;
	immutable(double) _left, _right;

	// mipmap data // TODO implement
	struct MinMax {double min; double max;} ;
	immutable(MinMax[][]) _mipmap_data;

	string _xlabel;
	string _ylabel;
}

import transform;
void drawMixedHistogram(T, MinMax)(BackendInterface d, Transform[3] t, double min, double max, immutable(T[]) bins, immutable(MinMax[][]) mipmap, double line_width, bool filled = true) {
	if (bins is null) {
		import std.stdio;
		writeln("********************   drawHistogram bins is null\r");
		return ;
	}
	if (bins.length == 0) {
		import std.stdio;
		writeln("********************   drawHistogram bins.length == 0\r");
		return ;
	}
	if (min >= max) {
		import std.stdio;
		writeln("********************   drawHistogram min >= max\r");
		return ;
	}
	d.set_line_width(line_width);

//d.set_line_width(2);
//d.set_color(1,0,0);

	double bin_width = (max-min)/bins.length;

	// find the starting index of the visible part of the histogram
	double xhist = min;
	import std.math;
	double x_start = t[0].exp(t[0].min);//logscale?exp(t[0].min):(t[0].min);
	uint idx_start = 0;
	double index = ((x_start-min)/bin_width);
	if (index < 0) index = 0;
	idx_start = cast(uint)index;
	if (idx_start >= bins.length) return;
	xhist = min+bin_width*idx_start;
	double x1,x2, y1,y2;
	x1 = t[0].world2canvas(t[0].log(xhist));
	y1 = t[1].world2canvas(t[1].log(bins[idx_start]));
	double y0 = t[1].world2canvas(t[1].log(0));
	// draw horizontal part
	xhist += bin_width;
	x2 = t[0].world2canvas(t[0].log(xhist));
	if (y1 !is double.init) {
		if (filled) { d.rectangle(x1,y0,x2+1,y1); d.fill();}
		else 		{ d.horizontal_line(y1, x1, x2); d.stroke();}
	}
	import std.stdio;
	//int color =1;
	//d.set_color(color,0,0);
	long mipmap_idx = idx_start;
	long mipmap_level = 0;
	outer: foreach(bin_idx, bin; bins[idx_start+1..$])
	{
		//import std.stdio; writeln("outer");
		// draw vertical part
		y2 = t[1].world2canvas(t[1].log(bin));
		import std.algorithm;
		double y1d=y1, y2d=y2;
		if (y2d<y1d) swap(y1d,y2d);
		if (y1 !is double.init && y2 !is double.init && !filled) d.vertical_line(x2, y1d-0.5*d.get_line_width, y2d+0.5*d.get_line_width);
		y1 = y2;

		// draw horizontal part of next bin
		x1 = x2;
		xhist += bin_width;
		mipmap_idx += 1;
		x2 = t[0].world2canvas(t[0].log(xhist));
		if (y2 !is double.init) {
			if (filled) { d.rectangle(x1,y0,x2+1,y2); d.fill(); }
			else        { d.horizontal_line(y2, x1, x2); d.stroke(); }
		}
		if (x2-x1 < d.get_line_width) { // need to switch to mipmap 
			mipmap_level  = 0;

			for (;;) {
				inner: for (;;) {
					if (mipmap_level >= mipmap.length)             break outer;
					if (mipmap_idx >= mipmap[cast(uint)mipmap_level].length) break outer;		
					x1 = t[0].world2canvas(t[0].log(xhist));
					x2 = t[0].world2canvas(t[0].log(xhist+bin_width));
					if ((x2-x1 > d.get_line_width/2 ) || mipmap_level+1 == mipmap.length) {
						break inner;
					}
					mipmap_idx   /= 2;
					mipmap_level += 1;
					bin_width    *= 2;
					d.stroke();
				}
				double vmin = t[1].log(mipmap[cast(uint)mipmap_level][cast(uint)mipmap_idx].min);
				double vmax = t[1].log(mipmap[cast(uint)mipmap_level][cast(uint)mipmap_idx].max);
				y1 = t[1].world2canvas(vmin);
				y2 = t[1].world2canvas(vmax);

				import std.algorithm;
				if (y2<y1) swap(y1,y2);
				if (y1 !is double.init && y2 !is double.init) {
					if (filled) {
						     if (y0>y2) d.vertical_line(x1,y0,y1);
						else if (y0<y1) d.vertical_line(x1,y2,y0);
						else            d.vertical_line(x1,y2,y1);
					} else {
						d.vertical_line(x1, y1-0.5*d.get_line_width, y2+0.5*d.get_line_width);
					}
				}

				xhist += bin_width;
				mipmap_idx += 1;
				if (t[0].log(xhist) > t[0].max) break outer;

			}

			break outer;
		}

		if (t[0].log(xhist) > t[0].max) break;
	}


	d.stroke();

}



//////////////////////////////////////////////////
// Visualizer for 2D Histograms
//////////////////////////////////////////////////
class Hist2Visualizer : Visualizer 
{
public:

	//import cairo.Pattern, gdk.Cairo;
	@trusted this(Visualizer old, ulong itemversion, BackendInterface d,/*ulong colorIdx,*/ double[] data, 
		ulong width, ulong height, 
		double left, double right, double bottom, double top,
		string xlabel = null, string ylabel = null, string zlabel = null)
	{
		auto old_hist2 = cast(Hist2Visualizer)old;
		import std.stdio;
		ulong dim;
		super(itemversion, dim=2);
		// recycle the memory if it has the same length
		if (old_hist2 !is null && data.length == old_hist2._bin_data.length) {
			_bin_data = old_hist2._bin_data;
			_bin_data[] = data[];
		} else {
			_bin_data = data.dup;
		}
		_bins_x   = width;
		_bins_y   = height;
		_left     = left;
		_right    = right;
		_bottom   = bottom;
		_top      = top;
		_xlabel   = xlabel;
		_ylabel   = ylabel;
		_zlabel   = zlabel;
		backend = d;

		//getZminZmaxInLeftRightBottomTop(_zmin, _zmax, _left,_right, _bottom, _top, )
		import std.algorithm;
		auto valid_bins = _bin_data.filter!(x => x !is double.init);
		if (valid_bins.empty) {
			_zmin = 0;
			_zmax = 1;
		} else {
			_zmin = valid_bins.minElement;
			_zmax = valid_bins.maxElement;
		}
		//import std.stdio;
		//writeln(_bin_data);
		//writeln(_zmin, " <<< ", _zmax);
		if (old_hist2 !is null && data.length == old_hist2._bin_data.length) {
			bitmap_handle = old_hist2.bitmap_handle;
			old_hist2.bitmap_handle = 0;
			bitmap_handle_log = old_hist2.bitmap_handle_log;
			old_hist2.bitmap_handle_log = 0;
		} else {
			bitmap_handle          = d.create_bitmap(cast(int)_bins_x*2, cast(int)_bins_y*2);
			bitmap_handle_log      = d.create_bitmap(cast(int)_bins_x*2, cast(int)_bins_y*2);

		}
		uint[] bitmap_data     = d.access_bitmap_data(bitmap_handle);
		uint[] bitmap_data_log = d.access_bitmap_data(bitmap_handle_log);
		//assert(bitmap_data.length == _bin_data.length);
		generate_rgb_data(_bin_data, _bins_x, _bins_y, _zmin, _zmax, _bins_x*2, bitmap_data, bitmap_data_log);
		d.access_bitmap_done(bitmap_handle);
		d.access_bitmap_done(bitmap_handle_log);
	}
	~this() {
		if (bitmap_handle)     backend.destroy_bitmap(bitmap_handle);
		if (bitmap_handle_log) backend.destroy_bitmap(bitmap_handle_log);
	}

	double gen_color(in double height, in Transform[3] t) const {
		import std.algorithm;
		if (t[2].min == t[2].max) return 0.5;
		double h = height;//.clamp(t.getZmin(), t.getZmax());
		if (t[2].logscale) {
			import std.math;
			//import std.stdio; writeln(log(h), "/", t.getZmax());
			return std.math.log(h)/t[2].max;
		}
		return (h-t[2].min)/(t[2].max-t[2].min);
	}

	@safe static void get_rgb(double c, out uint rgb) {
		// grayscale
		//uint i = cast(uint)(255*c);
		//rgb = 0xff000000 | (i<<16) | (i<<8) | (i<<0);

		// bluish color
		rgb = 0xff000000;
		if (c>1.0) c = 1.0;
		if (c<0.0) c = 0.0;
		c *= 3;
		if (c < 1.0) { // back to blue
			rgb |= cast(uint)(0xff*c);
			return;
		}
		rgb = 0xff0000ff;
		if (c < 2.0)  { // blue to lightblue
			c -= 1.0; 
			rgb |=  (cast(uint)(0x0000ff00*c) & 0x0000ff00) ; 
			return;
		}
		rgb = 0xff00ffff; // lightblue to white
		c -= 2.0;
		rgb |= cast(uint)(0xff*c)<<16;
	}

	@trusted
	void generate_rgb_data(in double[] data, ulong width, ulong height, 
		                   double zmin, double zmax,
		                   ulong stride, uint[] rgb_data, uint[] log_rgb_data) const
	{
		import std.stdio;
		//writeln("gererating rgb data: ", zmin, " ", zmax);
		import std.math;
		import std.parallelism;
		import std.range;
		foreach(ulong y; iota(0,height).parallel) { // employ a bit of parallelism here. A ~ 1.7x speed improvement was measured on an i7 4770
			foreach(ulong x; 0..width) {
				ulong idx = y*width+x;
				auto bin = data[cast(uint)idx];
				auto rgb_data_idx = (y)*stride + x;
				if (bin !is double.init) {// && bin>0) {
					get_rgb((bin-zmin)/(zmax-zmin), rgb_data[cast(uint)rgb_data_idx]);				
					if (bin > 0) {
						get_rgb((log(bin)-zmin)/(zmax-zmin), log_rgb_data[cast(uint)rgb_data_idx]);
					} else {
						log_rgb_data[cast(uint)rgb_data_idx] = 0x00000000;
					}
				} else {
					rgb_data[cast(uint)rgb_data_idx]     = 0x00000000;
					log_rgb_data[cast(uint)rgb_data_idx] = 0x00000000;
				}
			}
			int  old_xoffset = 0;
			auto xoffset = cast(int)width;
			int  xdepth  = 2;
			while(cast(int)width/xdepth) {
				ulong deltaxoffset = cast(int)width/xdepth;
				foreach(ulong x; 0..deltaxoffset) {
					auto rgb_data_idx = (y)*stride + (xoffset+x);
					auto source1_idx  = (y)*stride + (old_xoffset+x*2);
					auto source2_idx  = (y)*stride + (old_xoffset+x*2+1);

					*cast(uint*)&log_rgb_data[cast(uint)rgb_data_idx] = ((0xfefefefeL & log_rgb_data[cast(uint)source1_idx])+
					                                                     (0xfefefefeL & log_rgb_data[cast(uint)source2_idx]))>>1;
					*cast(uint*)&rgb_data[cast(uint)rgb_data_idx]     = ((0xfefefefeL & rgb_data[cast(uint)source1_idx])+
					                                                     (0xfefefefeL & rgb_data[cast(uint)source2_idx]))>>1;

				}
				old_xoffset = xoffset;
				xoffset += deltaxoffset;
				xdepth *= 2;
			}
		} 
		int  old_yoffset = 0;
		auto yoffset = cast(int)height;
		int  ydepth  = 2; // 1 refers to the original pixel buffer, 2 is the first mipmap, 3 is the second mipmap, and so on ...
		while(cast(int)height/ydepth) {
			ulong deltayoffset = cast(int)height/ydepth;
			foreach(ulong y; iota(0,deltayoffset).parallel) { // employ a bit of parallelism here. A ~ 1.7x speed improvement was measured on an i7 4770
				foreach(ulong x; 0..width) {
					ulong idx = y*width+x;
					auto rgb_data_idx = (yoffset    +y    )*stride + (x);
					auto source1_idx  = (old_yoffset+y*2  )*stride + (x);
					auto source2_idx  = (old_yoffset+y*2+1)*stride + (x);

					*cast(uint*)&log_rgb_data[cast(uint)rgb_data_idx] = ((0xfefefefeL & log_rgb_data[cast(uint)source1_idx])+
					                                                     (0xfefefefeL & log_rgb_data[cast(uint)source2_idx]))>>1;
					*cast(uint*)&rgb_data[cast(uint)rgb_data_idx]     = ((0xfefefefeL & rgb_data[cast(uint)source1_idx])+
					                                                     (0xfefefefeL & rgb_data[cast(uint)source2_idx]))>>1;
				}
				int  old_xoffset = 0;
				auto xoffset = cast(int)width;
				int  xdepth  = 2;
				while(cast(int)width/xdepth) {
					ulong deltaxoffset = cast(int)width/xdepth;
					foreach(ulong x; 0..deltaxoffset) {
						auto rgb_data_idx = (yoffset    +y    )*stride + (xoffset+x);
						auto source1_idx  = (old_yoffset+y*2  )*stride + (old_xoffset+x*2);
						auto source2_idx  = (old_yoffset+y*2+1)*stride + (old_xoffset+x*2+1);

						*cast(uint*)&log_rgb_data[cast(uint)rgb_data_idx] = ((0xfefefefeL & log_rgb_data[cast(uint)source1_idx])+
						                                                     (0xfefefefeL & log_rgb_data[cast(uint)source2_idx]))>>1;
						*cast(uint*)&rgb_data[cast(uint)rgb_data_idx]     = ((0xfefefefeL & rgb_data[cast(uint)source1_idx])+
						                                                     (0xfefefefeL & rgb_data[cast(uint)source2_idx]))>>1;
					}
					old_xoffset = xoffset;
					xoffset += deltaxoffset;
					xdepth *= 2;
				}
			}
			old_yoffset = yoffset;
			yoffset += deltayoffset;
			ydepth *= 2;
		}
	}

	//import draw : Draw, Transform;
	import graphics, transform;

	override @trusted void draw(BackendInterface d, in Transform[3] t)  {

		ulong handle = bitmap_handle;
		if (t[2].logscale) {
			handle = bitmap_handle_log;
		}
		//auto pixel_width = t.get_pixel_width();
		//auto pixel_height = t.get_pixel_height();
		//auto xmipmap_pos = 1;
		//auto ymipmap_pos = 1;
		//int rectangle_xoffset = 0;
		//int rectangle_yoffset = 0;
		//auto rectangle_width  = cast(int)_bins_x;
		//auto rectangle_height = cast(int)_bins_y;
		//while (rectangle_width>32 && pixel_width  > getBinWidth()*xmipmap_pos) {
		//	xmipmap_pos*=2;
		//	rectangle_xoffset += rectangle_width;
		//	rectangle_width /= 2;
		//}
		//while (rectangle_height>32 && pixel_height > getBinHeight()*ymipmap_pos) {
		//	ymipmap_pos*=2;
		//	rectangle_yoffset += rectangle_height;
		//	rectangle_height /= 2;
		//}

		if (t[2].min != _zmin || t[2].max() != _zmax) {
			_zmin=t[2].min;
			_zmax=t[2].max;
			uint[] bitmap_data     = d.access_bitmap_data(bitmap_handle);
			uint[] bitmap_data_log = d.access_bitmap_data(bitmap_handle_log);
			//assert(bitmap_data.length == _bin_data.length);
			generate_rgb_data(_bin_data, _bins_x, _bins_y, _zmin, _zmax, _bins_x*2, bitmap_data, bitmap_data_log);
			d.access_bitmap_done(bitmap_handle);
			d.access_bitmap_done(bitmap_handle_log);
		}

		double h_l = t[0].log(_left);
		double h_r = t[0].log(_right);
		double h_b = t[1].log(_bottom);
		double h_t = t[1].log(_top);

		int Nx = 1;
		int Ny = 1;
		if (t[0].logscale) Nx = 30;
		if (t[1].logscale) Ny = 30;
		if (t[0].logscale && t[1].logscale) {Nx = 20; Ny = 20;}

		// more advanced tiling (linear sizing of tiles in canvas space)
		foreach (ix; 0..Nx) {
			foreach (iy; 0..Ny) {
				double sx1 = 0+_bins_x*(ix+0.0)/Nx;
				double sy1 = 0+_bins_y*(iy+0.0)/Ny;
				double sx2 = 0+_bins_x*(ix+1.0)/Nx;
				double sy2 = 0+_bins_y*(iy+1.0)/Ny;
				double sw = sx2-sx1;//1.0*_bins_x/Nx;
				double sh = sy2-sy1;//1.0*_bins_y/Ny;

				double t_x1 = h_l+(h_r-h_l)*(ix+0.0)/Nx;
				double t_y1 = h_b+(h_t-h_b)*(iy+0.0)/Ny;
				double t_x2 = h_l+(h_r-h_l)*(ix+1.0)/Nx;
				double t_y2 = h_b+(h_t-h_b)*(iy+1.0)/Ny;
				double t_w = t_x2-t_x1;//(h_r-h_l)/Nx;
				double t_h = t_y2-t_y1;//(h_t-h_b)/Ny;

				double e_x1 = t[0].exp(t_x1);
				double e_y1 = t[1].exp(t_y1);
				double e_x2 = t[0].exp(t_x2);
				double e_y2 = t[1].exp(t_y2);

				double iix1 = (e_x1-_left  )*Nx/(_right-_left);
				double iiy1 = (e_y1-_bottom)*Ny/(_top-_bottom);
				double iix2 = (e_x2-_left  )*Nx/(_right-_left);
				double iiy2 = (e_y2-_bottom)*Ny/(_top-_bottom);

				double _sx1 = 0+_bins_x*(iix1)/Nx;
				double _sy1 = 0+_bins_y*(iiy1)/Ny;
				double _sx2 = 0+_bins_x*(iix2)/Nx;
				double _sy2 = 0+_bins_y*(iiy2)/Ny;
				double _sw  = _sx2-_sx1;
				double _sh  = _sy2-_sy1;

				double dx = t[0].world2canvas(t_x1);
				double dy = t[1].world2canvas(t_y1);
				double dw = t[0].world2canvas_delta(t_w);
				double dh = t[1].world2canvas_delta(t_h);

				// choose the correct mipmap
				double abs(double x) {return x<0?-x:x;}
				ulong binsx = _bins_x;
				ulong originx = 0;
				while (abs(_sw) > abs(dw)) {
					if (binsx <= 32) break;
					double delta = _sx1 - originx;
					originx += binsx;
					_sx1 = originx + delta/2.0;
					_sw /= 2.0;
					binsx /= 2;
				}
				ulong binsy = _bins_y;
				ulong originy = 0;
				while (abs(_sh) > abs(dh)) {
					if (binsy <= 32) break;
					double delta = _sy1 - originy;
					originy += binsy;
					_sy1 = originy + delta/2.0;
					_sh /= 2.0;
					binsy /= 2;
				}

				if (t[0].logscale) dw+=0.5; // to avoid small visible gaps between the tiles
				if (t[1].logscale) dh-=0.5; // to avoid small visible gaps between the tiles

				d.draw_bitmap(handle, _sx1,_sy1,_sw,_sh, dx,dy,dw,dh);

				//d.set_line_width(1);
				//d.set_color(1,0,0);
				//d.rectangle(dx,dy,dx+dw,dy+dh);
				//d.stroke();
			}
		}
		d.set_line_width(1);
		d.set_color(1,0,0);
		d.rectangle(t[0].world2canvas(t[0].log(_left)),
			        t[1].world2canvas(t[1].log(_bottom)), 
			        t[0].world2canvas(t[0].log(_right)),
			        t[1].world2canvas(t[1].log(_top)));
		d.stroke();


		//// in order to approximate correct log scaling, the bitmap is separated into tiles
		//int Nx = 1;
		//int Ny = 1;
		//if (t._logx) Nx = 30;
		//if (t._logy) Ny = 30;
		//if (t._logx && t._logy) {Nx = 20; Ny = 20;}
		//foreach (ix; 0..Nx) {
		//	foreach (iy; 0..Ny) {
		//		auto sx = rectangle_xoffset+rectangle_width*ix/Nx;
		//		auto sy = rectangle_yoffset+rectangle_height*iy/Ny;
		//		auto sw = rectangle_width/Nx;
		//		auto sh = rectangle_height/Ny;
		//		auto dx = t.transform_world2canvas_x(t.log_x(_left+(_right-_left)*ix/Nx));
		//		auto dy = t.transform_world2canvas_y(t.log_y(_bottom+(_top-_bottom)*iy/Ny));
		//		auto dw = t.transform_world2canvas_x(t.log_x(_left+(_right-_left)*(ix+1)/Nx))-t.transform_world2canvas_x(t.log_x(_left+(_right-_left)*(ix)/Nx));
		//		auto dh = t.transform_world2canvas_y(t.log_y(_bottom+(_top-_bottom)*(iy+1)/Ny))-t.transform_world2canvas_y(t.log_y(_bottom+(_top-_bottom)*(iy)/Ny));
		//		d.draw_bitmap(handle, sx,sy,sw,sh, dx,dy,dw,dh);
		//	}
		//}


		//d.draw_bitmap(handle,
		//	rectangle_xoffset,rectangle_yoffset,rectangle_width,rectangle_height,
		//	t.transform_world2canvas_x(t.log_x(_left)), t.transform_world2canvas_y(t.log_y(_bottom)),
		//	t.transform_world2canvas_x(t.log_x(_right))-t.transform_world2canvas_x(t.log_x(_left)), 
		//	t.transform_world2canvas_y(t.log_y(_top))-t.transform_world2canvas_y(t.log_y(_bottom))
		//);

		//double bw = getBinWidth();
		//double bh = getBinHeight();
		//foreach(idx, bin; _bin_data) {
		//	if (bin is double.init) continue;
		//	auto x_idx = idx%_bins_x;
		//	auto y_idx = idx/_bins_x;
		//	double x1 = _left+bw*x_idx;
		//	double y1 = _bottom+bh*y_idx;
		//	double x2 = x1+bw;
		//	double y2 = y1+bh;
		//	x1 = t.transform_world2canvas_x(t.log_x(x1));
		//	x2 = t.transform_world2canvas_x(t.log_x(x2));
		//	y1 = t.transform_world2canvas_y(t.log_y(y1));
		//	y2 = t.transform_world2canvas_y(t.log_y(y2));
		//	import std.algorithm;
		//	auto c = (1.0-gen_color(bin,t));//.clamp(0.0,1.0);
		//	d.set_color(c,c,c);
		//	d.rectangle(x1-0.2,y1+0.2, x2+0.2,y2-0.2);
		//	d.fill();
		//}
	}

	double getBinWidth() const
	{
		return (_right - _left) / _bins_x;
	}
	double getBinHeight() const
	{
		return (_top - _bottom) / _bins_y;
	}
	double getWidth() const
	{
		return _right-_left;
	}
	double getHeight() const
	{
		return _top-_bottom;
	}
	override double getValue(double x, double y) {
		auto x_idx = ((x-_left)*_bins_x/(_right-_left));
		//writeln("x_idx=",x_idx);
		auto y_idx = ((y-_bottom)*_bins_y/(_top-_bottom));
		//writeln("y_idx=",y_idx, " ", _bottom, " ", _top);
		auto idx = cast(int)y_idx*_bins_x+cast(int)x_idx;
		//writeln("idx=",idx);
		if (x_idx < 0 || x_idx >= _bins_x) {
			return double.init;
		}
		if (y_idx < 0 || y_idx >= _bins_y) {
			return double.init;
		}
		if (idx >= 0 && idx < _bin_data.length) {
			return _bin_data[cast(uint)idx];
		}
		return double.init;
	}
	override bool get_leftright(out double[2] lr, in Transform[3] t) {
		import std.stdio;
		if (t[0].logscale && _left <= 0 && _right <= 0) return false;
		if (_left == _right)                      return false;
		lr[0] = t[0].log(_left, getBinWidth()/2.0);
		lr[1] = t[0].log(_right);
		return true;
	}
	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t) {
		import std.stdio;
		if (_bin_data is null) {
			return false;
		}
		if (_bin_data.length == 0) {
			return false;
		}
		if (_bottom is double.init || _top   is double.init || 
			_left   is double.init || _right is double.init) {
			return false;
		}
		if (t[1].logscale && _bottom <= 0 && _top <= 0) {
			return false;
		}
		if (_bottom == _top) {
			return false;
		}   
		bt[0] = t[1].log(_bottom, getBinHeight()/2.0); // set the default_zero to half the bin size
		bt[1] = t[1].log(_top);
		return true;
	}

	override bool get_zminmax_in_leftright_bottomtop(out double[2] minmax, 
	                                                  in double[2] lr, in double[2] bt, in Transform[3] t) 
	{
		import std.stdio;
		if (_bin_data is null) {
			return false;
		}
		if (_bin_data.length == 0) {
			return false;
		}
		if (_bottom is double.init || _top is double.init || 
			_left is double.init   || _right is double.init) {
			return false;
		}

		import std.math;
		double left  = t[0].exp(lr[0]);
		double right = t[0].exp(lr[1]);
		double bottom = t[1].exp(bt[0]);
		double top    = t[1].exp(bt[1]);
		// transform into bin numbers
		left = (left-_left)/getBinWidth();
		right = (right-_left)/getBinWidth();
		bottom = (bottom-_bottom)/getBinHeight();
		top = (top-_bottom)/getBinHeight();

		import std.algorithm, std.stdio;
		double minimum, maximum;
		double minimum_larger0 = 0.0;
		bool initialize = true;
		int leftbin   = cast(int)(max(left,0));
		int rightbin  = cast(int)(min(right,_bins_x));
		int bottombin = cast(int)(max(bottom,0));
		int topbin    = cast(int)(min(top,_bins_y));
		if (leftbin > rightbin) return false;
		if (bottombin > topbin) return false;

		foreach(j ; bottombin..topbin+1) {
			if (j < 0) {
				continue;
			}
			if (j >= _bins_y) {
				break;
			}
			foreach(i ; leftbin..rightbin+1){
				//writeln(i, " ", j );
				if (i < 0) {
					continue;
				}
				if (i >= _bins_x) {
					break;
				}
				import std.algorithm;
				if(!(i >= 0 && i < _bins_x)) { 
					writeln ("getZminZmaxInLeftRightBottomTop() (i >= 0 && i < _bins_x) was violated\r");
				}
				if(!(j >= 0 && j < _bins_y)) { 
					writeln ("getZminZmaxInLeftRightBottomTop() (j >= 0 && j < _bins_y) was violated\r");
				}
				ulong idx = _bins_x*j+i;
				double d = _bin_data[cast(uint)idx];
				//writeln("d = ", d);
				if (d !is double.init) {
					if (initialize) {
						minimum = d;
						maximum = d;
						initialize = false;
					}
					minimum = min(minimum, d);
					maximum = max(maximum, d);

					if (d>0.0 && (minimum_larger0 == 0.0 || d < minimum_larger0)) {
						minimum_larger0 = d;
					} 
				}
			}
		}

		if (!initialize) {
			if (minimum is double.init || maximum is double.init) return false;
			if (t[2].logscale && minimum <= 0 && maximum <= 0) return false;
			if (minimum == maximum) return false;

			minmax[0] = t[2].log(minimum, minimum_larger0/2.0);
			minmax[1] = t[2].log(maximum);
			return true;
		}
		return false;

	}


private:
	double[] _bin_data;
	double _left, _right;
	double _bottom, _top;
	double _zmin, _zmax;
	ulong _bins_x, _bins_y;

	ulong bitmap_handle;
	ulong bitmap_handle_log;


	string _xlabel, _ylabel, _zlabel;

	int     stride;
	ubyte[] _rgb_data;
	ubyte[] _log_rgb_data;

	BackendInterface backend;

	//import cairo.Pattern, gdk.Cairo;
	//Pattern _image_surface_pattern;
	//Pattern _log_image_surface_pattern;

}

