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

module xydata;
@safe:

import item;
import std.json;
import serializeJSON;

// one data row: error is double.init if the file didn't give one for this point
struct XYPoint {
	double x, y, error = double.init;
}

// Reads a CSV file of "x,y" or "x,y,error" rows (error column optional, and may be present
// on some rows and absent on others). Blank lines and lines starting with "#" are skipped.
// If the first non-blank, non-comment line doesn't parse as numbers, it is treated as a
// header (used for axis labels) rather than data.
struct XYData {
	XYPoint[] points;
	string xlabel;
	string ylabel;
}
XYData read_csv(string filename) {
	import std.file, std.string, std.conv, std.array;

	XYPoint[] points;
	string xlabel, ylabel;
	bool header_checked = false;

	foreach(line; readText(filename).splitLines) {
		string trimmed = line.strip;
		if (trimmed.length == 0) continue;
		if (trimmed.startsWith("#")) continue;

		auto fields = trimmed.split(",");
		if (fields.length < 2) continue;

		double x, y, error = double.init;
		bool ok = true;
		try {
			x = fields[0].strip.to!double;
			y = fields[1].strip.to!double;
			if (fields.length >= 3 && fields[2].strip.length > 0) {
				error = fields[2].strip.to!double;
			}
		} catch (Exception e) {
			ok = false;
		}

		if (!ok) {
			// not parseable as numbers -- treat the very first such line as a header
			// giving axis labels, anything after that is just skipped (malformed data)
			if (!header_checked && points.length == 0) {
				xlabel = fields[0].strip;
				ylabel = fields[1].strip;
			}
			header_checked = true;
			continue;
		}
		header_checked = true;
		points ~= XYPoint(x, y, error);
	}
	return XYData(points, xlabel, ylabel);
}

class FileXYDataFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		return new FileXYData(json);
	}
}

import graphics, functions;
class FileXYData : Visual, FitDataSource, Item {
	struct Data {
		@SERIALIZE string filename;
	}
	Data data;
	string xlabel = "";
	string ylabel = "";
	this(Data d)             { data = d; }
	this(ref JSONValue json) { data = deserialize!Data(json); }

	// Item interface
	override JSONValue toJSON() { return serialize(data); }
	override string get_type()  { return "xydata.FileXYData"; }
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

	// Visual interface
	override Visualizer create_visualizer(BackendInterface backend, Visualizer old = null) {
		try {
			auto csv = read_csv(data.filename);
			xlabel = csv.xlabel;
			ylabel = csv.ylabel;
			return new XYDataVisualizer(item_version, csv.points, csv.xlabel, csv.ylabel);
		} catch (Exception e) {
			import std.stdio;
			writeln("cannot read file: ", data.filename, ": ", e.msg);
			return null;
		}
	}

	// FitDataSource interface
	override double get_bin_width() {
		auto points = read_csv(data.filename).points;
		if (points.length < 2) return 0;
		return (points[$-1].x - points[0].x) / (points.length - 1);
	}
	override double[3][] get_data(double[2] region) {
		double left = region[0];
		double right = region[1];
		auto points = read_csv(data.filename).points;
		double[3][] result;
		foreach(p; points) {
			if (p.x >= left && p.x < right) {
				result ~= [p.x, p.y, (p.error !is double.init && p.error > 0) ? p.error : 1.0];
			}
		}
		return result;
	}

private:
	import std.datetime : SysTime;
	import std.file : timeLastModified;

	ulong item_version = 0;
	SysTime _time_of_last_update;

	bool need_to_reload() {
		bool need_update = false;
		SysTime time_last_file_modification = timeLastModified(data.filename);
		SysTime time_of_last_update = _time_of_last_update;
		if (time_of_last_update == SysTime.init) need_update = true;
		if (time_of_last_update < time_last_file_modification) need_update = true;
		_time_of_last_update = time_last_file_modification;

		if (need_update) ++item_version;
		return need_update;
	}
}

import transform;
class XYDataVisualizer : Visualizer {
public:
	this(ulong itemversion, immutable(XYPoint[]) points, string xlabel, string ylabel) {
		super(itemversion, 1);
		_points = points;
		_xlabel = xlabel;
		_ylabel = ylabel;
		foreach(p; _points) {
			if (_xmin is double.init || p.x < _xmin) _xmin = p.x;
			if (_xmax is double.init || p.x > _xmax) _xmax = p.x;
			double has_error = (p.error !is double.init && p.error > 0);
			double ylo = has_error ? p.y-p.error : p.y;
			double yhi = has_error ? p.y+p.error : p.y;
			if (_ymin is double.init || ylo < _ymin) _ymin = ylo;
			if (_ymax is double.init || yhi > _ymax) _ymax = yhi;
		}
	}
	this(ulong itemversion, XYPoint[] points, string xlabel, string ylabel) {
		this(itemversion, points.idup, xlabel, ylabel);
	}

	override string getXlabel() { return _xlabel; }
	override string getYlabel() { return _ylabel; }

	override bool get_leftright(out double[2] lr, in Transform[3] t, bool zoom = false) {
		if (_xmin is double.init || _xmax is double.init) return false;
		if (t[0].logscale && _xmin <= 0 && _xmax <= 0) return false;
		if (_xmin == _xmax) return false;
		lr[0] = t[0].log(_xmin);
		lr[1] = t[0].log(_xmax);
		return true;
	}

	override bool get_bottomtop_in_leftright(out double[2] bt, in double[2] lr, in Transform[3] t, bool zoom = false) {
		double left = lr[0];
		double right = lr[1];
		if (t[0].logscale) {
			import std.math;
			left = exp(left);
			right = exp(right);
		}
		double ymin = double.init, ymax = double.init;
		foreach(p; _points) {
			if (p.x < left || p.x > right) continue;
			bool has_error = (p.error !is double.init && p.error > 0);
			double ylo = has_error ? p.y-p.error : p.y;
			double yhi = has_error ? p.y+p.error : p.y;
			if (ymin is double.init || ylo < ymin) ymin = ylo;
			if (ymax is double.init || yhi > ymax) ymax = yhi;
		}
		if (ymin is double.init || ymax is double.init) return false;
		if (t[1].logscale && ymax <= 0) return false;
		if (ymin == ymax) return false;
		bt[0] = t[1].log(ymin, ymax/1000.0);
		bt[1] = t[1].log(ymax);
		return true;
	}

	override double getValue(double x, double y) {
		return double.init; // no meaningful single "value at cursor" for scatter data
	}

	@trusted override void draw(BackendInterface d, in Transform[3] t, bool modified) const {
		if (_points is null) return;
		enum double SIZE = 4; // pixel width/height of each point's marker box, regardless of zoom
		d.set_color(0.1, 0.1, 0.6);
		d.set_line_width(2);
		foreach(p; _points) {
			double cx = t[0].world2canvas(t[0].log(p.x));
			double cy = t[1].world2canvas(t[1].log(p.y));
			if (cx is double.init || cy is double.init) continue;
			if (p.error !is double.init && p.error > 0) {
				double c_lo = t[1].world2canvas(t[1].log(p.y - p.error));
				double c_hi = t[1].world2canvas(t[1].log(p.y + p.error));
				if (c_lo !is double.init && c_hi !is double.init) {
					d.vertical_line(cx, c_lo, c_hi);
					d.stroke();
				}
			}
			d.rectangle(cx-SIZE/2, cy-SIZE/2, cx+SIZE/2, cy+SIZE/2);
			d.fill();
		}
	}

private:
	immutable(XYPoint[]) _points;
	string _xlabel, _ylabel;
	double _xmin = double.init, _xmax = double.init;
	double _ymin = double.init, _ymax = double.init;
}
