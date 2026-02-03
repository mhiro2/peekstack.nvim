.PHONY: deps deps-plenary fmt lint stylua stylua-check selene test

CC ?= cc
NVIM ?= nvim
GIT ?= git
PLENARY_PATH ?= deps/plenary.nvim

deps: deps-plenary

deps-plenary:
	@if [ ! -d "$(PLENARY_PATH)" ]; then \
		mkdir -p "$$(dirname "$(PLENARY_PATH)")"; \
		$(GIT) clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$(PLENARY_PATH)"; \
	fi

fmt: stylua

lint: stylua-check selene

stylua:
	stylua .

stylua-check:
	stylua --check .

selene:
	selene ./lua ./plugin ./tests

test: deps
	PLENARY_PATH="$(PLENARY_PATH)" \
		$(NVIM) --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests { minimal_init = './tests/minimal_init.lua' }" \
		-c "qa"
