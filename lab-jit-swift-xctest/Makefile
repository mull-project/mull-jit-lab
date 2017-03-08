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

compile2:
	swiftc \
    -emit-bc \
    -F/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
    -Xlinker -rpath -Xlinker /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
    -lswiftCore jitswift.swift

compile:
	xcrun swiftc -emit-bc \
	-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx \
	-L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/x86_64 \
	-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx \
	-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/x86_64 \
	-Xlinker -rpath -I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx \
	-lSwiftXCTest \
	-sdk $$(xcrun --show-sdk-path --sdk macosx) \
  jitswift.swift
	swiftc jitswift.swift

run:
	# $(LLI) -load=/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation jitswift.bc
	$(LLI) -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCore.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftDarwin.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftObjectiveC.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftDispatch.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftSwiftOnoneSupport.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftIOKit.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCoreGraphics.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftFoundation.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCoreData.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftXPC.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCoreImage.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftQuartzCore.dylib \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftAppKit.dylib \
           -load=/Applications/Xcode.app/Contents//Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest \
           -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftXCTest.dylib \
           jitswift.bc

run_normal:
	clang++ -framework Cocoa jitobjc.mm -o jitobjc
	./jitobjc

clean:
	rm -rfv *.bc
	rm -rfv *.ll

