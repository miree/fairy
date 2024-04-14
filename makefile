LD_FLAGS = -L-L/home/michael/local/lib -L-rpath=/home/michael/local/lib


fairy: src/*.d
	dmd -Isrc -i src/app.d -of=fairy $(LD_FLAGS)

allegro5: src/*.d
	dmd -Isrc -i src/app.d -of=fairy -version=allegro5 $(LD_FLAGS)

elderpt: src/*.d
	dmd -Isrc -i src/app.d src/mbsapi/*.c -of=fairy -version=allegro5 -version=elderpt $(LD_FLAGS)

gtk3: src/*.d
	ldc -Isrc -i src/app.d src/mbsapi/*.c -of=fairy --d-version=gtk3 --d-version=elderpt $(LD_FLAGS) -I/usr/include/d/gtkd-3

gtk4: src/*.d
	dmd -Isrc -i src/app.d src/mbsapi/*.c  -of=fairy -version=gtk4 -version=elderpt $(LD_FLAGS) -I/usr/include/d/gtkd-4

minigui: src/*.d
	dmd -I.. -Isrc -i src/app.d -of=fairy -version=minigui -version=elderpt  $(LD_FLAGS)

minigui_gl: src/*.d
	dmd -I.. -Isrc -i src/app.d -of=fairy -version=minigui_gl -version=elderpt  $(LD_FLAGS)

ldc-allegro5: src/*.d
	ldc -O -release -Isrc -i src/app.d -of=fairy --d-version=allegro5 -L-lallegro_ttf -L-lallegro_font -L-lallegro -L-lallegro_primitives -L-lallegro_color -L-lasound

gdc:
	make -j -f makefile.gdc

gdc-allegro5:
	make allegro5 -j -f makefile.gdc

test: test-serializeJSON test-transform test-graphics

test-serializeJSON:
	dmd -g -cov -Isrc -i -unittest -main -run src/serializeJSON.d && tail -n 1 src-serializeJSON.lst

test-transform:
	dmd -g -cov -Isrc -i -unittest -main -run src/transform.d     && tail -n 1 src-transform.lst

test-graphics:
	dmd -g -cov -Isrc -i -unittest -main -run src/graphics.d      && tail -n 1 src-graphics.lst

clean:
	rm -f fairy *.o
