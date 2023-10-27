module histogram;
@safe:

import fairy;
import std.json;
import serializeJSON;

static this() {
	fairy.add_item_factory("histogram.FileHistogram", new FileHistogramFactory);
}

class FileHistogramFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new FileHistogram(json);
	}
}

import graphics;
class FileHistogram : Visual, Item {
	struct Data {
		@SERIALIZE string filename;
	}
	Data data;
	this(Data d)             { data = d; }
	this(ref JSONValue json) { data = deserialize!Data(json); }
	// Item Interface
	override JSONValue toJSON() const { return serialize(data); }
	override string get_type() const { 
		return "histogram.FileHistogram"; 
	}

	// Visual Interface
	override Visualizer create_visualizer(BackendInterface backend) {
		HistData hist_data = read_file(data.filename);
		switch(hist_data.dim) {
			case 1: return new Hist1Visualizer(item_version, hist_data.data, hist_data.left, hist_data.right);
			break;
			default: assert(false);
		}
	}
private:
	ulong item_version = 0;

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
	this(ulong itemversion,/+ulong colorIdx, +/double[] data, double left, double right)//, string xlabel = null, string ylabel = null)
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
			drawMixedHistogram(d,t, _left,_right, _bin_data, _mipmap_data, line_width);
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
		double maximum = _bin_data[leftbin..rightbin].maxElement();
		double minimum = _bin_data[leftbin..rightbin].minElement();

		if (t[1].logscale) {
			auto bins_larger_0 = _bin_data.filter!(x=>x>0.0);
			double minimum_larger_0;
			if (!bins_larger_0.empty) minimum_larger_0 = _bin_data.filter!(x=>x>0.0).minElement();
			if (minimum_larger_0 is double.init) return false;
			bt[0] = t[1].log(minimum, minimum_larger_0/2.0);
			bt[1]    = t[1].log(maximum, minimum_larger_0/2.0);
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
					mip.min = min(mipmap_data[idx-1][n2].min, mipmap_data[idx-1][n2_plus_1].min);
					mip.max = max(mipmap_data[idx-1][n2].max, mipmap_data[idx-1][n2_plus_1].max);
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
void drawMixedHistogram(T, MinMax)(BackendInterface d, Transform[3] t, double min, double max, immutable(T[]) bins, immutable(MinMax[][]) mipmap, double line_width) {
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

d.set_line_width(2);
d.set_color(1,0,0);

	double bin_width = (max-min)/bins.length;

	// find the starting index of the visible part of the histogram
	double xhist = min;
	import std.math;
	double x_start = t[0].exp(min);//logscale?exp(t[0].min):(t[0].min);
	uint idx_start = 0;
	double index = ((x_start-min)/bin_width);
	if (index < 0) index = 0;
	idx_start = cast(uint)index;
	if (idx_start >= bins.length) return;
	xhist = min+bin_width*idx_start;
	double x1,x2, y1,y2;
	x1 = t[0].world2canvas(t[0].log(xhist));
	y1 = t[1].world2canvas(t[1].log(bins[idx_start]));
	// draw horizontal part
	xhist += bin_width;
	x2 = t[0].world2canvas(t[0].log(xhist));
	d.horizontal_line(y1, x1, x2);
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
		d.vertical_line(x2, y1d-0.5*d.get_line_width, y2d+0.5*d.get_line_width);
		y1 = y2;

		// draw horizontal part of next bin
		x1 = x2;
		xhist += bin_width;
		mipmap_idx += 1;
		x2 = t[0].world2canvas(t[0].log(xhist));
		d.horizontal_line(y2, x1, x2);
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
				d.vertical_line(x1, y1-0.5*d.get_line_width, y2+0.5*d.get_line_width);

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
