ifeq (, $(LLI))
define LLI_ERROR_MESSAGE

Provide LLI (path to lli).

The easiest way to get lli is to `brew install llvm`.

Then do:
LLI=/usr/local/opt/llvm/bin/lli make ...

endef
$(error $(LLI_ERROR_MESSAGE))
endif

CC=/opt/llvm-3.9/bin/clang
# CC=/opt/llvm-5.0.0/bin/clang
SYSROOT=-isysroot $(shell xcrun --sdk macosx --show-sdk-path)

default: compile run

MACOS_FRAMEWORKS_DIR=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
XCTEST_PATH=$(MACOS_FRAMEWORKS_DIR)/XCTest.framework/XCTest
XCTEST_FLAGS=-framework XCTest

CCFLAGS=$(SYSROOT) -F$(MACOS_FRAMEWORKS_DIR)


compile:
	$(CC) $(CCFLAGS) -fno-objc-arc -emit-llvm jitobjc.mm -c -o jitobjc.bc
	$(CC) $(CCFLAGS) -emit-llvm SomeClass.mm -c -o SomeClass.bc

	$(CC) $(CCFLAGS) jitobjc.mm -c -o jitobjc.o
	$(CC) $(CCFLAGS) SomeClass.mm -c -o SomeClass.o

	$(CC) $(CCFLAGS) $(XCTEST_FLAGS) -shared -undefined dynamic_lookup -o jitobjc.dylib jitobjc.mm
	$(CC) $(CCFLAGS) $(XCTEST_FLAGS) -shared -undefined dynamic_lookup -o SomeClass.dylib SomeClass.mm
	$(CC) $(CCFLAGS) $(XCTEST_FLAGS) -shared -undefined dynamic_lookup -o MUT_XCTestDriver.dylib MUT_XCTestDriver.mm
	$(CC) $(CCFLAGS) -emit-llvm -S jitobjc.mm -c -o jitobjc.ll

run:
	$(LLI) \
	-load=/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation \
	-load=$(XCTEST_PATH) \
	-load=MUT_XCTestDriver.dylib \
	-load=./SomeClass.dylib \
	jitobjc.bc

run_normal:
	$(CC)++ -framework Cocoa jitobjc.mm -o jitobjc
	./jitobjc
