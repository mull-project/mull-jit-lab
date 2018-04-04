#include "ObjCEnabledMemoryManager.h"

#include <gtest/gtest.h>

#include <llvm/ExecutionEngine/Orc/CompileUtils.h>
#include <llvm/ExecutionEngine/Orc/ObjectLinkingLayer.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/Support/DynamicLibrary.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Support/TargetSelect.h>

#include "ObjCResolver.h"
#include "ObjCRuntime.h"
#include "TestHelpers.h"

using namespace llvm;
using namespace llvm::orc;

static const char *const FixturesPath = "/opt/mull-jit-lab/lab-jit-objc/fixtures/bitcode";

namespace SwiftDyLibPath {
  static const char *const Core =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCore.dylib";
  static const char *const Darwin =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftDarwin.dylib";
  static const char *const ObjectiveC =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftObjectiveC.dylib";
  static const char *const Dispatch =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftDispatch.dylib";
  static const char *const CoreFoundation =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCoreFoundation.dylib";
  static const char *const IOKit =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftIOKit.dylib";
  static const char *const CoreGraphics =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCoreGraphics.dylib";

    //  -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftFoundation.dylib
    //  -load=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftXPC.dylib

  static const char *const Foundation =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftFoundation.dylib";
  static const char *const CoreData =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCoreData.dylib";

  static const char *const XPC =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftXPC.dylib";
  static const char *const os =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftos.dylib";
  static const char *const Metal =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftMetal.dylib";

  static const char *const CoreImage =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftCoreImage.dylib";
  static const char *const QuartzCore =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftQuartzCore.dylib";
  static const char *const AppKit =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftAppKit.dylib";

  static const char *const XCTest =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftXCTest.dylib";
  static const char *const SwiftOnoneSupport =
  "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx/libswiftSwiftOnoneSupport.dylib";


}

static void loadSwiftLibrariesOrExit() {
  const char *const libraries[] = {
    SwiftDyLibPath::Core,
    SwiftDyLibPath::Darwin,
    SwiftDyLibPath::ObjectiveC,
    SwiftDyLibPath::Dispatch,
    SwiftDyLibPath::CoreFoundation,
    SwiftDyLibPath::IOKit,
    SwiftDyLibPath::CoreGraphics,
    SwiftDyLibPath::Foundation,
    SwiftDyLibPath::CoreData,

    SwiftDyLibPath::XPC,
    SwiftDyLibPath::os,
    SwiftDyLibPath::Metal,
    SwiftDyLibPath::CoreImage,
    SwiftDyLibPath::QuartzCore,
    SwiftDyLibPath::AppKit,

    SwiftDyLibPath::XCTest,
    SwiftDyLibPath::SwiftOnoneSupport,
  };

  for (const char *const lib: libraries) {
    std::string errorMessage;
    if (sys::DynamicLibrary::LoadLibraryPermanently(lib,
                                                    &errorMessage)) {
      errs() << errorMessage << "\n";
      exit(1);
    }
  }
}

TEST(XCTest_Swift, Test_001_Minimal) {
    // These lines are needed for TargetMachine TM to be created correctly.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);

  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
    "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
  ));
  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
    "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest"
  ));
  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
    "/opt/CustomXCTestRunner/CustomXCTestRunner.dylib"
  ));
  loadSwiftLibrariesOrExit();

  llvm::LLVMContext llvmContext;

  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "swift_001_minimal_xctestcase_run.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
    EngineBuilder().selectTarget(llvm::Triple(),
                                 "",
                                 "",
                                 SmallVector<std::string, 1>())
  );

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto objcCompiledModule = compiler(*objcModule);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjCResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  void *runnerPtr = sys::DynamicLibrary::SearchForAddressOfSymbol("CustomXCTestRunnerRun");
  auto runnerFPtr = ((int (*)(void))runnerPtr);
  int result = runnerFPtr();
  result = runnerFPtr();
  ASSERT_EQ(result, 0);
}
