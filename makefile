fairy: src/*.d
	dmd -Isrc -i src/app.d -of=fairy -L-lasound

allegro5: src/*.d
	dmd -Isrc -i src/app.d -of=fairy -version=allegro5 -L-lallegro_ttf -L-lallegro_font -L-lallegro -L-lallegro_primitives -L-lallegro_color -L-lasound

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
