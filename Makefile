# GNU Makefile

BINNAME ?= kpatchview
PREFIX  ?= $(HOME)/.local
BINDIR  ?= $(PREFIX)/bin
COMPDIR ?= $(PREFIX)/share/bash-completion/completions

.PHONY: install uninstall

install:
	install -D -m 0755 kpatchview.sh $(BINDIR)/$(BINNAME)
	install -D -m 0644 completions/kpatchview $(COMPDIR)/$(BINNAME)
	@echo Installed $(BINDIR)/$(BINNAME)

uninstall:
	rm -f $(BINDIR)/$(BINNAME)
	rm -f $(COMPDIR)/$(BINNAME)
	@echo Removed $(BINDIR)/$(BINNAME)
