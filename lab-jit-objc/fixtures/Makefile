# Self-Documented Makefile
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## Show this help message.
	@grep -E '^[0-9a-zA-Z_\.-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

CC=/opt/llvm-3.9/bin/clang
# CC=/opt/llvm-5.0.0/bin/clang
SYSROOT=-isysroot $(shell xcrun --sdk macosx --show-sdk-path)

default: compile run

MACOS_FRAMEWORKS_DIR=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
# XCTEST_PATH=$(MACOS_FRAMEWORKS_DIR)/XCTest.framework/XCTest
# XCTEST_FLAGS=-framework XCTest

CCFLAGS=$(SYSROOT) -F$(MACOS_FRAMEWORKS_DIR)

OUTPUT_PATH=$(PWD)/bitcode
001_minimal_test: ## Basic test
	mkdir -p $(OUTPUT_PATH)
	cd $@ && $(CC) $(CCFLAGS) -fobjc-arc -emit-llvm $@.m -c -o $(OUTPUT_PATH)/$@.bc
	cd $@ && $(CC) $(CCFLAGS) -fobjc-arc -emit-llvm -S $@.m -c -o $(OUTPUT_PATH)/$@.ll
	cd $@ && $(CC) $(CCFLAGS) -fobjc-arc $@.m -c -o $(OUTPUT_PATH)/$@.o
.PHONY: 001_minimal_test

clean: ## Cleans the build folder.
	rm -rfv $(OUTPUT_PATH)
