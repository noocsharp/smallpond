smallpond: main.c lqmath-104/lqmath.c
	gcc -o smallpond main.c lqmath-104/lqmath.o lqmath-104/src/imath.o lqmath-104/src/imrat.o $(shell pkg-config --cflags --libs lua) $(shell pkg-config --cflags --libs freetype2) $(shell pkg-config --cflags --libs cairo) $(shell pkg-config --cflags --libs libavcodec) $(shell pkg-config --cflags --libs libavutil) $(shell pkg-config --cflags --libs libavformat)


clean:
	rm -f smallpond
