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
	swiftc -emit-bc jitswift.swift
	swiftc jitswift.swift

run:
	# $(LLI) -load=/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation jitswift.bc
	$(LLI) -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCore.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftSwiftOnoneSupport.dylib \
           jitswift.bc

run_normal:
	clang++ -framework Cocoa jitobjc.mm -o jitobjc
	./jitobjc
