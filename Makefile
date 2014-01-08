LUAVER  := 5.1
PREFIX  := /usr/local
DPREFIX := $(DESTDIR)$(PREFIX)
LIBDIR  := $(DPREFIX)/share/lua/$(LUAVER)
INSTALL := install

.PHONY: all test install

all:
	@echo "Nothing to build here, you can just make install"

test:
	cd test && ./test.sh

install:
	$(INSTALL) -d $(LIBDIR)/luchador
	$(INSTALL) lib/luchador/* $(LIBDIR)/luchador

uninstall:
	rm -r $(LIBDIR)/luchador
