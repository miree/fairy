fairy: src/*.d
	dmd -Isrc -i src/app.d -of=fairy

test:
	dmd -g -cov -Isrc -i -unittest -main -run src/serializeJSON.d && tail -n 1 src-serializeJSON.lst

clean:
	rm fairy fairy.o
