fairy: src/*.d
	dmd -Isrc -i src/app.d -of=fairy

gdc:
	make -j -f makefile.gdc

test: test-serializeJSON test-transform test-graphics

test-serializeJSON:
	dmd -g -cov -Isrc -i -unittest -main -run src/serializeJSON.d && tail -n 1 src-serializeJSON.lst

test-transform:
	dmd -g -cov -Isrc -i -unittest -main -run src/transform.d     && tail -n 1 src-transform.lst

test-graphics:
	dmd -g -cov -Isrc -i -unittest -main -run src/graphics.d      && tail -n 1 src-graphics.lst

clean:
	rm fairy *.o
