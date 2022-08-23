smallpond: main.c
	gcc -o smallpond main.c $(shell pkg-config --cflags --libs lua) $(shell pkg-config --cflags --libs freetype2) $(shell pkg-config --cflags --libs cairo)

clean:
	rm -f smallpond
