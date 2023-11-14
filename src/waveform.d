//    Fairy: Flexible Analysis of Ionizing Radiation Yields
//    Copyright (C) 2019 Michael Reese

//    This program is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.

//    This program is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.

//    You should have received a copy of the GNU General Public License
//    along with this program.  If not, see <https://www.gnu.org/licenses/>.

@safe:

import item;
import std.json;
import serializeJSON;


class WaveformFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		import std.stdio;
		return new Waveform(json);
	}
}


import graphics;
class Waveform : Visual, Item
{
public:
	struct Data {
		@SERIALIZE int      N;
		@SERIALIZE double   left;
		@SERIALIZE double   right;
		@SERIALIZE double[] data;
	}
	Data d;
	// data array contains concatenated polynomial coefficients up to order O.
	// each polynom is defined by N=order+1 coefficients
	// example N=4 (order=3):
	//   data array contains: [a0,b0,c0,d0, a1,b1,c1,d1, a2,b2,c2,d2, a3,...]
	//   y0(x-x0)=a0+b0*x+c0*x^2+d0*x^3
	//   y1(x-x1)=a1+b1*x+c1*x^2+d1*x^3
	// example N=2 (order=1):
	//   data array contains: [a0,b0, a1,b1, a2,b2, a3,...]
	//   y0(x-x0)=a0+b0*x
	//   y1(x-x1)=a1+b1*x
	// ...
	this (Data data) {	d = data; 	}
	this(double[] data, uint N, double left, double right) {
		assert(data.length%N == 0);
		d.data  = data;
		d.N     = N;
		d.left  = left;
		d.right = right;	
	}
	this(ref JSONValue json) { d = deserialize!Data(json); }
	override JSONValue toJSON() const { return serialize(d); }
	override string get_type() const pure {
		return "waveform.Waveform";
	}
	override ulong getVersion() {
		return item_version;
	}
	override void overrideVersion(ulong new_version) {
		item_version = new_version;
	}
	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null)
	{
		return new WaveformVisualizer(item_version, d.data, d.N, d.left, d.right);
	}
	//override void destroy() {}
	//override ulong getVersion() {
	//	return _version;
	//}
private:
	ulong item_version = 0;
}


//////////////////////////////////////////////////
// Visualizer for 1D Histograms
class WaveformVisualizer : Visualizer 
{
public:

	this(ulong itemversion, double[] data, uint N, double left, double right)
	{
		ulong dim;
		super(itemversion, dim=1);
		_data        = data.idup;
		_N           = N;
		_left        = left;
		_right       = right;
		_mipmap_data = make_mipmap_data();
	}
	import graphics, transform;
	@trusted override void draw(BackendInterface d, in Transform[3] t) const  
	{
		import std.stdio;

		double left  = t[0].exp(t[0].min);  // linear world coordinates
		double right = t[0].exp(t[0].max); // linear world coordinates

		ulong segments = _data.length/_N;
		double segment_width = (_right-_left)/segments;

		double left_idx  = (left -_left)/segment_width;
		double right_idx = (right-_left)/segment_width + 1;

		//writeln(_right, " - ", _left , " / ", segments, "   segwidth=", segment_width);
		//writeln(left, "  :   ", right);
		//writeln(left_idx, "  :   ", right_idx);

		if (left_idx > segments) return;
		long idx_l = 0;
		if (left_idx > 0) idx_l = cast(long)left_idx;

		long idx_r = segments;
		if (right_idx < segments) idx_r = cast(long)right_idx;
		if (right_idx < 0) return;

		//writeln("idx_l:", idx_l, "   idx_r:", idx_r);



		import std.range;

		double line_width = 2.0;
		d.set_line_width(line_width);
		d.set_color(1.0,0.0,0.0);

		bool draw_segment(double x1, double x2, const double[] coeff, MinMax minmax) {
			//writeln("draw_segment ", x1, " ", x2);
			if (x1 > t[0].exp(t[0].max)) return false;
			if (x2 < t[0].exp(t[0].min))  return false;
			double px1 = x1;
			if (px1 < t[0].exp(t[0].min)) px1 = t[0].exp(t[0].min);
			double px2 = x2;
			if (px2 > t[0].exp(t[0].max)) px2 = t[0].exp(t[0].max);

			int n_pixels = cast(int)( (t[0].log(px2) - t[0].log(px1))/t[0].pixel_width)+1;

			double dy=t[1].world2canvas(t[1].log(minmax.min)) - 
			          t[1].world2canvas(t[1].log(minmax.max));
			if (dy < 0) dy = -dy;
			//writeln("min=",minmax.min, "   max=",minmax.max, "  dy=",dy);
			int n_pixels_y = cast(int)(dy/line_width);
			if (n_pixels_y>10) n_pixels_y = 10;
			//writeln("n_pixels=",n_pixels, "  n_pixels_y=",n_pixels_y);
			if (n_pixels_y > n_pixels) n_pixels = n_pixels_y;
			if (n_pixels > 30) n_pixels = 30;
			//writeln("num pixels = ", n_pixels);


			double dx = (t[0].log(px2) - t[0].log(px1))/n_pixels;

			double x;
			double line_x1 = t[0].log(px1);
			x = (t[0].exp(line_x1)-x1)/(x2-x1);
			if (x < 0) x = 0;
			if (x > 1) x = 1;
			double line_y1 = t[1].log(eval_polynom(x, coeff));
			for (int i = 0; i < n_pixels; ++i) {
				double line_x2 = t[0].log(px1)+(i+1)*dx;
				x = (t[0].exp(line_x2)-x1)/(x2-x1);
				if (x < 0) x = 0;
				if (x > 1) x = 1;
				double line_y2 = t[1].log(eval_polynom(x, coeff));


				d.line(t[0].world2canvas(line_x1), t[1].world2canvas(line_y1),
					   t[0].world2canvas(line_x2), t[1].world2canvas(line_y2));
				//line(d,t, line_x1,line_y1, line_x2,line_y2);
				//point(d,t, line_x1, line_y1);
				//point(d,t, line_x2, line_y2);
				line_x1 = line_x2;
				line_y1 = line_y2;
			}
			d.stroke();
			return true;
		}


		ulong x_idx = _N*idx_l;
		double x = _left+segment_width*x_idx/_N;
		outer: for(;;) {
			if (x_idx/_N >= idx_r) break;
			double x1 = t[0].world2canvas(t[0].log(x));
			double x2 = t[0].world2canvas(t[0].log(x+segment_width));
			if (x2-x1 <= d.get_line_width) {
				//writeln("switch to mipmap");
				long mipmap_level = 0;
				long mipmap_idx = x_idx/_N;
				auto mipmap = _mipmap_data;
				for (;;) {
					inner: for (;;) {
						//writeln("inner");
						if (mipmap_level >= mipmap.length)             break outer;
						if (mipmap_idx >= mipmap[cast(uint)mipmap_level].length) break outer;		
						x1 = t[0].world2canvas(t[0].log(x));
						x2 = t[0].world2canvas(t[0].log(x+segment_width));
						if ((x2-x1 > d.get_line_width/2 /*&& (mipmap_idx%2==0)*/) || mipmap_level+1 == mipmap.length) {
							break inner;
						}
						mipmap_idx   /= 2;
						mipmap_level += 1;
						segment_width *= 2;
						//import std.stdio; writeln("switch to mipmap inner ", mipmap_level);
						d.stroke();
						//color=(color+1)%2;
						//d.set_color(color,0,0);

					}
					double vmin = t[1].log(mipmap[cast(uint)mipmap_level][cast(uint)mipmap_idx].min);
					double vmax = t[1].log(mipmap[cast(uint)mipmap_level][cast(uint)mipmap_idx].max);
					double y1 = t[1].world2canvas(vmin);
					double y2 = t[1].world2canvas(vmax);

					import std.algorithm;
					if (y2<y1) swap(y1,y2);
					d.vertical_line(x1, y1-0.5*line_width, y2+0.5*line_width);
					d.stroke();
					//writeln(mipmap_level, "  vertical_line, ", x1, " ", y1, " " , y2);

					x += segment_width;
					mipmap_idx += 1;
					if (t[0].log(x) > t[0].max) break outer;

				}

			}

			//writeln("x_idx=",x_idx, "   x=",x);
			auto seg = _data[x_idx..x_idx+_N];
			auto minmax = _mipmap_data[0][x_idx/_N];
			draw_segment(x, x+segment_width, seg, minmax);
			point(d,t, t[0].log(x),t[0].log(seg[0]),d.get_line_width+1);
			d.stroke();
			x_idx += _N;
			x += segment_width;
		}
	}

	void point(BackendInterface drawer, in Transform[3] t, double x, double y, double size=2.0) const {
		double tx = t[0].world2canvas(t[0].log(x));
		if (t[1].logscale && y <= 0) return;
		double ty = t[1].world2canvas(t[1].log(y));
		//drawer.line(tx-size, ty-size, tx+size, ty+size);
		//drawer.line(tx+size, ty-size, tx-size, ty+size);
		size/=1.5;

		drawer.line(tx-size, ty-size,  tx+size, ty-size);
		drawer.line(tx-size, ty+size,  tx+size, ty+size);
		drawer.line(tx-size, ty-size,  tx-size, ty+size);
		drawer.line(tx+size, ty-size,  tx+size, ty+size);
	}


	double getBinWidth() const pure
	{
		return (_right - _left) / (_data.length / _N);
	}

	MinMax minmax_polynom(in double[] coeff, in double xleft = 0.0, in double xright = 1.0) const pure {
		import std.math, std.algorithm;
		assert(coeff !is null);
		assert(coeff.length > 0);
		assert(xleft >= 0.0);
		assert(xright <= 1.0);
		assert(xleft <= xright);
		if (coeff.length == 1) {
			return MinMax(coeff[0], coeff[0]);
		}
		if (coeff.length == 2) {
			double a = coeff[0];
			double b = coeff[0]+coeff[1];
			double[2] minmax_candidates = [eval_polynom(xleft,coeff), eval_polynom(xright,coeff)];
			return MinMax(minmax_candidates[0..$].minElement,
				          minmax_candidates[0..$].maxElement);
		}
		if (coeff.length == 3) {
			double a = coeff[0];
			double b = coeff[1];
			double c = coeff[2];
			double x0 = -b/c/2.0;
			double yleft = eval_polynom(xleft,coeff);
			double yright = eval_polynom(xright,coeff);
			double[3] minmax_candidates = [yleft,yright,yright];
			if (x0 > xleft && x0 < xright) {
				minmax_candidates[2] = eval_polynom(x0,coeff);
			}
			return MinMax(minmax_candidates[0..$].minElement, 
				          minmax_candidates[0..$].maxElement);
		}
		if (coeff.length == 4) {
			double a = coeff[0];
			double b = coeff[1];
			double c = coeff[2];
			double d = coeff[3];
			double R = c*c - 3.0*b*d;
			double yleft = eval_polynom(xleft,coeff);
			double yright = eval_polynom(xright,coeff);
			double[4] minmax_candidates = [yleft,yright,yright,yright];

			if (R >= 0) {
				double x0;
				if (d == 0) {
					x0 = -b/(2.0*c);
					if (x0 >= xleft && x0 <= xright) {
						minmax_candidates[2] = eval_polynom(x0, coeff);
					}
				} else {
					x0 = -(sqrt(R)+c)/(3.0*d);
					if (x0 >= xleft && x0 <= xright) {
						minmax_candidates[2] = eval_polynom(x0, coeff);
					}
					x0 =  (sqrt(R)-c)/(3.0*d);
					if (x0 >= xleft && x0 <= xright) {
						minmax_candidates[3] = eval_polynom(x0, coeff);
					}
				}
			}
			auto result = MinMax(minmax_candidates[0..$].minElement, 
				          minmax_candidates[0..$].maxElement);
			return result;
		}
		import std.range;
		immutable int N = 10;
		auto minmax_candidates = iota(10+1).map!(x=>x/N).map!(x=>eval_polynom(x,coeff));
		return MinMax(minmax_candidates.minElement, minmax_candidates.maxElement);
	}
	double eval_polynom(double x, const double[] coeff) const pure {
		assert(coeff !is null);
		assert(coeff.length > 0);
		assert(x >= 0.0 && x <= 1.0);
		double result = coeff[$-1];
		for (int i = cast(int)coeff.length-2; i >= 0; --i) {
			result *= x;
			result += coeff[i];
		}
		return result;
	}
	override double getValue(double x, double y) {
		double x_idx = ((x-_left)*(_data.length/_N)/(_right-_left));
		if (x_idx > 0 && x_idx < _data.length/_N) {
			auto x_idx_int = cast(int)x_idx;
			auto dx = x_idx - x_idx_int;
			return eval_polynom(dx, _data[_N*x_idx_int.._N*(x_idx_int+1)]);
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
		double left = lr[0];
		double right = lr[1];
		import std.stdio;
		if (_data is null) {
			return false;
		}
		if (_data.length == 0) {
			return false;
		}
		if (_left is _left.init || _right is _right.init) {
			return false;
		}


		right = t[0].exp(right);
		left  = t[0].exp(left);

		// transform into bin numbers
		left  = (left-_left)/getBinWidth();
		right = (right-_left)/getBinWidth();

		// prevent overflow when converting to in further down in the code
		if (left >= int.max/2) left = int.max/2;
		if (right >= int.max/2) right = int.max/2;


		if (left >= _mipmap_data[0].length || right <= 0) {
			return false;
		}

		import std.algorithm;
		int leftbin  = max(cast(int)left,0);
		int rightbin = min(cast(int)(right+1),_mipmap_data[0].length);
		if (leftbin > rightbin) {
			import std.stdio;
			writeln("unexpected leftbin,rightbin: ", leftbin, "," , rightbin, "\r");
			return false;
		}
		double x_frac_left = left-leftbin;
		double x_frac_right = right-(rightbin-1);
		double[6] extrema;

		import std.algorithm;
		uint n_extrema = 0;
		if (leftbin+1 == rightbin &&
			x_frac_left >= 0 && x_frac_left <= 1.0 &&
			x_frac_right >= 0.0 && x_frac_right <= 1.0) {
			auto coeff = _data[leftbin*_N..(leftbin+1)*_N];
			//writeln("single ", coeff, " ", x_frac_left, " ", x_frac_right);
			auto minmax_left = minmax_polynom(coeff, x_frac_left, x_frac_right);
			extrema[n_extrema++] = minmax_left.min;
			extrema[n_extrema++] = minmax_left.max;
		} else {
			if (x_frac_left >= 0 && x_frac_left <= 1.0) {
				auto coeff = _data[leftbin*_N..(leftbin+1)*_N];
				//writeln("left ", coeff, " ", x_frac_left, " ", 1.0);
				auto minmax_left = minmax_polynom(coeff, x_frac_left, 1.0);
				extrema[n_extrema++] = minmax_left.min;
				extrema[n_extrema++] = minmax_left.max;
				++leftbin;
			}
			if (x_frac_right >= 0.0 && x_frac_right <= 1.0) {
				auto coeff = _data[(rightbin-1)*_N..rightbin*_N];
				//writeln("right ", coeff, " ", 0.0, " ", x_frac_right);
				auto minmax_right = minmax_polynom(coeff, 0.0, x_frac_right);
				extrema[n_extrema++] = minmax_right.min;
				extrema[n_extrema++] = minmax_right.max;
				//writeln("right n_extrema ", n_extrema, "    ", extrema[0..n_extrema]);
				--rightbin;
			}
			if (leftbin < rightbin) { // one entire bin visible
				//writeln("mid ", leftbin, " ", rightbin);
				extrema[n_extrema++] = _mipmap_data[0][leftbin..rightbin].map!(x=>x.max).maxElement();
				//writeln("max: ", extrema[n_extrema-1]);
				extrema[n_extrema++] = _mipmap_data[0][leftbin..rightbin].map!(x=>x.min).minElement();
				//writeln("min: ", extrema[n_extrema-1]);
			} 
		}
		double minimum = extrema[0..n_extrema].minElement;
		double maximum = extrema[0..n_extrema].maxElement;

		if (t[1].logscale) {
			auto bins_larger_0 = _mipmap_data[0].map!(x=>x.max).filter!(x=>x>0.0);
			double minimum_larger_0;
			if (!bins_larger_0.empty) minimum_larger_0 = bins_larger_0.minElement();
			if (minimum_larger_0 is double.init) return false;
			bt[0] = t[1].log(minimum, minimum_larger_0/2.0);
			bt[1] = t[1].log(maximum, minimum_larger_0/2.0);
			//writeln("minimum_larger_0=",minimum_larger_0);
			return true;
		}
		bt[0] = minimum;
		bt[1] = maximum;
		return true;
	}


private:

	/////////////////////////////////////////////////////////
	// calculate mipmap data from _data
	// has to be pure to be allowed to return immutable
	immutable(MinMax[][]) make_mipmap_data() pure 
	{
		if (_data is null) {
			return null;
		}
		import std.algorithm, std.stdio;
		auto mipmap_data = new MinMax[][0];
		for (int idx = 0;; ++idx) {
			if (idx == 0) {
				mipmap_data ~= new MinMax[_data.length/_N];
				foreach(n, ref mip; mipmap_data[$-1]) {
					const double[] coeff = _data[n*_N..(n+1)*_N];
					mip = minmax_polynom(coeff);
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
	immutable(double[]) _data;
	immutable(int)     _N;
	immutable(double) _left, _right;

	// mipmap data // TODO implement
	struct MinMax {double min; double max;} ;
	immutable(MinMax[][]) _mipmap_data;

	string _xlabel;
	string _ylabel;
}
