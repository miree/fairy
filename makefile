fairy: src/*.d
	dmd -Isrc -i src/app.d -of=fairy

allegro5: src/*.d
	dmd -Isrc -i src/app.d -of=fairy -version=allegro5

elderpt: src/*.d
	dmd -Isrc -i src/app.d -of=fairy -version=allegro5 -version=elderpt -L-L/home/michael/.local/lib

gtk3: src/*.d
	ldc -Isrc -i src/app.d -of=fairy --d-version=gtk3 --d-version=elderpt -L-L/home/michael/.local/lib -I/usr/include/d/gtkd-3

minigui: src/*.d
	dmd -I.. -Isrc -i src/app.d -of=fairy -version=minigui -version=elderpt  -L-L/home/michael/.local/lib

minigui_gl: src/*.d
	dmd -I.. -Isrc -i src/app.d -of=fairy -version=minigui_gl -version=elderpt  -L-L/home/michael/.local/lib

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
