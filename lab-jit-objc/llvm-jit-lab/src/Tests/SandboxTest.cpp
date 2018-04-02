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

static const char *const FixturesPath = "/Users/Stanislaw/rootstanislaw/projects/Fuzzer";

static std::string getFixturePath(const char *const path) {
  char fixturePath[255];
  snprintf(fixturePath, sizeof(fixturePath), "%s/%s", FixturesPath, path);
  return std::string(fixturePath);
}

TEST(Sandbox, Test001) {
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

  llvm::LLVMContext llvmContext;

  std::string path_RunnerTests = getFixturePath("bitcode/FuzzerTests/Runner/RunnerTests.bc");
  std::string path_Report = getFixturePath("bitcode/Fuzzer/Reports/FZRReport.bc");

  auto module_runnerTests = loadModuleAtPath(path_RunnerTests, llvmContext);
  auto module_report = loadModuleAtPath(path_Report, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
    EngineBuilder().selectTarget(llvm::Triple(),
                                 "",
                                 "",
                                 SmallVector<std::string, 1>())
  );

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto compiledModule_runnerTests = compiler(*module_runnerTests);
  auto compiledModule_report = compiler(*module_report);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(compiledModule_runnerTests.getBinary());
  objcSet.push_back(compiledModule_report.getBinary());

  ObjCResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  void *runnerPtr = sys::DynamicLibrary::SearchForAddressOfSymbol("CustomXCTestRunnerRun");
  auto runnerFPtr = ((int (*)(void))runnerPtr);
  runnerFPtr();
}
