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
	string          name;
	shared Waveform wave;
}

@trusted
static ~this() {
	if (running) {
		tid.send(MsgStop());
		receive((MsgAck msg) {});
	}
}

interface AudioDAQ {
	uint[] get_allowed_rates();
	uint[] get_allowed_channels();
}

version(Windows) {

}
else {

	pragma(lib, "asound");



	@trusted
	void run_audiodaq(Tid main_thread_tid, int num_channels, int trace_length, string device_name) {
		import std.datetime;
		main_thread = main_thread_tid;
		bool paused = false;
		bool stop = false;
		// create fairy Wavforms and send them over to main thread
		traces.length = num_channels;

		foreach(channel; 0..num_channels) {
			import std.conv;
			import std.stdio;
			string tracename = "audiodaq/"~channel.to!string;
			traces[channel] = new Waveform(new double[trace_length], 1, 0, trace_length);
			writeln("send waveform item");
			main_thread.send(MsgWaveformCreate(tracename, cast(shared Waveform)traces[$-1]));
			receive((MsgAck msg) {});
			writeln("got ack for waveform");
		}
		auto pcm = new AlsaPcmRecord(num_channels, device_name);

		// main loop take data samples and send trace to main thread when trigger is detected
		for (uint i; ;++i) {
			if (!paused) {
				auto t = Clock.currTime;
				uint time_secs = cast(uint)t.toUnixTime;
				auto timeval = t.toTimeVal;
				uint timestamp = 0;
				uint frac_msecs = cast(uint)(timeval.tv_usec/1e3);
				pcm.popFront;
				foreach(ch;0..num_channels) {
					traces[ch].d.data[i] = pcm.front[ch];
				}
				if (i == trace_length-1) {
					i = 0;
					import std.stdio;
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
			snd_pcm_hw_params_t *params;
			snd_pcm_hw_params_malloc(&params); 
			scope(exit) snd_pcm_hw_params_free(params);		
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
			snd_pcm_hw_params_t *params;
			snd_pcm_hw_params_malloc(&params);
			scope(exit) snd_pcm_hw_params_free(params);		
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
		int[] buffer;
		ulong idx;

		this(uint ch, string device_name) {
			channels = ch;
			import std.string;
			assert(snd_pcm_open(&handle, device_name.toStringz, SND_PCM_STREAM_CAPTURE, 0) >= 0);
			snd_pcm_hw_params_malloc(&params); 
			snd_pcm_hw_params_any(handle, params);
			assert(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0);
			assert(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED)==0);
			assert(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S32_LE)==0);
			assert(snd_pcm_hw_params_set_channels(handle, params, channels)==0);
			uint rmin=0, rmax=1000000;
			int dirmin=0, dirmax=0;
		    assert(snd_pcm_hw_params_set_rate_minmax(handle, params, &rmin, &dirmin, &rmax, &dirmax) == 0);
		    writeln("max rate = ", rmax);
			assert(snd_pcm_hw_params_set_rate(handle, params, rmax, 0)==0);

		    ulong pmin=0, pmax =1000000;
		    assert(snd_pcm_hw_params_set_period_size_minmax(handle, params, &pmin, &dirmin, &pmax, &dirmax) == 0);
			period_size = pmax;
			writeln("period_size = ", period_size);
			snd_pcm_hw_params_set_period_size(handle, params, period_size, 0);

			assert(snd_pcm_hw_params(handle, params)>=0);

			buffer = new int[channels*period_size];                 // buffer for the sound data
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
		int[] front() {
			if (!check()) return null;
			return buffer[idx..idx+channels];
		}
		void popFront() {
			idx += channels;
			check();
		}
	}


}