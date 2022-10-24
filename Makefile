smallpond: main.c
	gcc -o smallpond main.c $(shell pkg-config --cflags --libs lua) $(shell pkg-config --cflags --libs freetype2) $(shell pkg-config --cflags --libs cairo) $(shell pkg-config --cflags --libs libavcodec) $(shell pkg-config --cflags --libs libavutil)


clean:
	rm -f smallpond
