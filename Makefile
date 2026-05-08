PREFIX    ?= $(HOME)/.local
CONFDIR   ?= $(HOME)/.config/txs

BINDIR    = $(PREFIX)/bin
SHAREDIR  = $(PREFIX)/share/txs/completions

GO_SRC    = go
BINARY    = txs

.PHONY: build install uninstall generate-completions test lint help

build:
	cd go && go build -o ../bin/$(BINARY) .

generate-completions: build
	mkdir -p completions
	./bin/$(BINARY) completion bash > completions/txs.bash
	./bin/$(BINARY) completion zsh  > completions/txs.zsh
	./bin/$(BINARY) completion fish > completions/txs.fish

install: build generate-completions
	install -Dm755 bin/$(BINARY) "$(BINDIR)/$(BINARY)"
	install -Dm644 completions/txs.bash "$(SHAREDIR)/txs.bash"
	install -Dm644 completions/txs.zsh "$(SHAREDIR)/txs.zsh"
	install -Dm644 completions/txs.fish "$(SHAREDIR)/txs.fish"
	@if [ ! -f "$(CONFDIR)/projects.conf" ]; then \
		install -Dm644 examples/projects.conf.example "$(CONFDIR)/projects.conf"; \
		echo "Installed example config to $(CONFDIR)/projects.conf"; \
	elif [ -t 0 ]; then \
		printf "Config already exists at $(CONFDIR)/projects.conf. Overwrite? [y/N] "; \
		read -r ans; \
		case "$$ans" in \
			[yY]*) \
				install -Dm644 examples/projects.conf.example "$(CONFDIR)/projects.conf"; \
				echo "Overwritten config at $(CONFDIR)/projects.conf"; \
				;; \
			*) \
				echo "Kept existing config"; \
				;; \
		esac; \
	else \
		echo "Kept existing config at $(CONFDIR)/projects.conf"; \
	fi
	@if [ ! -f "$(CONFDIR)/config" ]; then \
		install -Dm644 examples/config.example "$(CONFDIR)/config"; \
		echo "Installed example settings to $(CONFDIR)/config"; \
	else \
		echo "Kept existing settings at $(CONFDIR)/config"; \
	fi
	@echo ""
	@echo "Installed txs to $(BINDIR)/txs"
	@echo ""
	@echo "To enable shell completions, add to your shell rc:"
	@echo "  zsh:  source $(SHAREDIR)/txs.zsh"
	@echo "  bash: source $(SHAREDIR)/txs.bash"
	@echo "  fish: source $(SHAREDIR)/txs.fish"

uninstall:
	rm -f "$(BINDIR)/txs"
	rm -rf "$(PREFIX)/share/txs"
	@echo "Uninstalled txs (config at $(CONFDIR) was kept)"

test:
	@bash tests/run_tests.sh

lint:
	shellcheck -s bash install.sh tests/run_tests.sh

help:
	@echo "txs Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  build                Build the Go binary to bin/txs"
	@echo "  generate-completions Generate shell completions to completions/"
	@echo "  install              Build and install txs to PREFIX (default: ${HOME}/.local)"
	@echo "  uninstall            Remove txs (keeps config)"
	@echo "  test                 Run test suite"
	@echo "  lint                 Run shellcheck on scripts"
	@echo "  help                 Show this message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX      Installation prefix  (default: ${HOME}/.local)"
	@echo "  CONFDIR     Config directory      (default: ${HOME}/.config/txs)"
