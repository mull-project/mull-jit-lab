
ifeq (, $(LLI))
define LLI_ERROR_MESSAGE

Provide $LLI (path to lli).
LLI=/Users/Stanislaw/Projects/LLVM/BuildXcode/Debug/bin/lli

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

