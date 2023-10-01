fairy: src/*.d
	dmd -Isrc -i src/app.d -of=fairy

test: test-serializeJSON test-transform test-draw

test-serializeJSON:
	dmd -g -cov -Isrc -i -unittest -main -run src/serializeJSON.d && tail -n 1 src-serializeJSON.lst

test-transform:
	dmd -g -cov -Isrc -i -unittest -main -run src/transform.d     && tail -n 1 src-transform.lst

test-draw:
	dmd -g -cov -Isrc -i -unittest -main -run src/draw.d          && tail -n 1 src-draw.lst

clean:
	rm fairy fairy.o
