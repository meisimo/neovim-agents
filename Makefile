.PHONY: test

test:
	NVIM_LOG_FILE=/tmp/agents-nvim-test.log nvim --headless -i NONE -u tests/minimal_init.lua -l tests/agents_spec.lua
	NVIM_LOG_FILE=/tmp/agents-nvim-suggestions-test.log nvim --headless -i NONE -u tests/minimal_init.lua -l tests/suggestions_spec.lua
