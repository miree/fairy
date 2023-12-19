module audiodaq;
@safe:

import waveform;
Waveform[] traces;

import std.concurrency;
Tid main_thread;

bool running = false;
bool paused  = false;
Tid  tid;

struct MsgPause {}
struct MsgContinue {}
struct MsgStop {}
struct MsgAck {}
struct MsgWaveformCreate{
	string   name;
	shared(Waveform.Data) wave;
}
struct MsgError {}

@trusted
static ~this() {
	if (running) {
		tid.send(MsgStop());
		receive((MsgAck msg) {});
	}
}

interface Filter {
	void put(double x);
	bool empty(); // returns true if there is a new value available on the output
	uint N(); // return the lenght of the array that will be returned by get();
	bool trigger(double level, int slope, out double dx); // slope = 1 trigger on rising edge
	                                                      // slope = -1 triggers on falling edge
	                                                      // slope = 0 triggers on either edge
	double[] get(); // only call if empty() is false
}

class NoFilter : Filter {
	double[1] value;
	double[1] previous;
	override void put(double x) {
		if (value[0] == double.init) previous[0] = x;
		else                         previous[0] = value[0];
		value[0] = x;
	}
	override bool empty() {
		return false;
	}
	override uint N() {
		return 1;
	}
	override bool trigger(double level, int slope, out double dx) {
		dx = 0;
		if (slope >= 0 && previous[0] < level && value[0] >= level) return true;
		if (slope <= 0 && previous[0] > level && value[0] <= level) return true;
		return false;
	}
	override double[] get() {
		return value;
	}
}

class LinearInterpolation : Filter {
	double previous;
	double[2] output;
	override void put(double x) {
		if (previous !is double.init) {
			output[0] = previous;
			output[1] = x-previous;
		}
		previous = x;
	}
	override bool empty() {
		return (previous is double.init);
	}
	override uint N() {
		return 2;
	}
	override bool trigger(double level, int slope, out double dx) {
		double y0 = output[0];
		double y1 = output[0]+output[1];
		if (slope >= 0 && y0 < level && y1 >= level) {
			dx = 1.0-(level-y0)/(y1-y0);
			return true;
		}
		if (slope <= 0 && y0 > level && y1 <= level) {
			dx = -(y0-level)/(y0-y1);
			return true;
		}
		return false;
	}
	override double[] get() {
		return output;
	}
}

class SincInterpolation : Filter {
	// sample height and first derivative
	struct Sample {
		double y;
		double yd = 0.0;
	}
	double[4] coefficients;
	void calc_coefficients(in Sample s0, in Sample s1) {
		coefficients[0] = s0.y;
		coefficients[1] = s0.yd;
		coefficients[2] = -1*s1.yd + 3*s1.y - 2*s0.yd - 3*s0.y;
		coefficients[3] =    s1.yd - 2*s1.y + 1*s0.yd + 2*s0.y;
	}
	double eval(double x) {
		assert(x >= 0);
		assert(x <= 1);
		double a = coefficients[0];
		double b = coefficients[1];
		double c = coefficients[2];
		double d = coefficients[3];
		return a+(b+(c+d*x)*x)*x;
	}

	import std.math, std.range;
	// table of derivatives of sinc function
	// optimized in a way such that polynom interpolation reproduces the sinc function more precisely
	static immutable double[] dsinc_dx = [0.0, -1.07432, 0.587811, -0.402117, 0.303929, -0.244447, 0.204067, -0.175336, 0.153231, -0.130252, 0.106675, -0.0831741, 0.060211, -0.0384085, 0.0180193, 9.70157e-05];

	Sample[dsinc_dx.length] samples; // ringbuffer of samples
	ulong front_idx;                 // index into ringbuffer pointing to the front element of the range
	bool is_empty = true;
	Sample front_sample;
	Sample previous_sample;

	override void put(double y) {
		if (is_empty) {
			samples[] = Sample(y);
			front_sample = samples[front_idx];
			is_empty = false;
		} 
		previous_sample = front_sample;
		front_sample = samples[front_idx];
		samples[front_idx] = Sample(y);
		ulong end   = front_idx;
		ulong begin = end+1;
		if (begin >= samples.length) begin = 0;

		long xi = samples.length-1;
		for(ulong i = begin; i != end; i = (i+1)%samples.length) {
			samples[i].yd         -= dsinc_dx[xi] * samples[front_idx].y;
			samples[front_idx].yd += dsinc_dx[xi] * samples[i].y;
			--xi;
		}
		front_idx = begin;
		calc_coefficients(previous_sample, front_sample);
	}
	bool empty() { return is_empty; }
	uint N() {return 4;}
	override bool trigger(double level, int slope, out double dx) {
		import std.math, std.stdio;
		double pa = coefficients[0];
		double pb = coefficients[1];
		double pc = coefficients[2];
		double pd = coefficients[3];
		double[4] buffer = [0.0,1.0,1.0,1.0]; // create the array on the stack
		double[] extrema = buffer[0..2];
		double k = pc*pc - 3*pb*pd;
		if (k >= 0) { // Fill extrema-array with the sorted extrema of the polynom in the [0,1] interval. 
			          // At most 4, at least 2.
			double sk = sqrt(k);
			double x1 = -(sk + pc) / (3*pd);
			double x2 =  (sk - pc) / (3*pd);
			if (x1 > 0.0 && x1 < 1.0) {
				extrema = buffer[0..extrema.length+1];
				extrema[$-2] = x1;
				//assert(extrema[$-3]<=extrema[$-2]);
				//assert(extrema[$-2]<=extrema[$-1]);
			}
			if (x2 > 0.0 && x2 < 1.0) {
				extrema = buffer[0..extrema.length+1];
				extrema[$-2] = x2;
				if (extrema[$-3] > extrema[$-2]) {
					extrema[$-2] = extrema[$-3];
					extrema[$-3] = x2;
				}
				//assert(extrema[0]  <= extrema[1]);
				//assert(extrema[1]  <= extrema[2]);
				//assert(extrema[$-3]<=extrema[$-2]);
				//assert(extrema[$-2]<=extrema[$-1]);
			}
		}
		//writeln(extrema);

		const double epsilon = 1e-3;
		double result;
		for (int i = 0; i < extrema.length-1; ++i ) {
			double x0 = extrema[i];
			double x1 = extrema[i+1];
			//writeln("interval ", x0, " ", x1);
			double y0 = eval(x0);
			double y1 = eval(x1);
			if (slope >= 0 && y0 <= level && y1 >= level) { // we have a trigger condition here ... look for exact intersection
				int steps = 0;
				while (y1-y0 > epsilon) {
					++steps;
					double xmid = 0.5*(x0+x1);
					double ymid = eval(xmid);
					if (level <= ymid) { 
						x1 = xmid;
						y1 = ymid;
					} else {
						x0 = xmid;
						y0 = ymid;
					}
				}
				result = 0.5*(x0+x1);
				dx = 1.0-result;
				//import std.stdio; stderr.writeln("result: ", result, " steps: ", steps);
				return true;
			}
			if (slope <= 0 && y0 >= level && y1 <= level) { // tigger condition... look for exact intersection
				int steps = 0;
				while (y0-y1 > epsilon) {
					++steps;
					double xmid = 0.5*(x0+x1);
					double ymid = eval(xmid);
					if (level <= ymid) {
						x0 = xmid;
						y0 = ymid;
					} else {
						x1 = xmid;
						y1 = ymid;
					}
				}
				result = 0.5*(x0+x1);
				dx = 1.0-result;
				//import std.stdio; stderr.writeln("result: ", result , " steps: ", steps);
				return true;
			}
		}

		dx = 1.0-result;
		return result !is double.init;
	}
	double[] get() { return coefficients; }
}

interface AudioDAQ {
	uint[] get_allowed_rates();
	uint[] get_allowed_channels();
}

enum InterpolationMode {
	no,
	linear,
	sinc
}

version(Windows) {

}
else {

	pragma(lib, "asound");



	@trusted
	void run_audiodaq(Tid main_thread_tid, int trace_length, int num_channels, int samplingrate, int trigger_level, int trigger_slope, double trigger_position, InterpolationMode interpolation, string device_name) {
		if (trigger_slope > 1 || trigger_slope < -1) throw new Exception("audiodaq trigger_slope must be -1, 0, or 1");
		if (trigger_position < 0.0 || trigger_position > 1.0) throw new Exception("audiodaq trigger_position must be >= 0 and <= 1");

		import std.datetime;
		main_thread = main_thread_tid;
		bool paused = false;
		bool stop = false;
		// create fairy Wavforms and send them over to main thread
		import std.stdio;
		//writeln("run_audiodaq ", num_channels);
		traces.length = num_channels;

		auto filters = new Filter[num_channels];
		foreach(ref filter; filters) {
			if (interpolation == InterpolationMode.no) {
				filter = new NoFilter;
			} else if (interpolation == InterpolationMode.linear) {
				filter = new LinearInterpolation;
			} else if (interpolation == InterpolationMode.sinc) {
				filter = new SincInterpolation;
			} else {
				throw new Exception("invalid interpolation filter");
			}
		}

		foreach(channel; 0..num_channels) {
			import std.conv;
			string tracename = "audiodaq/"~channel.to!string;
			auto itemversion = new shared(ulong[])(1);
			itemversion[0] = 0;
			int pretrigger_tracelength= cast(int)(trace_length*trigger_position);
			traces[channel] = new Waveform(new shared(double[])(trace_length*filters[channel].N), filters[channel].N, -pretrigger_tracelength, trace_length-pretrigger_tracelength);
			//writeln("send waveform item ", traces[channel].get_type());
			main_thread.send(MsgWaveformCreate(tracename, traces[channel].d));
			receive((MsgAck msg) {});
			//writeln("got ack for waveform");
		}
		try {
			auto pcm = AlsaPcmRecord(num_channels, samplingrate, device_name);

			enum t_state { ready, triggered, wait }
			t_state state = t_state.wait;
			//bool triggered = false;
			//bool disarmed = false;
			uint trace_end = trace_length*2;
			uint pre_trigger_data = cast(uint)(trace_length*(1.0-trigger_position))+1;
			uint pre_trigger_count = 0;
			double trigger_dx;
			import std.stdio;
			// main loop take data samples and send trace to main thread when trigger is detected
			for (int i=0; ;) {
				if (!paused) {
					pcm.popFront; // keep taking samples from hardware
					foreach(ch;0..num_channels) {
						filters[ch].put(pcm.front[ch]);
					}
					final switch(state) {
						case t_state.wait: {
							//writeln("wait... check");
							bool all_channels_ready = true;
							foreach(ch;0..num_channels) {
								if (traces[ch].d.data_start_idx[0] != -1) all_channels_ready = false;
							}
							if (all_channels_ready) {
								//writeln("wait -> ready");
								state = t_state.ready;
								pre_trigger_count = 0;
							}
						}
						break;
						case t_state.ready:
							//writeln("ready");
							foreach(ch;0..num_channels) {
								if (!filters[ch].empty) {
									//writeln("ready writing data i=",i);
									traces[ch].d.data[filters[ch].N*i..filters[ch].N*(i+1)] = filters[ch].get[0..filters[ch].N];
								}
							}
							if (++i >= trace_length) i = 0; // increment sample index 
							if (pre_trigger_count < pre_trigger_data) {
								++pre_trigger_count;
							} else if (filters[0].trigger(trigger_level, trigger_slope, trigger_dx)) { // test only for trigger if enough pre trigger data are recorded
								trace_end = i + cast(int)(trace_length*(1.0-trigger_position));
								if (trace_end >= trace_length) trace_end -= trace_length;
								//writeln("ready -> triggered at i=",i, " trace_end=",trace_end);
								state = t_state.triggered;
							}
						break;
						case t_state.triggered:
							//writeln("triggered");
							foreach(ch;0..num_channels) {
								if (!filters[ch].empty) {
									//writeln("triggered writing data i=",i, " trace_end=",trace_end);
									traces[ch].d.data[filters[ch].N*i..filters[ch].N*(i+1)] = filters[ch].get[0..filters[ch].N];
								}
							}
							if (++i >= trace_length) i = 0; // increment sample index 
							if (i == trace_end) {
								foreach(ch;0..num_channels) {
									traces[ch].d.dx[0] = trigger_dx;
									traces[ch].d.data_start_idx[0] = trace_end;
								}
								foreach(ch;0..num_channels) {
									traces[ch].overrideVersion(traces[ch].getVersion+1);
								}
								//writeln("triggered -> wait");
								state = t_state.wait;
							}							
						break;
					}
				}
				receiveTimeout(paused?100.msecs:Duration.zero,
					(MsgPause    msg) { paused = true;  main_thread.send(MsgAck()); },
					(MsgContinue msg) { paused = false; main_thread.send(MsgAck()); },
					(MsgStop     msg) { stop   = true;  main_thread.send(MsgAck()); });
				if (stop) break;
			}
			import std.stdio;
			//writeln("run_audiodaq returns");

		} catch (Exception e) {
			writeln("error running audiodaq: ", e.msg);
			main_thread.send(MsgError());
			stop = true;
			paused = false;
			running = false;
		}
	}

	import alsa_import;

	//@trusted
	//class Alsa : AudioDAQ {

	//	snd_pcm_t* handle;
	//	snd_pcm_hw_params_t *params;

	//	this(string devname) {
	//		import std.string;
	//		assert(snd_pcm_open(&handle, devname.toStringz, SND_PCM_STREAM_CAPTURE, 0) >= 0);
	//		assert(snd_pcm_hw_params_malloc(&params) >= 0); 

	//	}
	//	~this() {
	//		import std.stdio;
	//		snd_pcm_hw_free(handle);
	//		snd_pcm_close(handle);
	//		snd_pcm_hw_params_free(params);
	//	}


	//	override uint[] get_allowed_rates() {
	//		snd_pcm_hw_params_any(handle, params);
	//		assert(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0);
	//		assert(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED) == 0);
	//		assert(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S32_LE) == 0);

	//		uint[] result;
	//		uint fmin = 0;
	//		uint fmax = 10000000;
	//		int dirmin=0;
	//		int dirmax=0;
	//		assert(snd_pcm_hw_params_set_rate_minmax(handle, params, &fmin, &dirmin, &fmax, &dirmax) == 0);
	//		foreach(f; [44100,48000,96000,192000,352000]) {
	//			if (f<= fmax && f >= fmin) {
	//				result ~= f;
	//			}
	//		}
	//		return result;
	//	}

	//	override uint[] get_allowed_channels() {
	//		uint[] result = []; 
	//		snd_pcm_hw_params_any(handle, params);
	//		assert(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0);
	//		assert(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED) == 0);
	//		assert(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S32_LE) == 0);
	//		uint fmin = 0;
	//		uint fmax = 10000000;
	//		int dirmin=0;
	//		int dirmax=0;
	//		assert(snd_pcm_hw_params_set_rate_minmax(handle, params, &fmin, &dirmin, &fmax, &dirmax) == 0);
	//		foreach(ch; 1..3) {
	//			if (snd_pcm_hw_params_test_channels(handle, params, ch) == 0) {
	//				result ~= ch;
	//			}
	//		}
	//		return result;
	//	}


	//}


	@trusted
	struct AlsaPcmRecord {
		//import alsa.pcm;
		import alsa_import;
		import std.stdio;
		snd_pcm_t *handle; // a handle to pcm device
		snd_pcm_hw_params_t *params;
		uint channels;
		ulong period_size;
		short[] buffer;
		ulong idx;

		this(uint ch, uint rate, string device_name) {
			channels = ch;
			import std.string;
			if (!(snd_pcm_open(&handle, device_name.toStringz, SND_PCM_STREAM_CAPTURE, 0) >= 0)) {
				closeall();
				throw new Exception("alsa error snd_pcm_open");
			}
			snd_pcm_hw_params_malloc(&params); 
			snd_pcm_hw_params_any(handle, params);
			if (!(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0)) {
				closeall();
				throw new Exception("alsa error snd_pcm_hw_params_set_rate_resample");
			}
			if (!(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED)==0)) {
				closeall();
				throw new Exception("alsa error snd_pcm_hw_params_set_access");
			}
			if (!(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S16_LE)==0)) {
				closeall();
				throw new Exception("alsa error snd_pcm_hw_params_set_format");
			}
			if (!(snd_pcm_hw_params_set_channels(handle, params, channels)==0)) {
				closeall();
				throw new Exception("alsa error snd_pcm_hw_params_set_channels");
			}
			uint rmin=0, rmax=1000000;
			int dirmin=0, dirmax=0;
		    if (!(snd_pcm_hw_params_set_rate_minmax(handle, params, &rmin, &dirmin, &rmax, &dirmax) == 0)) {
				closeall();
		    	throw new Exception("alsa error snd_pcm_hw_params_set_rate_minmax");
		    }
		    //writeln("max rate = ", rmax);
			if (!(snd_pcm_hw_params_set_rate(handle, params, (rate==0)?rmax:rate, 0)==0)) {
				closeall();
				throw new Exception("alsa error snd_pcm_hw_params_set_rate");
			}

		    ulong pmin=0, pmax =4096;
		    if (!(snd_pcm_hw_params_set_period_size_minmax(handle, params, &pmin, &dirmin, &pmax, &dirmax) == 0)) {
				closeall();
		    	throw new Exception("alsa error snd_pcm_hw_params_set_period_size_minmax");
		    }
			period_size = pmax;
			//writeln("period_size = ", period_size);
			snd_pcm_hw_params_set_period_size(handle, params, period_size, 0);
			//writeln("period_size = ", period_size);

			if (!(snd_pcm_hw_params(handle, params)>=0)) {
				closeall();
				throw new Exception("alsa error snd_pcm_hw_params");
			}

			buffer = new short[channels*period_size];                 // buffer for the sound data
			idx = buffer.length;
		}
		~this() {
			closeall();
		}
		void closeall() {
			snd_pcm_hw_params_free(params);
			snd_pcm_drain(handle);
			snd_pcm_close(handle);
			snd_pcm_hw_free(handle);

		}
		bool empty() {
			return false;
		}
		bool check() {
			if (idx >= buffer.length) {
				import std.stdio;
				long sr = snd_pcm_readi(handle, cast(char*)(buffer.ptr), period_size);
				if (sr < 0)
				{
					core.stdc.stdio.stderr.writeln("error in readi, recover");
					sr = snd_pcm_recover(handle, cast(int)sr, 0);
					if (sr < 0)
					{
						core.stdc.stdio.stderr.writeln("recovery failed");
						return false;
					}
				}
				idx = 0;
			}
			return true;
		}
		short[] front() {
			if (!check()) return null;
			return buffer[idx..idx+channels];
		}
		void popFront() {
			idx += channels;
			check();
		}
	}


}