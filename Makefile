CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -O2 -ggdb
TOPDIR	= $(shell pwd)
export TOPDIR

TARGETS = pyra_volumed femtocom


.PHONY: all install clean

all: $(TARGETS)

clean:
	$(RM) $(TARGETS)

pyra_volumed: LDLIBS+= -lasound -liio


install:
	install -d "$(DESTDIR)/usr/bin"
	install -m 755 -t "$(DESTDIR)/usr/bin" "$(TOPDIR)/pyra_volumed"
	install -d "$(DESTDIR)/lib/systemd/system"
	install -m 644 -t "$(DESTDIR)/lib/systemd/system/" "$(TOPDIR)/pyra_volumed.service"
	install -d "$(DESTDIR)/lib/udev/rules.d/"
	install -m 644 -t "$(DESTDIR)/lib/udev/rules.d/" "$(TOPDIR)/nubs.rules"
	install -m 755 -t "$(DESTDIR)/usr/bin" "$(TOPDIR)/femtocom"
