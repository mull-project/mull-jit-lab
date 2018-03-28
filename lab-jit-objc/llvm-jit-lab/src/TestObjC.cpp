#include "ObjCEnabledMemoryManager.h"

#include <gtest/gtest.h>

#include <llvm/Bitcode/ReaderWriter.h>
#include <llvm/ExecutionEngine/Orc/CompileUtils.h>
#include <llvm/ExecutionEngine/Orc/ObjectLinkingLayer.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/Support/DynamicLibrary.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Support/TargetSelect.h>

#include "ObjCRuntime.h"

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

class ObjcResolver : public RuntimeDyld::SymbolResolver {
public:
  ObjcResolver() {}

  RuntimeDyld::SymbolInfo findSymbol(const std::string &Name) {
    //errs() << "ObjcResolver::findSymbol> " << Name << "\n";
    if (Name == "_printf") {
      return
        RuntimeDyld::SymbolInfo((uint64_t)objc_printf,
                                JITSymbolFlags::Exported);
    }

    if (auto SymAddr = RTDyldMemoryManager::getSymbolAddressInProcess(Name)) {
      return RuntimeDyld::SymbolInfo(SymAddr, JITSymbolFlags::Exported);
    }

    return RuntimeDyld::SymbolInfo(nullptr);
  }

  RuntimeDyld::SymbolInfo findSymbolInLogicalDylib(const std::string &Name) {
    //errs() << "ObjcResolver::findSymbolInLogicalDylib> " << Name << "\n";

    return RuntimeDyld::SymbolInfo(nullptr);
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

  return std::move(llvmModule.get());
}

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

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
    EngineBuilder().selectTarget(llvm::Triple(), "", "",
    SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto objcCompiledModule = compiler(*objcModule);
  auto mutatedSomeClassCompiledModule = compiler(*mutatedSomeClassModule);


  std::vector<object::ObjectFile*> objcSet;
  object::ObjectFile *someClassObject = mutatedSomeClassCompiledModule.getBinary();

  objcSet.push_back(someClassObject);
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjcResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  std::string functionName = "_objc_function";
  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));

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

TEST(LLVMJIT, Test001_BasicTest) {
  // These lines are needed for TargetMachine TM to be created correctly.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);

  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
    "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
  ));

  llvm::LLVMContext llvmContext;

  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "001_minimal_test.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto objcCompiledModule = compiler(*objcModule);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjcResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  std::string functionName = "_run";
  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));

  if (fpointer == nullptr) {
    errs() << "CustomTestRunner> Can't find pointer to function: "
    << functionName << "\n";
    exit(1);
  }

  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);

  int result = runnerFunction();
  EXPECT_EQ(result, 1234);
}

TEST(LLVMJIT, Test002_ClassMethodCall) {
  // These lines are needed for TargetMachine TM to be created correctly.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);

  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
                                                      ));

  llvm::LLVMContext llvmContext;

  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "002_calling_class_method.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto objcCompiledModule = compiler(*objcModule);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjcResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  std::string functionName = "_run";
  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));

  if (fpointer == nullptr) {
    errs() << "CustomTestRunner> Can't find pointer to function: "
    << functionName << "\n";
    exit(1);
  }

  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);

  int result = runnerFunction();
  EXPECT_EQ(result, 1234);
}

TEST(LLVMJIT, Test003_CallingASuperMethodOnInstance) {
  // These lines are needed for TargetMachine TM to be created correctly.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);

  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
                                                      ));

  llvm::LLVMContext llvmContext;

  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "003_calling_a_super_method_on_instance.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto objcCompiledModule = compiler(*objcModule);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjcResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  std::string functionName = "_run";
  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));

  if (fpointer == nullptr) {
    errs() << "CustomTestRunner> Can't find pointer to function: "
    << functionName << "\n";
    exit(1);
  }

  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);

  int result = runnerFunction();
  EXPECT_EQ(result, 111);
}

TEST(LLVMJIT, Test004_CallingASuperMethodOnClass) {
    // These lines are needed for TargetMachine TM to be created correctly.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);

  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
                                                      "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
                                                      ));

  llvm::LLVMContext llvmContext;

  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "004_calling_a_super_method_on_class.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto objcCompiledModule = compiler(*objcModule);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjcResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  std::string functionName = "_run";
  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));

  if (fpointer == nullptr) {
    errs() << "CustomTestRunner> Can't find pointer to function: "
    << functionName << "\n";
    exit(1);
  }

  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);

  int result = runnerFunction();
  EXPECT_EQ(result, 111);
}

TEST(LLVMJIT, Test005_IvarsOfClassAndSuperclass) {
    // These lines are needed for TargetMachine TM to be created correctly.
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::InitializeNativeTargetAsmParser();

  llvm::sys::DynamicLibrary::LoadLibraryPermanently(nullptr);

  assert(!sys::DynamicLibrary::LoadLibraryPermanently(
    "/System/Library/Frameworks/Foundation.framework/Versions/Current/Foundation"
  ));

  llvm::LLVMContext llvmContext;

  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, "005_ivars_of_class_and_superclass.bc");

  auto objcModule = loadModuleAtPath(fixturePath, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
                                    EngineBuilder().selectTarget(llvm::Triple(), "", "", SmallVector<std::string, 1>()));

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto objcCompiledModule = compiler(*objcModule);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(objcCompiledModule.getBinary());

  ObjcResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  std::string functionName = "_run";
  JITSymbol symbol = ObjLayer.findSymbol(functionName, false);

  void *fpointer =
  reinterpret_cast<void *>(static_cast<uintptr_t>(symbol.getAddress()));

  if (fpointer == nullptr) {
    errs() << "CustomTestRunner> Can't find pointer to function: "
    << functionName << "\n";
    exit(1);
  }

  auto runnerFunction = ((int (*)(void))(intptr_t)fpointer);

  int result = runnerFunction();
  EXPECT_EQ(result, 1111);
}
