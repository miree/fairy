VPATH=../src

INCLUDES=\
	alsa.di                 \
	app.di                  \
	asciirender.di          \
	audiodaq.di             \
	cmdline.di              \
	expression.di           \
	fairy.di                \
	functions.di            \
	graphics.di             \
	elderpt.di              \
	histogram.di            \
	item.di                 \
	multifit_nlin.di        \
	serializeJSON.di        \
	transform.di            \
	ui.di                   \
	value.di                \
	waveform.di             

all: $(INCLUDES)

%.di: %.d
	dmd -i -I../src -o- -H $< 