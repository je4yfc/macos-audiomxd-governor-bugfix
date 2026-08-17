CC ?= clang
CFLAGS ?= -O2 -Wall -fblocks
TARGET = audioaccessory_shim
DESTDIR ?= /usr/local/libexec

all: $(TARGET)

$(TARGET): audioaccessory_shim.c
	$(CC) $(CFLAGS) $< -o $@

install: $(TARGET)
	mkdir -p $(DESTDIR)
	cp $(TARGET) $(DESTDIR)/$(TARGET)
	chmod 0755 $(DESTDIR)/$(TARGET)
	chown root:wheel $(DESTDIR)/$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all install clean
