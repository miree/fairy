@trusted:

//import alsa.pcm;
import alsa_import;


immutable int Nsamples = 10000;


uint[] alsa_get_minmax_rates(string devname = "default") {
	//import alsa.pcm;
	import std.string;
	snd_pcm_t* handle;
	assert(snd_pcm_open(&handle, devname.toStringz, SND_PCM_STREAM_CAPTURE, 0) >= 0);
	scope(exit) {
		snd_pcm_hw_free(handle);
		snd_pcm_close(handle);
	}

	snd_pcm_hw_params_t *params;
	snd_pcm_hw_params_malloc(&params); 
	scope(exit) snd_pcm_hw_params_free(params);		
	snd_pcm_hw_params_any(handle, params);
	assert(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0);
	assert(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED) == 0);
	assert(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S32_LE) == 0);
	//assert(snd_pcm_hw_params_set_channels(handle, params, 2) == 0);

	uint[] result;
	uint fmin = 0;
	uint fmax = 10000000;
	int dirmin=0;
	int dirmax=0;
	assert(snd_pcm_hw_params_set_rate_minmax(handle, params, &fmin, &dirmin, &fmax, &dirmax) == 0);
	result ~= fmin;
	result ~= fmax;
	return result;

}

uint alsa_get_max_channels(string devname = "default") {
	//import alsa.pcm;
	import std.string;
	snd_pcm_t* handle;
	assert(snd_pcm_open(&handle, devname.toStringz, SND_PCM_STREAM_CAPTURE, 0) >= 0);
	scope(exit) {
		snd_pcm_hw_free(handle);
		snd_pcm_close(handle);
	}

	snd_pcm_hw_params_t *params;
	snd_pcm_hw_params_malloc(&params); 
	snd_pcm_hw_params_any(handle, params);
	assert(snd_pcm_hw_params_set_rate_resample(handle, params, 0) == 0);
	assert(snd_pcm_hw_params_set_access(handle, params, SND_PCM_ACCESS_RW_INTERLEAVED) == 0);
	assert(snd_pcm_hw_params_set_format(handle, params, SND_PCM_FORMAT_S32_LE) == 0);
	scope(exit) snd_pcm_hw_params_free(params);		
	uint fmin = 0;
	uint fmax = 10000000;
	int dirmin=0;
	int dirmax=0;
	assert(snd_pcm_hw_params_set_rate_minmax(handle, params, &fmin, &dirmin, &fmax, &dirmax) == 0);
	//for (uint ch = 1; ch < 100; ++ch) {
	//	if (snd_pcm_hw_params_set_channels(handle, params, ch)) return ch;
	//}
	uint ch=2;
	assert(snd_pcm_hw_params_set_channels_near(handle, params, &ch) == 0);
	return ch;
}

