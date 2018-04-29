#include "ObjCEnabledMemoryManager.h"

#include <gtest/gtest.h>

#include <llvm/ExecutionEngine/ExecutionEngine.h>
#include <llvm/ExecutionEngine/Orc/CompileUtils.h>
#include <llvm/ExecutionEngine/Orc/RTDyldObjectLinkingLayer.h>

#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Value.h>
#include <llvm/IR/Constants.h>

#include <llvm/Support/DynamicLibrary.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Object/ObjectFile.h>
#include <llvm/Object/Binary.h>

#include <objc/message.h>

#include "ObjCResolver.h"
#include "ObjCRuntime.h"
#include "TestHelpers.h"
#include "ObjCRuntimeHelpers.h"
#include <dlfcn.h>

#include <memory>

using namespace llvm;
using namespace llvm::orc;
using namespace llvm::object;

@class BinarySearchTest;

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


class JITSetup {

public:
  static
  llvm::orc::RTDyldObjectLinkingLayer::MemoryManagerGetter getMemoryManager() {
    llvm::orc::RTDyldObjectLinkingLayer::MemoryManagerGetter GetMemMgr =
    []() {
      return std::make_shared<ObjCEnabledMemoryManager>();
    };
    return GetMemMgr;
  }
};

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
  assert(dlopen("/opt/SwiftTestCase/Build/Products/Release/SwiftTestCase.framework/Versions/Current/SwiftTestCase", RTLD_NOW));

  Class correctBSTClazz = objc_getClass("BinarySearchTestCorrect");
  assert(correctBSTClazz);
  id correctBSTClazzInstance = objc_msgSend(objc_msgSend(correctBSTClazz, @selector(alloc)), @selector(init));

//  objc_constructInstance(correctBSTClazz, malloc(class_getInstanceSize(correctBSTClazz)));
  assert(correctBSTClazzInstance);
  errs() << "Calling correct class: " << "\n";
  objc_msgSend(correctBSTClazzInstance, sel_registerName("setUp"));

//  sleep(0.5);
//  return 0;
  llvm::LLVMContext llvmContext;

  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "swift_001_minimal_xctestcase_run.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
  assert(objcModule);

  char runnerBitcodeFixturePath[255];
  snprintf(runnerBitcodeFixturePath,
           sizeof(runnerBitcodeFixturePath), "%s/%s", "/opt/CustomXCTestRunner", "CustomXCTestRunner.bc");
  auto runnerBitcodeModule = loadModuleAtPath(runnerBitcodeFixturePath, llvmContext);
  assert(runnerBitcodeModule);

  std::vector<llvm::Function *> staticCtors = getStaticConstructors(objcModule.get());
  errs() << "static constructors: " << staticCtors.size() << "\n";
  for (auto &fptr: staticCtors) {
    errs() << fptr->getName() << "\n";
  }

//  exit(1);
  RTDyldObjectLinkingLayer objectLayer(JITSetup::getMemoryManager());

  std::unique_ptr<TargetMachine> TM(
    EngineBuilder().selectTarget(llvm::Triple(),
                                 "",
                                 "",
                                 SmallVector<std::string, 1>())
  );

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  std::shared_ptr<ObjCResolver> objcResolver = std::make_shared<ObjCResolver>();

  RTDyldObjectLinkingLayer::ObjectPtr objcCompiledModule =
    std::make_shared<object::OwningBinary<object::ObjectFile>>(compiler(*objcModule));
  assert(objcCompiledModule);
  assert(objcCompiledModule->getBinary());
  assert(objcCompiledModule->getBinary()->isMachO());
  std::vector<object::ObjectFile*> objcSet;
  auto objcHandle = objectLayer.addObject(objcCompiledModule, objcResolver).get();
  assert(objcHandle->get());
//  auto objcCompiledModule = compiler(*objcModule);

  Error err = objectLayer.emitAndFinalize(objcHandle);

  char objectFixturePath[255];
  snprintf(objectFixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "swift_001_minimal_xctestcase_run.o");
//  auto objcCompiledModule = getObjectFromDisk(objectFixturePath);

  char runnerFixturePath[255];
  snprintf(runnerFixturePath,
           sizeof(fixturePath),
           "%s/%s", "/opt/CustomXCTestRunner", "CustomXCTestRunner.o");
//  auto runnerCompiledModule = getObjectFromDisk(runnerFixturePath);
//  auto runnerCompiledModule = compiler(*runnerBitcodeModule);

//  std::vector<object::ObjectFile*> objcSet;

  std::string cacheName("/tmp/_objcmodule.o");
  std::error_code EC;
  raw_fd_ostream outfile(cacheName, EC, sys::fs::F_None);
  outfile.write(objcCompiledModule->getBinary()->getMemoryBufferRef().getBufferStart(),
                objcCompiledModule->getBinary()->getMemoryBufferRef().getBufferSize());
  outfile.close();

//  objcSet.push_back(objcCompiledModule->getBinary());
//  objcSet.push_back(runnerCompiledModule.getBinary());

//  ObjCResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);

//  ObjLayer.emitAndFinalize(objcHandle);

  /**
  {

    std::string functionName = "__T032swift_001_minimal_xctestcase_run15sandboxFunctionyyF";
    errs() << "Running function: " << functionName << "\n";
    JITSymbol symbol = objectLayer.findSymbol(functionName, false);

    void *fpointer =
      reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress().get()));

    if (fpointer == nullptr) {
      errs() << "CustomTestRunner> Can't find pointer to function: "
      << functionName << "\n";
      exit(1);
    }

    auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
    int result;
//    result = runnerFunction();
  }
*/

#define FAST_REQUIRES_RAW_ISA   (1UL<<2)
  assert(FAST_IS_SWIFT == (1UL<<0));
  assert(FAST_DATA_MASK == 0x00007ffffffffff8UL);
  assert(FAST_REQUIRES_RAW_ISA == (1UL<<2));
#define FAST_HAS_DEFAULT_RR     (1UL<<1)
#define RW_HAS_DEFAULT_AWZ    (1<<16)
#define RO_HAS_CXX_STRUCTORS  (1<<2)
#define RO_IS_ARC             (1<<7)

//  Class wrongBSTClazz = objc_getClass("BinarySearchTest");
//  here_swift_class_t *correctBSTOBJCClazz = (__bridge_retained here_swift_class_t *)correctBSTClazz;
//  here_swift_class_t *wrongBSTOBJCClazz = (__bridge_retained here_swift_class_t *)wrongBSTClazz;


//  assert(wrongBSTClazz);
//
//  id rawWrongInstance = objc_msgSend(wrongBSTClazz, @selector(alloc));
//  id wrongInstance = objc_msgSend(rawWrongInstance, @selector(init));
//  assert(wrongInstance);

//  wrongBSTOBJCClazz->flags = correctBSTOBJCClazz->flags;
//  wrongBSTOBJCClazz->instanceSize = correctBSTOBJCClazz->instanceSize;
//  wrongBSTOBJCClazz->classSize = correctBSTOBJCClazz->classSize;
//  assert(correctBSTOBJCClazz->bits.bits == wrongBSTOBJCClazz->bits.bits);

//  wrongBSTOBJCClazz->bits.setBits(RO_IS_ARC);
//  wrongBSTOBJCClazz->bits.setBits(FAST_IS_SWIFT);
//  assert(correctBSTOBJCClazz->bits.bits & FAST_IS_SWIFT);
//  assert(wrongBSTOBJCClazz->bits.bits & FAST_IS_SWIFT);
//
//  assert(correctBSTOBJCClazz->bits.bits & FAST_DATA_MASK);
//  assert(wrongBSTOBJCClazz->bits.bits & FAST_DATA_MASK);
//
//  assert((correctBSTOBJCClazz->bits.bits & FAST_REQUIRES_RAW_ISA) == 0);
//  assert((wrongBSTOBJCClazz->bits.bits & FAST_REQUIRES_RAW_ISA) == 0);
//
//  assert((correctBSTOBJCClazz->bits.bits & RO_HAS_CXX_STRUCTORS) == 0);
//  assert((wrongBSTOBJCClazz->bits.bits & RO_HAS_CXX_STRUCTORS) == 0);

  /* FLAKY BITS
//  assert((correctBSTOBJCClazz->bits.bits & RW_HAS_DEFAULT_AWZ) == 0);
//  assert((wrongBSTOBJCClazz->bits.bits & RW_HAS_DEFAULT_AWZ) == 0);
//  assert((correctBSTOBJCClazz->bits.bits & FAST_HAS_DEFAULT_RR) == 0);
//  assert((wrongBSTOBJCClazz->bits.bits & FAST_HAS_DEFAULT_RR) == 0);
   */

//  void *pointer = (void *)((((uintptr_t)correctBSTClazzInstance) & *swift_isaMask) + 0x68);
//  void (*funcPtr)(void *, SEL) = (void (*)(void *, SEL))pointer;
//  funcPtr(correctBSTClazzInstance, sel_registerName("setUp"));

//  objc_msgSend(wrongInstance, sel_registerName("setUp"));
//  objc_msgSend(wrongInstance, sel_registerName("setUp"));

  {
    void *runnerPtr = sys::DynamicLibrary::SearchForAddressOfSymbol("CustomXCTestRunnerRun");
    errs() << "runnerPtr: " << runnerPtr << "\n";
    auto runnerFPtr = ((int (*)(void))runnerPtr);
    int result = runnerFPtr();
    ASSERT_EQ(result, 0);
  }
}
