PREFIX    ?= $(HOME)/.local
CONFDIR   ?= $(HOME)/.config/txs

BINDIR    = $(PREFIX)/bin
LIBDIR    = $(PREFIX)/lib/txs
SHAREDIR  = $(PREFIX)/share/txs/completions

LIB_FILES = lib/log.sh \
            lib/config.sh \
            lib/tmux.sh \
            lib/git.sh \
            lib/commands.sh \
            lib/ui.sh

.PHONY: install uninstall test lint help

install:
	install -Dm755 bin/txs "$(BINDIR)/txs"
	@for f in $(LIB_FILES); do \
		install -Dm644 "$$f" "$(LIBDIR)/$$(basename $$f)"; \
	done
	install -Dm644 completions/txs.bash "$(SHAREDIR)/txs.bash"
	install -Dm644 completions/txs.zsh "$(SHAREDIR)/txs.zsh"
	@if [ ! -f "$(CONFDIR)/projects.conf" ]; then \
		install -Dm644 projects.conf.example "$(CONFDIR)/projects.conf"; \
		echo "Installed example config to $(CONFDIR)/projects.conf"; \
	else \
		printf "Config already exists at $(CONFDIR)/projects.conf. Overwrite? [y/N] "; \
		read ans; \
		case "$$ans" in \
			[yY]*) \
				install -Dm644 projects.conf.example "$(CONFDIR)/projects.conf"; \
				echo "Overwritten config at $(CONFDIR)/projects.conf"; \
				;; \
			*) \
				echo "Kept existing config"; \
				;; \
		esac; \
	fi
	@echo ""
	@echo "Installed txs to $(BINDIR)/txs"
	@echo ""
	@echo "To enable shell completions, add to your shell rc:"
	@echo "  zsh:  source $(SHAREDIR)/txs.zsh"
	@echo "  bash: source $(SHAREDIR)/txs.bash"

uninstall:
	rm -f "$(BINDIR)/txs"
	rm -rf "$(LIBDIR)"
	rm -rf "$(PREFIX)/share/txs"
	@echo "Uninstalled txs (config at $(CONFDIR) was kept)"

test:
	@bash tests/run_tests.sh

lint:
	shellcheck -s bash lib/*.sh bin/txs completions/txs.bash install.sh tests/run_tests.sh

help:
	@echo "txs Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  install     Install txs to PREFIX (default: ${HOME}/.local)"
	@echo "  uninstall   Remove txs (keeps config)"
	@echo "  test        Run test suite"
	@echo "  lint        Run shellcheck on all scripts"
	@echo "  help        Show this message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX      Installation prefix  (default: ${HOME}/.local)"
	@echo "  CONFDIR     Config directory      (default: ${HOME}/.config/txs)"
