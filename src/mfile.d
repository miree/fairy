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

module mfile;
@safe:

// Reader for the "LC" (line compressed) matrix file format used by libmfile
// (https://gitlab.ikp.uni-koeln.de/jmayer/libmfile), a small, old, no-longer-actively-developed
// C library for nuclear spectroscopy data. Rather than depending on (or vendoring) the whole
// library -- which also covers ~20 other, mostly legacy, matrix formats fairy has no use for --
// this is a from-scratch port of just the LC decoder, reverse-engineered directly from
// libmfile's lc_minfo.c/lc_getput.c/lc_c1.c/lc_c2.c and cross-checked byte-for-byte against
// files written by the real C library (both sub-versions, 1D and 2D, including zero-run and
// repeated-value edge cases).
//
// On-disk layout: a 44-byte header (11 little-endian uint32 fields: magic, version, levels,
// lines, columns, poslentablepos, freepos, freelistpos, used, free, status), followed at
// poslentablepos by one {pos:uint32, len:uint32} entry per row (levels*lines of them, row =
// level*lines+line) pointing to that row's compressed bytes ( len==0 means "all zero, nothing
// stored"). Each row's `columns` int32 values are encoded as a short byte stream: zigzag-delta
// against the previous value, with small deltas packed 2 or 3 to a byte, and (version 2 only)
// runs of repeated values collapsed via a count. Versions 1 and 2 use slightly different byte
// layouts for this (lc1_uncompress/lc2_uncompress below); both are supported since real files
// use either. levels>1 ("cubes") are rejected -- fairy has no 3D visualizer.

import std.exception;

private uint readLE32(const(ubyte)[] b) {
	return cast(uint)b[0] | (cast(uint)b[1]<<8) | (cast(uint)b[2]<<16) | (cast(uint)b[3]<<24);
}

private uint bitextract(uint v, uint pos, uint len) {
	return (v >> pos) & ((1u<<len)-1);
}

private enum uint MAGIC_LC = 0x80FFFF10;
private enum size_t LC_HEADER_SIZE = 44;

private struct LCHeader {
	uint magic, version_, levels, lines, columns;
	uint poslentablepos, freepos, freelistpos, used, free_, status;
}

private LCHeader parseHeader(const(ubyte)[] data) {
	enforce(data.length >= LC_HEADER_SIZE, "mfile: file too small to be an LC matrix file");
	LCHeader h;
	h.magic          = readLE32(data[0..4]);
	h.version_       = readLE32(data[4..8]);
	h.levels         = readLE32(data[8..12]);
	h.lines          = readLE32(data[12..16]);
	h.columns        = readLE32(data[16..20]);
	h.poslentablepos = readLE32(data[20..24]);
	h.freepos        = readLE32(data[24..28]);
	h.freelistpos    = readLE32(data[28..32]);
	h.used           = readLE32(data[32..36]);
	h.free_          = readLE32(data[36..40]);
	h.status         = readLE32(data[40..44]);
	enforce(h.magic == MAGIC_LC, "mfile: not an LC matrix file (bad magic)");
	return h;
}

// version 1 row decoder, ported from lc_c1.c's lc1_uncompress(). Every decoded value updates
// the running delta-reference ("last"), unlike version 2 below.
private int[] lc1_uncompress(const(ubyte)[] src, uint num) {
	auto dest = new int[num];
	int last = 0;
	uint nleft = num;
	size_t si = 0, di = 0;
	int decode(uint i) {
		last += (i & 1) ? ~(cast(int)(i >> 1)) : cast(int)(i >> 1);
		return last;
	}
	while (nleft) {
		enforce(si < src.length, "mfile: lc1 stream truncated");
		ubyte t = src[si++];
		switch (t >> 6) {
			case 0: // 3 values packed 2 bits each
				enforce(nleft >= 3, "mfile: lc1 stream corrupt (3x2)");
				nleft -= 3;
				dest[di++] = decode(bitextract(t,0,2));
				dest[di++] = decode(bitextract(t,2,2));
				dest[di++] = decode(bitextract(t,4,2));
				break;
			case 1: // 2 values packed 3 bits each
				enforce(nleft >= 2, "mfile: lc1 stream corrupt (2x3)");
				nleft -= 2;
				dest[di++] = decode(bitextract(t,0,3));
				dest[di++] = decode(bitextract(t,3,3));
				break;
			case 2: // 1 value, 6 bits
				nleft -= 1;
				dest[di++] = decode(bitextract(t,0,6));
				break;
			default: // 1 value, 6 bits + 7-bit continuation bytes while the high bit is set
				nleft -= 1;
				uint i = bitextract(t,0,6);
				uint s = 6;
				ubyte tt;
				do {
					enforce(si < src.length, "mfile: lc1 stream truncated (escaped value)");
					tt = src[si++];
					i += (bitextract(tt,0,7) << s);
					s += 7;
				} while (tt & 0x80);
				dest[di++] = decode(i);
				break;
		}
	}
	enforce(di == num, "mfile: lc1 stream decoded to the wrong number of values");
	return dest;
}

// version 2 row decoder, ported from lc_c2.c's lc2_uncompress(). Unlike version 1, only the
// *last* value of a packed group (or an escaped single value) updates "last" -- earlier values
// in a 2x3/3x2 group are deltas against the same, unupdated "last". Also adds a run-length tag
// for repeated values, which is why version 2 is libmfile's recommended default.
private int[] lc2_uncompress(const(ubyte)[] src, uint num) {
	auto dest = new int[num];
	int last = 0;
	int nleft = cast(int)num;
	size_t si = 0, di = 0;
	int decode(uint i) {
		return (i & 1) ? ~(cast(int)(i >> 1)) : cast(int)(i >> 1);
	}
	while (nleft > 0) {
		enforce(si < src.length, "mfile: lc2 stream truncated");
		ubyte t = src[si++];
		if (t & 0x80) {
			uint n = t & 0x3f;
			if (n > 59) {
				uint extrabytes = n - 59;
				n = 59;
				foreach (i; 0 .. extrabytes) {
					enforce(si < src.length, "mfile: lc2 stream truncated (escaped tag)");
					ubyte b = src[si++];
					n += (cast(uint)b + 1) << (i << 3);
				}
			}
			if (t & 0x40) { // a changed value followed by a run of repeats of the previous "last"
				int diff = cast(int)bitextract(n,0,1);
				uint same = (n >> 1) + 3;
				dest[di++] = last + diff;
				nleft -= cast(int)same;
				enforce(nleft > 0, "mfile: lc2 stream corrupt (repeat run)");
				foreach (k; 0 .. same) dest[di++] = last;
			} else { // one escaped delta-encoded value
				last += decode(n);
				dest[di++] = last;
			}
			nleft -= 1;
		} else if (t & 0x40) { // 2 values packed 3 bits each
			nleft -= 2;
			enforce(nleft >= 0, "mfile: lc2 stream corrupt (2x3)");
			dest[di++] = last + decode(bitextract(t,0,3));
			last += decode(bitextract(t,3,3));
			dest[di++] = last;
		} else { // 3 values packed 2 bits each
			nleft -= 3;
			enforce(nleft >= 0, "mfile: lc2 stream corrupt (3x2)");
			dest[di++] = last + decode(bitextract(t,0,2));
			dest[di++] = last + decode(bitextract(t,2,2));
			last += decode(bitextract(t,4,2));
			dest[di++] = last;
		}
	}
	enforce(di == num, "mfile: lc2 stream decoded to the wrong number of values");
	return dest;
}

// reads one row (levels*lines of these exist, row = level*lines+line), each `columns` values long
private int[] read_row(const(ubyte)[] data, LCHeader h, uint row) {
	size_t entryPos = h.poslentablepos + row * 8UL;
	enforce(entryPos + 8 <= data.length, "mfile: position/length table entry out of bounds");
	uint pos = readLE32(data[entryPos .. entryPos+4]);
	uint len = readLE32(data[entryPos+4 .. entryPos+8]);
	if (len == 0) return new int[h.columns]; // an all-zero row is stored as nothing at all
	enforce(cast(ulong)pos + len <= data.length, "mfile: row data out of bounds");
	auto rowbytes = data[pos .. pos+len];
	if (h.version_ == 1) return lc1_uncompress(rowbytes, h.columns);
	if (h.version_ == 2) return lc2_uncompress(rowbytes, h.columns);
	import std.conv : to;
	throw new Exception("mfile: unsupported LC sub-version " ~ h.version_.to!string);
}

// Mirrors histogram.HistData/histogram.read_file()'s result shape so FileMfileLC (see below) can
// feed it straight into Hist1Visualizer/Hist2Visualizer exactly like histogram.FileHistogram
// does. mfile carries no axis calibration (no left/right/bottom/top, no axis labels) -- bins are
// just plain channel numbers, left=0/right=columns (and bottom=0/top=lines for 2D).
import histogram : HistData;

@trusted ubyte[] readBinaryFile(string filename) {
	import std.file : read;
	return cast(ubyte[]) read(filename);
}

HistData read_file(string filename) {
	auto data = readBinaryFile(filename);
	auto h = parseHeader(data);
	enforce(h.columns > 0, "mfile: zero-column matrix");
	enforce(h.lines > 0 && h.levels > 0, "mfile: zero-line or zero-level matrix");
	enforce(h.levels == 1, "mfile: 3D matrices (\"cubes\", levels > 1) are not supported -- fairy has no 3D visualizer");

	if (h.lines == 1) {
		auto row = read_row(data, h, 0);
		double[] bins = new double[h.columns];
		foreach (i, v; row) bins[i] = v;
		return HistData(bins, 1, "", 0, h.columns);
	}

	double[] bins = new double[h.lines * h.columns];
	foreach (line; 0 .. h.lines) {
		auto row = read_row(data, h, line);
		foreach (col, v; row) bins[line*h.columns + col] = v;
	}
	return HistData(bins, 2, "", 0, h.columns, "", 0, h.lines, h.columns, h.lines);
}


import item;
import std.json;
import serializeJSON;

class FileMfileLCFactory : ItemFactory {
	override Item create(ref JSONValue json) {
		return new FileMfileLC(json);
	}
}

import graphics, functions, histogram;
class FileMfileLC : Visual, Hist2ProjectionSource, FitDataSource, Item, HasProperties {
	struct Data {
		@SERIALIZE @EDITABLE string filename;
	}
	Data data;
	string xlabel = "";
	string ylabel = "";
	this(Data d)             { data = d; }
	this(ref JSONValue json) { data = deserialize!Data(json); }
	override void visitEditableFields(FieldVisitor v) { item.visitEditableFields(data, v); }

	// Item interface
	override JSONValue toJSON() { return serialize(data); }
	override string get_type()  { return "mfile.FileMfileLC"; }
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
			HistData hist_data = read_file(data.filename);
			dim = hist_data.dim;
			switch (hist_data.dim) {
				case 1:
					xlabel = hist_data.xlabel;
					return new Hist1Visualizer(old, item_version, hist_data.data, hist_data.xlabel, hist_data.left, hist_data.right);
				case 2:
					xlabel = hist_data.xlabel;
					ylabel = hist_data.ylabel;
					return new Hist2Visualizer(old, item_version, backend, hist_data.data,
											   hist_data.bins_x, hist_data.bins_y,
											   hist_data.left, hist_data.right, hist_data.bottom, hist_data.top,
											   hist_data.xlabel, hist_data.ylabel);
				default: return null;
			}
		} catch (Exception e) {
			import std.stdio;
			writeln("cannot read file: ", data.filename, ": ", e.msg);
			return null;
		}
	}

	// FitDataSource interface
	override double get_bin_width() {
		return bin_width;
	}
	override double[3][] get_data(double[2] region) {
		double left = region[0];
		double right = region[1];
		HistData hist_data = read_file(data.filename);
		bin_width = (hist_data.right-hist_data.left)/hist_data.data.length;
		dim = hist_data.dim;
		double[3][] result;
		if (hist_data.dim == 1) {
			foreach(idx, y; hist_data.data) {
				double x = hist_data.left+idx*(hist_data.right-hist_data.left)/hist_data.data.length;
				x += bin_width/2;
				if (x >= left && x < right) {
					import std.math;
					double[3] dp = [x, (y is double.init)?0:y, y>1?sqrt(y):1];
					result ~= dp;
				}
			}
		} else {
			throw new Exception("fit for 2D-histograms not implemented yet");
		}
		return result;
	}

	// Hist2ProjectionSource interface
	bool projection_data_ready() { return dim == 2; }
	Hist2ProjectionSource.Data get_projection_data() {
		HistData hist_data = read_file(data.filename);
		if (hist_data.dim == 2) {
			return Hist2ProjectionSource.Data(hist_data.data, hist_data.bins_x, hist_data.bins_y,
				                              hist_data.left, hist_data.right, hist_data.bottom, hist_data.top);
		}
		throw new Exception("Projection for 1D-histograms not implemented");
	}
	string getXlabel() { return xlabel; }
	string getYlabel() { return ylabel; }

private:
	import std.datetime : SysTime;
	import std.file : timeLastModified;

	ulong item_version = 0;
	SysTime _time_of_last_update;

	double bin_width;
	ulong dim;

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
