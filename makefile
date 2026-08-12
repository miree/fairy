###############################################################################
# Choose your D compiler
###############################################################################
DC=ldc  # LDC on Arch Linux 
#DC=ldc2 # LDC on Debian Linux
#DC=dmd

# Replace -L with -L-L and -l with -L-l in pkg-config output 
# (all linker arguments start with -L for the D compilers LDC or DMD)
LD_FLAGS = `pkg-config --libs elderpt-0.1 gsl | sed -e 's/-L/-L-L/g' | sed -e 's/-l/-L-l/g'`

# for some reason the --cflags of gtkd-3 pkg-config return -pthread. filter it out!
CFLAGS = `pkg-config --cflags gtkd-3 | sed -e 's/-pthread/ /'` \
         -link-defaultlib-shared \
         -O4

##############################################################################
# Main Target: The canonical fairy gui version is at the moment with Gtk3
###############################################################################
fairy: src/*.d src/mbsapi/*.c 
	$(DC) -Isrc -i src/app.d src/mbsapi/*.c -of=fairy --d-version=gtk3 --d-version=elderpt $(LD_FLAGS) $(CFLAGS)

##############################################################################
# Command line interface version without any gui support and 
# always dmd compiler for fast builds
##############################################################################
cli-dmd: src/*.d
	dmd -Isrc -i src/app.d -of=fairy $(LD_FLAGS)

###############################################################################
####  targets below are for unittesting
###############################################################################
test: test-serializeJSON test-transform test-graphics

test-serializeJSON:
	dmd -g -cov -Isrc -i -unittest -main -run src/serializeJSON.d && tail -n 1 src-serializeJSON.lst

test-transform:
	dmd -g -cov -Isrc -i -unittest -main -run src/transform.d     && tail -n 1 src-transform.lst

test-graphics:
	dmd -g -cov -Isrc -i -unittest -main -run src/graphics.d      && tail -n 1 src-graphics.lst

test-expression:
	dmd -g -cov -Isrc -i -unittest -main -run src/expression.d    && tail -n 1 src-expression.lst

clean:
	rm -f fairy *.o src/*.i *.lst
