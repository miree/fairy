//    Fairy: Flexible Analysis of Ionizing Radiation Yields
//    Copyright (C) 2019-2026 Michael Reese

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

module transform;
@safe:

import std.math;
import serializeJSON;

struct Transform 
{
//private: // serialization does (of course)_not work if this is private
	@SERIALIZE double minimum = -1;
	@SERIALIZE double maximum =  1;
	@SERIALIZE double min_width = 1e-3;
	@SERIALIZE double max_width = 1e10;
	@SERIALIZE bool   logscale = false;

	double delta = 0;
	double scale = 1;

	double a,b; // transformation coefficients
	// use with negative canvas_width, if the positive 
	//  canvas coordinates go from top to bottom (e.g. the y-axis)
	void update_coefficients(in int segment, in int num_segments, in int canvas_width, in bool inverse = false) {
		double segment_width  = 1.0*canvas_width/num_segments;
		if (inverse) {
			b = -segment_width / width;
			a = segment*segment_width - b * max;
		} else {
			b = segment_width / width;
			a = segment*segment_width - b * min;
		}
	}

	// for translation and scaling operation
	double translating_start_canvas = 0.0;
	double scaling_start_canvas     = 0.0;
	double scaling_start_world      = 0.0;

public:
	void translate_one_step(in double canvas_start, in int num_segments, in int canvas_width, in double canvas_step) {
		translate_start(canvas_start, num_segments, canvas_width);
		translate_ongoing(canvas_step);
		translate_finish();
	}
	void translate_start(in double canvas_start, in int num_segments, in int canvas_width) {
		update_coefficients(0, num_segments, canvas_width);
		translating_start_canvas = canvas_start;
	}
	void translate_ongoing(in double canvas_current) {
		delta = (canvas_current - translating_start_canvas)/b;
	}
	void translate_finish() {
		minimum -= delta;
		maximum -= delta;
		delta = 0;
	}
	void scale_one_step(in double canvas_start, in int num_segments, in int canvas_width, in double canvas_step, in double factor, in bool inverse)
	{
		scale_start(canvas_start, num_segments, canvas_width, inverse);
		scale_ongoing(canvas_start+canvas_step, factor);
		scale_finish();
	}
	void scale_start(in double canvas_start, in int num_segments, in int canvas_width, in bool inverse) {
		update_coefficients(0, num_segments, canvas_width, inverse);
		scaling_start_canvas = canvas_start;
		double reduced_canvas_start = reduce_canvas(canvas_start, num_segments, canvas_width);
		import std.stdio;
		//writeln("canvas_start:", canvas_start, " reduced_canvas_start:", reduced_canvas_start);
		scaling_start_world  = canvas2world(reduced_canvas_start);
	}
	void scale_ongoing(in double canvas_current, in double factor) {
		double scale_distance = canvas_current - scaling_start_canvas;
		scale = std.math.exp(scale_distance*factor);
		double new_minimum = scaling_start_world - scale*(scaling_start_world-minimum);
		delta = minimum - new_minimum;
	}
	void scale_finish() {
		double w = width;
		double new_minimum = minimum - delta;
		double new_maximum = new_minimum + w;
		scale = 1;
		delta = 0;
		// route through set_minmax() so interactive zooming (unlike the old direct assignment
		// here) is subject to the same min_width/max_width floor/ceiling as every other way of
		// changing the viewport. Without this, repeated zoom-in can shrink the width toward 0
		// (and, via IEEE-754 underflow, eventually to exactly 0), which makes the grid-line
		// tick-spacing loop in graphics.d's vertical_grid()/horizontal_grid() compute a step of
		// exactly 0 and loop forever (xpos += 0 never advances) -- a real, user-reachable UI
		// freeze, not just a cosmetic issue. Repeated zoom-out had the mirror problem: an
		// unbounded-growth width that could overflow to infinity/NaN once exp()'d back from
		// logscale in set_linscale().
		set_minmax(new_minimum, new_maximum);
	}

	double reduce_canvas(in double x, in int num_segments, in int canvas_width) const pure {
		double segment_width  = abs(1.0*canvas_width)/num_segments;
		int segment = cast(int)(x/segment_width);
		if (segment >= num_segments) segment = num_segments-1;
		if (segment < 0) segment = 0;
		return x - segment*segment_width;
	}
	double world2canvas(in double x) const pure {
		return a + b*x;
	}
	double world2canvas_delta(in double dx) const pure {
		return b*dx;
	}
	double canvas2world(in double x) const pure {
		return (x - a)/b;
	}
	double canvas2world_delta(in double dx) const pure {
		return dx/b;
	}
	double pixel_width() const pure {
		return abs(1.0/b);
	}
	double min() const pure {
		return minimum - delta;
	}
	double max() const pure {
		return min + width;
	}
	double width() const pure {
		return (maximum - minimum)*scale;
	}
	void set_minmax(in double mini, in double maxi) {
		minimum = mini;
		maximum = maxi;
		if (maximum-minimum < min_width) {
			double mid = 0.5*(minimum+maximum);
			minimum = mid - 0.5*min_width;
			maximum = mid + 0.5*min_width;
		}
		if (maximum-minimum > max_width) {
			double mid = 0.5*(minimum+maximum);
			minimum = mid - 0.5*max_width;
			maximum = mid + 0.5*max_width;			
		}
	}
	// min is the smallest value larger than 0 that should be within the new [minimum,maximum] interval
	// return true if it was changed (not already in logscale)
	bool set_logscale(double min) {
		if (!logscale) {
			if (minimum <= 0) minimum = min;
			if (maximum <= 0) maximum = minimum+min_width;
			minimum = std.math.log(minimum);
			maximum = std.math.log(maximum);
			logscale = true;
			return true;
		}
		return false;
	}
	bool set_linscale() {
		if (logscale) {
			minimum = std.math.exp(minimum);
			maximum = std.math.exp(maximum);
			// exp() overflows to +infinity once its argument exceeds ~709, reachable if
			// unbounded interactive zoom-out (see scale_finish()) pushed the log-space width
			// out far enough. If BOTH ends overflow together, width becomes
			// infinity-infinity = NaN, which a plain "width > max_width" check can't catch
			// (NaN comparisons are always false in IEEE-754) -- so check isFinite()
			// explicitly and recover around whichever endpoint is actually still sane.
			if (!isFinite(minimum) || !isFinite(maximum) || width > max_width) {
				double anchor = isFinite(minimum) ? minimum : (isFinite(maximum) ? maximum-max_width : min_width);
				minimum = anchor;
				maximum = anchor + max_width;
			}
			logscale = false;
			return true;
		}
		return false;
	}
	double log(in double x, double xmin = 0.0) const pure {
		import std.math;
		if (logscale) return (x>0)?(std.math.log(x)):( (xmin>0.0)?std.math.log(xmin):min);
		return x;
	}
	double exp(in double x) const pure {
		import std.math;
		if (logscale) return std.math.exp(x);
		return x;
	}
}

unittest {
	import std.stdio;

	Transform lt;
	int segment, num_segments, canvas_width;
	bool inverse;
	lt.set_minmax(-1,1);
	assert(lt.reduce_canvas(75,num_segments=2,canvas_width= 100) == 25);
	assert(lt.reduce_canvas(90,num_segments=5,canvas_width= 100) == 10);
	assert(lt.reduce_canvas(10,num_segments=5,canvas_width= 100) == 10);
	assert(lt.reduce_canvas(90,num_segments=5,canvas_width= 100) == 10);


	lt.set_minmax(-1,1);
	int canvas_start, canvas_stop;
	double factor;
	lt.translate_start(canvas_start=0, num_segments=1, canvas_width=100);
	lt.translate_ongoing(canvas_stop=100);
	//writeln(lt.min, " ", lt.max);
	assert(lt.min == -3 && lt.max == -1);
	lt.translate_finish();
	//writeln(lt.min, " ", lt.max);
	assert(lt.min == -3 && lt.max == -1);

	// caling around left edge (= -3 in world coordinates) of canvas must not change lt.min
	lt.scale_start(canvas_start=0, num_segments=1, canvas_width=100, inverse=false);
	lt.scale_ongoing(canvas_stop=10, factor=0.01);
	writeln(lt.min, " ", lt.max);
	assert(lt.min == -3);
	lt.scale_finish();
	//writeln(lt.min, " ", lt.max);
	assert(lt.min == -3);


	lt.set_minmax(-1,1);
	lt.scale_start(canvas_start=100, num_segments=1, canvas_width=100, inverse=false);
	lt.scale_ongoing(canvas_stop=90, factor=0.01);
	lt.scale_finish();
	assert(lt.max == 1);

	lt.set_minmax(-1,1);
	lt.scale_start(canvas_start=100, num_segments=1, canvas_width=100, inverse=true);
	lt.scale_ongoing(canvas_stop=90, factor=0.01);
	lt.scale_finish();
	writeln("lt.min,lt.max = ", lt.min,",",lt.max);
	assert(lt.min == -1);

	lt.set_minmax(-1,1);
	lt.scale_start(canvas_start=0, num_segments=1, canvas_width=100, inverse=true);
	lt.scale_ongoing(canvas_stop=90, factor=0.01);
	lt.scale_finish();
	writeln("lt.min,lt.max = ", lt.min,",",lt.max);
	assert(lt.max == 1);


	lt.set_minmax(-1,1);
	lt.scale_start(canvas_start=50, num_segments=1, canvas_width=100, inverse=false);
	lt.scale_ongoing(canvas_stop=90, factor=0.01);
	lt.scale_finish();
	assert(lt.max+lt.min == 0);


	lt.set_minmax(-1,1);
	lt.update_coefficients(segment=1, num_segments=3,canvas_width=120);
	lt.scale_start(canvas_start=60, num_segments=3, canvas_width=120, inverse=false);
	lt.scale_ongoing(canvas_stop=90, factor=0.01);
	lt.scale_finish();
	assert(lt.max+lt.min == 0);


	lt.set_minmax(-1,1);
	lt.update_coefficients(segment=1, num_segments=3,canvas_width=120, inverse=true);
	lt.scale_start(canvas_start=60, num_segments=3, canvas_width=120, inverse=true);
	lt.scale_ongoing(canvas_stop=90, factor=0.01);
	lt.scale_finish();
	assert(lt.max+lt.min == 0);
	lt.scale_start(canvas_start=20, num_segments=3, canvas_width=120, inverse=false);
	lt.scale_ongoing(canvas_stop=30, factor=0.01);
	lt.scale_finish();
	assert(lt.max+lt.min == 0);
	lt.scale_start(canvas_start=100, num_segments=3, canvas_width=120, inverse=false);
	lt.scale_ongoing(canvas_stop=50, factor=0.01);
	lt.scale_finish();
	assert(lt.max+lt.min == 0);

	lt.set_minmax(2,4);
	lt.set_logscale(0.1);
	lt.set_logscale(0.1);
	lt.set_linscale;
	lt.set_linscale;
	assert(lt.min == 2 && lt.max == 4);

	lt.set_logscale(0.1);
	lt.set_minmax(1,100);
	lt.set_linscale;
	assert(lt.width <= lt.max_width);

	lt.set_minmax(-1e30,1e30);
	assert(lt.max-lt.min <= lt.max_width);

	lt.set_minmax(10,10);
	assert(lt.max-lt.min >= lt.min_width);

	// regression test: repeated interactive zooming (scale_one_step(), as used by
	// mouse-wheel zoom in graphics.d's scroll()) must never collapse the width to 0 (which
	// used to make vertical_grid()/horizontal_grid()'s tick-spacing loop spin forever,
	// since xpos += 0 never advances) or let it grow without bound (which used to let
	// set_linscale() overflow via exp() once switching back from logscale).
	lt.set_minmax(-1,1);
	foreach (i; 0..5000) lt.scale_one_step(50, 1, 100, -50, 0.01, false);
	assert(lt.max - lt.min >= lt.min_width);
	assert(lt.max - lt.min <= lt.max_width);
	assert(std.math.isFinite(lt.min) && std.math.isFinite(lt.max));

	lt.set_minmax(-1,1);
	foreach (i; 0..5000) lt.scale_one_step(50, 1, 100, 50, 0.01, false);
	assert(lt.max - lt.min >= lt.min_width);
	assert(lt.max - lt.min <= lt.max_width);
	assert(std.math.isFinite(lt.min) && std.math.isFinite(lt.max));

	// regression test: set_linscale() must not leave min/max as infinity/NaN even if the
	// log-space width was pushed out far enough for exp() to overflow.
	lt.set_minmax(1,2);
	lt.logscale  = true;
	lt.minimum   = 800; lt.maximum = 900; // exp(900) overflows to +infinity
	lt.set_linscale();
	assert(std.math.isFinite(lt.min) && std.math.isFinite(lt.max));
	assert(lt.max - lt.min <= lt.max_width);

	lt.set_minmax(1,2);
	lt.logscale  = true;
	lt.minimum   = -900; lt.maximum = 900; // exp(-900)->0, exp(900)->+infinity
	lt.set_linscale();
	assert(std.math.isFinite(lt.min) && std.math.isFinite(lt.max));
	assert(lt.max - lt.min <= lt.max_width);

	lt.set_minmax(-10,10);
	lt.update_coefficients(segment=0,num_segments=2,canvas_width=40);
	assert(lt.world2canvas(0)==10);
	assert(lt.canvas2world(10)==0);
	assert(lt.world2canvas(10)==20);
	assert(lt.canvas2world(20)==10);
	assert(lt.world2canvas_delta(1)==1);
	assert(lt.canvas2world_delta(1)==1);
	assert(lt.pixel_width==1);
	lt.update_coefficients(segment=1,num_segments=2,canvas_width=40);
	assert(lt.world2canvas(0)==30);
	assert(lt.world2canvas(10)==40);

	JSONValue json = serialize(lt);
	json.toString.writeln;
	auto lt2 = deserialize!Transform(json);
}