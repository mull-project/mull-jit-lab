
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

compile: clean
	# Use -v5 for maximum verbosity
	ghc -v2 -fllvm -ddump-llvm -ddump-to-file -keep-llvm-files -keep-tmp-files example.hs
	llvm-as-3.7 example.ll # Generates .bc (bitcode)
	llc-3.7 example.ll # Generates .s (assembly)

run:
	$(LLI) example.bc

normal:
	ghc -o example example.hs
	./example

.PHONY: clean
clean:
	rm -rfv example
	rm -rfv example.hi
	rm -rfv example.o
	rm -rfv example.bc
	rm -rfv example.dump-llvm
	rm -rfv example.s

