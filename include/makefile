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
	interactive.di          \
	interactive_demo.di     \
	gate.di                 \
	multifit_nlin.di        \
	serializeJSON.di        \
	transform.di            \
	ui.di                   \
	value.di                \
	waveform.di             \
	alsa_import.i           \
	mbsapi_import.i         \
	gsl_import.i            \
	gtk4_import.i           

all: $(INCLUDES)

%.di: %.d
	dmd -i -I../src -o- -H $< 

%.i: %.c
	gcc `pkg-config gtk4 alsa gsl --cflags` -E $< > $@
