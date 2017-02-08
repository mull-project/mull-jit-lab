
ifeq (, $(LLI))
define LLI_ERROR_MESSAGE

Provide LLI (path to lli).

The easiest way to get lli is to `brew install llvm`.

Then do:
LLI=/usr/local/opt/llvm/bin/lli make ...


endef
$(error $(LLI_ERROR_MESSAGE))
endif

default: compile run

compile:
	ghc -fllvm example.hs

run:
	# $(LLI) example.bc

normal:
	ghc -o example example.hs
	./example

