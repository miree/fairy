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
	shared(double[])      backbuf;
	shared(ulong[])       itemversion;
}

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
	double[] get(); // only call if empty() is false
}

class NoFilter : Filter {
	double[1] value;
	override void put(double x) {
		value[0] = x;
	}
	override bool empty() {
		return false;
	}
	override uint N() {
		return 1;
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
	void run_audiodaq(Tid main_thread_tid, int trace_length, int num_channels, int samplingrate, InterpolationMode interpolation, string device_name) {
		import std.datetime;
		main_thread = main_thread_tid;
		bool paused = false;
		bool stop = false;
		// create fairy Wavforms and send them over to main thread
		import std.stdio;
		writeln("run_audiodaq ", num_channels);
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
			traces[channel] = new Waveform(new shared(double[])(trace_length*filters[channel].N), filters[channel].N, 0, trace_length, itemversion);
			//writeln("send waveform item ", traces[channel].get_type());
			main_thread.send(MsgWaveformCreate(tracename, traces[channel].d, traces[channel].backbuffer, itemversion));
			receive((MsgAck msg) {});
			//writeln("got ack for waveform");
		}

		auto pcm = new AlsaPcmRecord(num_channels, samplingrate, device_name);
		// main loop take data samples and send trace to main thread when trigger is detected
		//int[] previous_sample = new int[num_channels];
		for (int i=0; ;) {
			if (!paused) {
				pcm.popFront;
				//if (i==-1) {
				//	foreach(ch;0..num_channels) {
				//		previous_sample[ch] = pcm.front[ch];
				//	}
				//	continue;
				//}
				foreach(ch;0..num_channels) {
					filters[ch].put(pcm.front[ch]);
					if (!filters[ch].empty) {
						traces[ch].backbuffer[filters[ch].N*i..filters[ch].N*(i+1)] = filters[ch].get[0..filters[ch].N];
						if (ch==num_channels-1) ++i;
					}
					//traces[ch].backbuffer[2*i]    = previous_sample[ch];
					//traces[ch].backbuffer[2*i+1]  = pcm.front[ch]-previous_sample[ch];
					//previous_sample[ch] = pcm.front[ch];
				}
				if (i == trace_length) {
					i = 0;
					import std.stdio;
					foreach(ch;0..num_channels) {
						traces[ch].swap_backbuffer();
					}
					foreach(ch;0..num_channels) {
						traces[ch].overrideVersion(traces[ch].getVersion+1);
					}
				}
			}
			receiveTimeout(paused?100.msecs:Duration.zero,
				(MsgPause    msg) { paused = true;  main_thread.send(MsgAck()); },
				(MsgContinue msg) { paused = false; main_thread.send(MsgAck()); },
				(MsgStop     msg) { stop   = true;  main_thread.send(MsgAck()); });
			if (stop) break;
		}
		import std.stdio;
		writeln("run_audiodaq returns");
	}

	import alsa_import;

	@trusted
	class Alsa : AudioDAQ {

		snd_pcm_t* handle;
		snd_pcm_hw_params_t *params;

		this(string devname) {
			import std.string;
			assert(snd_pcm_open(&handle, devname.toStringz, SND_PCM_STREAM_CAPTURE, 0) >= 0);
			assert(snd_pcm_hw_params_malloc(&params) >= 0); 

		}
		~this() {
			import std.stdio;
			snd_pcm_hw_free(handle);
			snd_pcm_close(handle);
			snd_pcm_hw_params_free(params);
		}


		override uint[] get_allowed_rates() {
			snd_pcm_hw_params_any(handle, params);
			assert(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0);
			assert(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED) == 0);
			assert(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S32_LE) == 0);

			uint[] result;
			uint fmin = 0;
			uint fmax = 10000000;
			int dirmin=0;
			int dirmax=0;
			assert(snd_pcm_hw_params_set_rate_minmax(handle, params, &fmin, &dirmin, &fmax, &dirmax) == 0);
			foreach(f; [44100,48000,96000,192000,352000]) {
				if (f<= fmax && f >= fmin) {
					result ~= f;
				}
			}
			return result;
		}

		override uint[] get_allowed_channels() {
			uint[] result = []; 
			snd_pcm_hw_params_any(handle, params);
			assert(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0);
			assert(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED) == 0);
			assert(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S32_LE) == 0);
			uint fmin = 0;
			uint fmax = 10000000;
			int dirmin=0;
			int dirmax=0;
			assert(snd_pcm_hw_params_set_rate_minmax(handle, params, &fmin, &dirmin, &fmax, &dirmax) == 0);
			foreach(ch; 1..3) {
				if (snd_pcm_hw_params_test_channels(handle, params, ch) == 0) {
					result ~= ch;
				}
			}
			return result;
		}


	}


	@trusted
	class AlsaPcmRecord {
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
				throw new Exception("alsa error snd_pcm_open");
			}
			snd_pcm_hw_params_malloc(&params); 
			snd_pcm_hw_params_any(handle, params);
			if (!(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0)) {
				throw new Exception("alsa error snd_pcm_hw_params_set_rate_resample");
			}
			if (!(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED)==0)) {
				throw new Exception("alsa error snd_pcm_hw_params_set_access");
			}
			if (!(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S16_LE)==0)) {
				throw new Exception("alsa error snd_pcm_hw_params_set_format");
			}
			if (!(snd_pcm_hw_params_set_channels(handle, params, channels)==0)) {
				throw new Exception("alsa error snd_pcm_hw_params_set_channels");
			}
			uint rmin=0, rmax=1000000;
			int dirmin=0, dirmax=0;
		    if (!(snd_pcm_hw_params_set_rate_minmax(handle, params, &rmin, &dirmin, &rmax, &dirmax) == 0)) {
		    	throw new Exception("alsa error snd_pcm_hw_params_set_rate_minmax");
		    }
		    writeln("max rate = ", rmax);
			if (!(snd_pcm_hw_params_set_rate(handle, params, (rate==0)?rmax:rate, 0)==0)) {
				throw new Exception("alsa error snd_pcm_hw_params_set_rate");
			}

		    ulong pmin=0, pmax =4096;
		    if (!(snd_pcm_hw_params_set_period_size_minmax(handle, params, &pmin, &dirmin, &pmax, &dirmax) == 0)) {
		    	throw new Exception("alsa error snd_pcm_hw_params_set_period_size_minmax");
		    }
			period_size = pmax;
			writeln("period_size = ", period_size);
			snd_pcm_hw_params_set_period_size(handle, params, period_size, 0);
			writeln("period_size = ", period_size);

			if (!(snd_pcm_hw_params(handle, params)>=0)) {
				throw new Exception("alsa error snd_pcm_hw_params");
			}

			buffer = new short[channels*period_size];                 // buffer for the sound data
			idx = buffer.length;
		}
		~this() {
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
				//import std.stdio;
				//writeln('.');

				long sr = snd_pcm_readi(handle, cast(char*)(buffer), period_size);
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