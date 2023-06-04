all: lqmath.o imath

lqmath.o:
	gcc -Isrc -c lqmath.c -o lqmath.o

imath:
	make -C src

clean:
	rm -f lqmath.o
	make -C src clean
