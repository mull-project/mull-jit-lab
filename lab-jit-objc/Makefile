
ifeq (, $(LLI))
define LLI_ERROR_MESSAGE

Provide $LLI (path to lli).
LLI=/Users/Stanislaw/Projects/LLVM/BuildXcode/Debug/bin/lli

endef
$(error $(LLI_ERROR_MESSAGE))
endif

default: compile run

compile:	
	clang -emit-llvm jitobjc.mm -c -o jitobjc.bc
	clang -emit-llvm -S jitobjc.mm -c -o jitobjc.ll

run:
	$(LLI) -load=/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation jitobjc.bc

run_normal:
	clang++ -framework Cocoa jitobjc.mm -o jitobjc
	./jitobjc
