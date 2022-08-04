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
CFLAGS=-std=c99 -fopenmp $(CWARNFLAGS) $(COPTFLAGS)
LDFLAGS=$(shell pkg-config --libs python3-embed)


.SECONDARY: $(CSRC)


.PHONY: all
all: $(BIN)

# Remove the implicity rule
%: %.c

.INTERMEDIATE: $(GCDAFILES)

% %.gcda: %.c Makefile
	gcc -o $@ $< $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -fprofile-generate
	./$@ 404 5 10 7 3 1 75 1 1 1 > /dev/null
	gcc -o $@ $< $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -fprofile-use

%.c %.html: %.pyx Makefile
	python3 $(shell which cython3) -o $@ $(CYFLAGS) $<


.PHONY: clean mrproper
clean:
	rm -f $(CSRC) $(HTMLSRC) $(INSTBIN) $(GCDAFILES)

mrproper: clean
	rm -f $(BIN)
