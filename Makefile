BASENAME=numbers
BIN=$(BASENAME)
PYXSRC=$(BASENAME).pyx
CSRC=$(patsubst %.pyx,%.c,$(PYXSRC))
HTMLSRC=$(patsubst %.pyx,%.html,$(PYXSRC))
INSTBIN=$(patsubst %.pyx,%.inst,$(PYXSRC))
GCDAFILES=$(patsubst %.pyx,%.gcda,$(PYXSRC))

CWARNFLAGS=-Wall -Wextra -Wno-pedantic
COPTFLAGS=-Ofast -march=native -ggdb3

CYFLAGS=-a --embed -3
CPPFLAGS=$(shell pkg-config --cflags python3-embed)
CFLAGS=-std=c99 $(CWARNFLAGS) $(COPTFLAGS)
LDFLAGS=$(shell pkg-config --libs python3-embed)


.SECONDARY: $(CSRC)


.PHONY: all
all: $(BIN)

# Remove the implicity rule
%: %.c

%: %.c %.gcda Makefile
	gcc -o $@ $< $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -fprofile-use

%.gcda: %.inst Makefile
	./$< 404 5 10 7 3 1 75 1 1 1 > /dev/null

%.inst: %.c Makefile
	gcc -o $@ $< $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -fprofile-generate

%.c %.html: %.pyx Makefile
	cython -o $@ $(CYFLAGS) $<


.PHONY: clean mrproper
clean:
	rm -f $(CSRC) $(HTMLSRC) $(INSTBIN) $(GCDAFILES)

mrproper: clean
	rm -f $(BIN)
