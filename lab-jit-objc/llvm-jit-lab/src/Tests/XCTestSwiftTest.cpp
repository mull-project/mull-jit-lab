#include "ObjCEnabledMemoryManager.h"

#include <gtest/gtest.h>

#include <llvm/ExecutionEngine/Orc/CompileUtils.h>
#include <llvm/ExecutionEngine/Orc/ObjectLinkingLayer.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Value.h>
#include <llvm/IR/Constants.h>

#include <llvm/Support/DynamicLibrary.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Object/ObjectFile.h>
#include <llvm/Object/Binary.h>

#include "ObjCResolver.h"
#include "ObjCRuntime.h"
#include "TestHelpers.h"

using namespace llvm;
using namespace llvm::orc;
using namespace llvm::object;

static
OwningBinary<ObjectFile> getObjectFromDisk(const std::string &path) {

  ErrorOr<std::unique_ptr<MemoryBuffer>> buffer =
    MemoryBuffer::getFile(path.c_str());

  if (!buffer) {
    return OwningBinary<ObjectFile>();
  }

  Expected<std::unique_ptr<ObjectFile>> objectOrError =
  ObjectFile::createObjectFile(buffer.get()->getMemBufferRef());

  if (!objectOrError) {
    return OwningBinary<ObjectFile>();
  }

  std::unique_ptr<ObjectFile> objectFile(std::move(objectOrError.get()));

  auto owningObject = OwningBinary<ObjectFile>(std::move(objectFile),
                                               std::move(buffer.get()));
  return owningObject;
}

static std::vector<llvm::Function *> getStaticConstructors(llvm::Module *module) {
  /// NOTE: Just Copied the whole logic from ExecutionEngine
  std::vector<llvm::Function *> Ctors;

  GlobalVariable *GV = module->getNamedGlobal("llvm.global_ctors");

  // If this global has internal linkage, or if it has a use, then it must be
  // an old-style (llvmgcc3) static ctor with __main linked in and in use.  If
  // this is the case, don't execute any of the global ctors, __main will do
  // it.
  if (!GV || GV->isDeclaration() || GV->hasLocalLinkage()) return Ctors;

  // Should be an array of '{ i32, void ()* }' structs.  The first value is
  // the init priority, which we ignore.
  ConstantArray *InitList = dyn_cast<llvm::ConstantArray>(GV->getInitializer());
  if (!InitList) {
    return Ctors;
  }

  for (unsigned i = 0, e = InitList->getNumOperands(); i != e; ++i) {
    ConstantStruct *CS = dyn_cast<ConstantStruct>(InitList->getOperand(i));
    if (!CS) continue;

    Constant *FP = CS->getOperand(1);
    if (FP->isNullValue())
      continue;  // Found a sentinal value, ignore.

    // Strip off constant expression casts.
    if (ConstantExpr *CE = dyn_cast<ConstantExpr>(FP))
      if (CE->isCast())
        FP = CE->getOperand(0);

    // Execute the ctor/dtor function!
    if (Function *F = dyn_cast<Function>(FP))
      Ctors.push_back(F);

    // FIXME: It is marginally lame that we just do nothing here if we see an
    // entry we don't recognize. It might not be unreasonable for the verifier
    // to not even allow this and just assert here.
  }

  return Ctors;
}

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

  std::vector<llvm::Function *> staticCtors = getStaticConstructors(objcModule.get());
  errs() << "static constructors: " << staticCtors.size() << "\n";
  for (auto &fptr: staticCtors) {
    errs() << fptr->getName() << "\n";
  }

//  exit(1);
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
  char objectFixturePath[255];
  snprintf(objectFixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "swift_001_minimal_xctestcase_run.o");

//  auto objcCompiledModule = getObjectFromDisk(objectFixturePath);
  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjCResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  void *runnerPtr = sys::DynamicLibrary::SearchForAddressOfSymbol("CustomXCTestRunnerRun");
  errs() << "runnerPtr: " << runnerPtr << "\n";
  auto runnerFPtr = ((int (*)(void))runnerPtr);
  int result = runnerFPtr();
  ASSERT_EQ(result, 0);
}
