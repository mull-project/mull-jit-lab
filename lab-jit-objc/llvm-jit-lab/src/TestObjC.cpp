#include "ObjCEnabledMemoryManager.h"

#include <gtest/gtest.h>

#include <llvm/Bitcode/BitcodeReader.h>
#include <llvm/ExecutionEngine/ExecutionEngine.h>
#include <llvm/ExecutionEngine/Orc/CompileUtils.h>
  //#include <llvm/ExecutionEngine/Orc/ObjectLinkingLayer.h>
#include <llvm/ExecutionEngine/Orc/RTDyldObjectLinkingLayer.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/Support/DynamicLibrary.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Support/TargetSelect.h>

#include "ObjCRuntime.h"
#include <objc/runtime.h>
#include <objc/message.h>
#include <memory>

using namespace llvm;
using namespace llvm::orc;

const char *const FixturesPath = "/opt/mull-jit-lab/lab-jit-objc/fixtures/bitcode";

extern "C" int objc_printf( const char * format, ... ) {
  errs() << "**** objc_printf ****" << "\n";

  va_list arguments;
  va_start(arguments, format);
  int res = vprintf(format, arguments);
  va_end(arguments);

  return res;
}

class ObjcResolver : public JITSymbolResolver {
public:
  ObjcResolver() {}

  JITSymbol findSymbol(const std::string &Name) {
    errs() << "ObjcResolver::findSymbol> " << Name << "\n";
    if (Name == "_printf") {
      return
        JITSymbol((uint64_t)objc_printf,
                  JITSymbolFlags::Exported);
    }

    if (auto SymAddr = RTDyldMemoryManager::getSymbolAddressInProcess(Name)) {
      return JITSymbol(SymAddr, JITSymbolFlags::Exported);
    }

    return JITSymbol(nullptr);
  }

  JITSymbol findSymbolInLogicalDylib(const std::string &Name) {
    errs() << "ObjcResolver::findSymbolInLogicalDylib> " << Name << "\n";

    return JITSymbol(nullptr);
  }
};

std::unique_ptr<llvm::Module> loadModuleAtPath(const std::string &path,
                                               llvm::LLVMContext &llvmContext) {

  auto BufferOrError = MemoryBuffer::getFile(path);
  if (!BufferOrError) {
    errs() << "ModuleLoader> Can't load module " << path << '\n';
    return nullptr;
  }
  errs() << "ModuleLoader> module " << path << '\n';

  auto llvmModule = llvm::parseBitcodeFile(BufferOrError->get()->getMemBufferRef(),
                                           llvmContext);

  if (!llvmModule) {
    errs() << "ModuleLoader> Can't load module " << path << '\n';
    return nullptr;
  }

  assert(llvmModule.get());
  return std::move(llvmModule.get());
}

class JITSetup {

public:
  static
  llvm::orc::RTDyldObjectLinkingLayer::MemoryManagerGetter getMemoryManager() {
    llvm::orc::RTDyldObjectLinkingLayer::MemoryManagerGetter GetMemMgr =
    []() {
      return std::make_shared<SectionMemoryManager>();
    };
    return GetMemMgr;
  }

};

#pragma mark - Integration tests

TEST(DISABLED_LLVMJIT, ObjCRegistration) {
  // These lines are needed for TargetMachine TM to be created correctly.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);

  //assert(!sys::DynamicLibrary::LoadLibraryPermanently("/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"));
  assert(!sys::DynamicLibrary::LoadLibraryPermanently("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest"));
  assert(!sys::DynamicLibrary::LoadLibraryPermanently("/opt/MUT_XCTestDriver.dylib"));

  llvm::LLVMContext llvmContext;

  auto objcModule             = loadModuleAtPath("/opt/jitobjc.bc",   llvmContext);
  auto mutatedSomeClassModule = loadModuleAtPath("/opt/SomeClass.bc", llvmContext);

  RTDyldObjectLinkingLayer objectLayer(JITSetup::getMemoryManager());

  std::unique_ptr<TargetMachine> TM(
    EngineBuilder().selectTarget(llvm::Triple(), "", "",
    SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  RTDyldObjectLinkingLayer::ObjectPtr objcCompiledModule =
    std::make_shared<object::OwningBinary<object::ObjectFile>>(compiler(*objcModule));
  object::OwningBinary<object::ObjectFile> mutatedSomeClassCompiledModule =
    compiler(*mutatedSomeClassModule);

  std::shared_ptr<ObjcResolver> objcResolver;

  auto objcHandle = objectLayer.addObject(objcCompiledModule,
                                          objcResolver).get();

  Error err = objectLayer.emitAndFinalize(objcHandle);
  if (err) {
    errs() << "Failed to emitAndFinalize." << "\n";
    exit(1);
  }

  std::string functionName = "_objc_function";
  JITSymbol symbol = objectLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress().get()));

  if (fpointer == nullptr) {
    errs() << "CustomTestRunner> Can't find pointer to function: "
    << functionName << "\n";
    exit(1);
  }

  void *mainPointer = fpointer;
  auto objcFunction = ((void (*)(void))(intptr_t)mainPointer);

  objcFunction();
//  objcFunction();
//  objcFunction();
//  objcFunction();
//  objcFunction();
//  objcFunction();
//  objcFunction();
//  objcFunction();
//  objcFunction();
}

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

void loadSwiftLibrariesOrExit() {
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

TEST(LLVMJIT, SwiftWIP) {
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
    "/Users/Stanislaw/rootstanislaw/projects/CustomXCTestRunner/CustomXCTestRunner.dylib"
  ));

  loadSwiftLibrariesOrExit();

  llvm::LLVMContext llvmContext;

  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "swift_001_minimal_xctestcase_run.bc");
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "002_calling_class_method.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);

  assert(objcModule);
  RTDyldObjectLinkingLayer objectLayer(JITSetup::getMemoryManager());

  std::unique_ptr<TargetMachine> TM(
                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);
  std::shared_ptr<ObjcResolver> objcResolver;

  RTDyldObjectLinkingLayer::ObjectPtr objcCompiledModule =
    std::make_shared<object::OwningBinary<object::ObjectFile>>(compiler(*objcModule));

  auto objcHandle = objectLayer.addObject(objcCompiledModule,
                                          objcResolver).get();

  Error err = objectLayer.emitAndFinalize(objcHandle);
  if (err) {
    errs() << "Failed to emitAndFinalize." << "\n";
    exit(1);
  }


////  assert(objc_getClass("_TtC32swift_001_minimal_xctestcase_run14SwiftObjCClass"));
//
//  Class clz = objc_getClass("SwiftObjCClass_Parent");
//  id instance = class_createInstance(clz, 0);
//  assert(instance);
//  objc_msgSend(instance, sel_registerName("testHello"));
//
//  return;
  void *runnerPtr = sys::DynamicLibrary::SearchForAddressOfSymbol("CustomXCTestRunnerRun");
  auto runnerFPtr = ((int (*)(void))runnerPtr);
  runnerFPtr();
  return;
  std::string functionName = "_runnnn";
  JITSymbol symbol = objectLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress().get()));

  if (fpointer == nullptr) {
    errs() << "CustomTestRunner> Can't find pointer to function: "
    << functionName << "\n";
    exit(1);
  }

  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);

  int result = runnerFunction();
  EXPECT_EQ(result, 1234);
}

//TEST(LLVMJIT, XCTestObjCWIP) {
//    // These lines are needed for TargetMachine TM to be created correctly.
//  llvm::InitializeNativeTarget();
//  llvm::InitializeNativeTargetAsmPrinter();
//  llvm::InitializeNativeTargetAsmParser();
//
//  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
//
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
//                                                      ));
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//                                                      "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework/XCTest"
//                                                      ));
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//                                                      "/Users/Stanislaw/rootstanislaw/projects/CustomXCTestRunner/CustomXCTestRunner.dylib"
//                                                      ));
//
////  loadSwiftLibrariesOrExit();
//
//  llvm::LLVMContext llvmContext;
//
//  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "xctest_objc_001_minimal_xctestcase_run.bc");
//
//  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
//
//  ObjectLinkingLayer<> ObjLayer;
//
//  std::unique_ptr<TargetMachine> TM(
//                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));
//
//  assert(TM.get());
//
//  SimpleCompiler compiler(*TM);
//
//  auto objcCompiledModule = compiler(*objcModule);
//
//  std::vector<object::ObjectFile*> objcSet;
//  objcSet.push_back(objcCompiledModule.getBinary());
//
//  ObjcResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);
//
//  ObjLayer.emitAndFinalize(objcHandle);
//
//    //  assert(objc_getClass("_TtC32swift_001_minimal_xctestcase_run14SwiftObjCClass"));
//
////  Class clz = objc_getClass("SwiftObjCClass");
////  id instance = class_createInstance(clz, 0);
////  assert(instance);
////  objc_msgSend(instance, sel_registerName("testHello"));
//
//  void *runnerPtr = sys::DynamicLibrary::SearchForAddressOfSymbol("CustomXCTestRunnerRun");
//  auto runnerFPtr = ((int (*)(void))runnerPtr);
//  runnerFPtr();
//
//  return;
//  std::string functionName = "_runnnn";
//  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);
//
//  void *fpointer =
//  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));
//
//  if (fpointer == nullptr) {
//    errs() << "CustomTestRunner> Can't find pointer to function: "
//    << functionName << "\n";
//    exit(1);
//  }
//
//  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
//
//  int result = runnerFunction();
//  EXPECT_EQ(result, 1234);
//}
//
//#pragma mark - Unit tests
//
//TEST(LLVMJIT, Test001_BasicTest) {
//  // These lines are needed for TargetMachine TM to be created correctly.
//  llvm::InitializeNativeTarget();
//  llvm::InitializeNativeTargetAsmPrinter();
//  llvm::InitializeNativeTargetAsmParser();
//
//  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
//
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//    "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
//  ));
//
//  llvm::LLVMContext llvmContext;
//
//  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "001_minimal_test.bc");
//
//  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
//
//  ObjectLinkingLayer<> ObjLayer;
//
//  std::unique_ptr<TargetMachine> TM(
//    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));
//
//  assert(TM.get());
//
//  SimpleCompiler compiler(*TM);
//
//  auto objcCompiledModule = compiler(*objcModule);
//
//  std::vector<object::ObjectFile*> objcSet;
//  objcSet.push_back(objcCompiledModule.getBinary());
//
//  ObjcResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);
//
//  ObjLayer.emitAndFinalize(objcHandle);
//
//  std::string functionName = "_run";
//  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);
//
//  void *fpointer =
//  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));
//
//  if (fpointer == nullptr) {
//    errs() << "CustomTestRunner> Can't find pointer to function: "
//    << functionName << "\n";
//    exit(1);
//  }
//
//  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
//
//  int result = runnerFunction();
//  EXPECT_EQ(result, 1234);
//}
//
//TEST(LLVMJIT, Test002_ClassMethodCall) {
//  // These lines are needed for TargetMachine TM to be created correctly.
//  llvm::InitializeNativeTarget();
//  llvm::InitializeNativeTargetAsmPrinter();
//  llvm::InitializeNativeTargetAsmParser();
//
//  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
//
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
//                                                      ));
//
//  llvm::LLVMContext llvmContext;
//
//  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "002_calling_class_method.bc");
//
//  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
//
//  ObjectLinkingLayer<> ObjLayer;
//
//  std::unique_ptr<TargetMachine> TM(
//                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));
//
//  assert(TM.get());
//
//  SimpleCompiler compiler(*TM);
//
//  auto objcCompiledModule = compiler(*objcModule);
//
//  std::vector<object::ObjectFile*> objcSet;
//  objcSet.push_back(objcCompiledModule.getBinary());
//
//  ObjcResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);
//
//  ObjLayer.emitAndFinalize(objcHandle);
//
//  std::string functionName = "_run";
//  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);
//
//  void *fpointer =
//  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));
//
//  if (fpointer == nullptr) {
//    errs() << "CustomTestRunner> Can't find pointer to function: "
//    << functionName << "\n";
//    exit(1);
//  }
//
//  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
//
//  int result = runnerFunction();
//  EXPECT_EQ(result, 1234);
//}
//
//TEST(LLVMJIT, Test003_CallingASuperMethodOnInstance) {
//  // These lines are needed for TargetMachine TM to be created correctly.
//  llvm::InitializeNativeTarget();
//  llvm::InitializeNativeTargetAsmPrinter();
//  llvm::InitializeNativeTargetAsmParser();
//
//  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
//
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
//                                                      ));
//
//  llvm::LLVMContext llvmContext;
//
//  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "003_calling_a_super_method_on_instance.bc");
//
//  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
//
//  ObjectLinkingLayer<> ObjLayer;
//
//  std::unique_ptr<TargetMachine> TM(
//                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));
//
//  assert(TM.get());
//
//  SimpleCompiler compiler(*TM);
//
//  auto objcCompiledModule = compiler(*objcModule);
//
//  std::vector<object::ObjectFile*> objcSet;
//  objcSet.push_back(objcCompiledModule.getBinary());
//
//  ObjcResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);
//
//  ObjLayer.emitAndFinalize(objcHandle);
//
//  std::string functionName = "_run";
//  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);
//
//  void *fpointer =
//  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));
//
//  if (fpointer == nullptr) {
//    errs() << "CustomTestRunner> Can't find pointer to function: "
//    << functionName << "\n";
//    exit(1);
//  }
//
//  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
//
//  int result = runnerFunction();
//  EXPECT_EQ(result, 111);
//}
//
//TEST(LLVMJIT, Test004_CallingASuperMethodOnClass) {
//    // These lines are needed for TargetMachine TM to be created correctly.
//  llvm::InitializeNativeTarget();
//  llvm::InitializeNativeTargetAsmPrinter();
//  llvm::InitializeNativeTargetAsmParser();
//
//  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
//
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
//                                                      ));
//
//  llvm::LLVMContext llvmContext;
//
//  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "004_calling_a_super_method_on_class.bc");
//
//  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
//
//  ObjectLinkingLayer<> ObjLayer;
//
//  std::unique_ptr<TargetMachine> TM(
//                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));
//
//  assert(TM.get());
//
//  SimpleCompiler compiler(*TM);
//
//  auto objcCompiledModule = compiler(*objcModule);
//
//  std::vector<object::ObjectFile*> objcSet;
//  objcSet.push_back(objcCompiledModule.getBinary());
//
//  ObjcResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);
//
//  ObjLayer.emitAndFinalize(objcHandle);
//
//  std::string functionName = "_run";
//  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);
//
//  void *fpointer =
//  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));
//
//  if (fpointer == nullptr) {
//    errs() << "CustomTestRunner> Can't find pointer to function: "
//    << functionName << "\n";
//    exit(1);
//  }
//
//  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
//
//  int result = runnerFunction();
//  EXPECT_EQ(result, 111);
//}
//
//TEST(LLVMJIT, Test005_IvarsOfClassAndSuperclass) {
//    // These lines are needed for TargetMachine TM to be created correctly.
//  llvm::InitializeNativeTarget();
//  llvm::InitializeNativeTargetAsmPrinter();
//  llvm::InitializeNativeTargetAsmParser();
//
//  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
//
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//    "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
//  ));
//
//  llvm::LLVMContext llvmContext;
//
//  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "005_ivars_of_class_and_superclass.bc");
//
//  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
//
//  ObjectLinkingLayer<> ObjLayer;
//
//  std::unique_ptr<TargetMachine> TM(
//    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));
//
//  assert(TM.get());
//
//  SimpleCompiler compiler(*TM);
//
//  auto objcCompiledModule = compiler(*objcModule);
//
//  std::vector<object::ObjectFile*> objcSet;
//  objcSet.push_back(objcCompiledModule.getBinary());
//
//  ObjcResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);
//
//  ObjLayer.emitAndFinalize(objcHandle);
//
//  std::string functionName = "_run";
//  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);
//
//  void *fpointer =
//  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));
//
//  if (fpointer == nullptr) {
//    errs() << "CustomTestRunner> Can't find pointer to function: "
//    << functionName << "\n";
//    exit(1);
//  }
//
//  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
//
//  int result = runnerFunction();
//  EXPECT_EQ(result, 1111);
//}
//
//TEST(LLVMJIT, Test006_PropertiesOfClassAndSuperclass) {
//    // These lines are needed for TargetMachine TM to be created correctly.
//  llvm::InitializeNativeTarget();
//  llvm::InitializeNativeTargetAsmPrinter();
//  llvm::InitializeNativeTargetAsmParser();
//
//  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);
//
//  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
//                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
//                                                      ));
//
//  llvm::LLVMContext llvmContext;
//
//  char fixturePath[255];
//  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "006_properties_of_class_and_superclass.bc");
//
//  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);
//
//  ObjectLinkingLayer<> ObjLayer;
//
//  std::unique_ptr<TargetMachine> TM(
//                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));
//
//  assert(TM.get());
//
//  SimpleCompiler compiler(*TM);
//
//  auto objcCompiledModule = compiler(*objcModule);
//
//  std::vector<object::ObjectFile*> objcSet;
//  objcSet.push_back(objcCompiledModule.getBinary());
//
//  ObjcResolver objcResolver;
//  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
//                                          make_unique<ObjCEnabledMemoryManager>(),
//                                          &objcResolver);
//
//  ObjLayer.emitAndFinalize(objcHandle);
//
//  std::string functionName = "_run";
//  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);
//
//  void *fpointer =
//  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));
//
//  if (fpointer == nullptr) {
//    errs() << "CustomTestRunner> Can't find pointer to function: "
//    << functionName << "\n";
//    exit(1);
//  }
//
//  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);
//
//  int result = runnerFunction();
//  EXPECT_EQ(result, 1111);
//}
