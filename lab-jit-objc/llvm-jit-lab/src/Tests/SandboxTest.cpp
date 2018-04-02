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

  std::string path_RunnerTests              = getFixturePath("bitcode/FuzzerTests/Runner/RunnerTests.bc");
  std::string path_DeleteNodeMutationTests  = getFixturePath("bitcode/FuzzerTests/Mutations/DeleteNodeMutationTests.bc");
  std::string path_ReplaceNodeMutationTests = getFixturePath("bitcode/FuzzerTests/Mutations/ReplaceNodeMutationTests.bc");

  std::string path_Report              = getFixturePath("bitcode/Fuzzer/Reports/FZRReport.bc");
  std::string path_NodeReplacement     = getFixturePath("bitcode/Fuzzer/Replacements/FZRNodeReplacement.bc");
  std::string path_Runner              = getFixturePath("bitcode/Fuzzer/Runners/FZRRunner.bc");
  std::string path_MutationFactory     = getFixturePath("bitcode//Fuzzer/Factories/FZRMutationFactory.bc");
  std::string path_DeleteNodeMutation  = getFixturePath("bitcode//Fuzzer/Mutations/FZRDeleteNodeMutation.bc");
  std::string path_ReplaceNodeMutation = getFixturePath("bitcode//Fuzzer/Mutations/FZRReplaceNodeMutation.bc");


  auto module_runnerTests              = loadModuleAtPath(path_RunnerTests, llvmContext);
  auto module_ReplaceNodeMutationTests = loadModuleAtPath(path_ReplaceNodeMutationTests, llvmContext);
  auto module_DeleteNodeMutationTests  = loadModuleAtPath(path_DeleteNodeMutationTests, llvmContext);

  auto module_report              = loadModuleAtPath(path_Report, llvmContext);
  auto module_NodeReplacement     = loadModuleAtPath(path_NodeReplacement, llvmContext);
  auto module_Runner              = loadModuleAtPath(path_Runner, llvmContext);
  auto module_MutationFactory     = loadModuleAtPath(path_MutationFactory, llvmContext);
  auto module_DeleteNodeMutation  = loadModuleAtPath(path_DeleteNodeMutation, llvmContext);
  auto module_ReplaceNodeMutation = loadModuleAtPath(path_ReplaceNodeMutation, llvmContext);

  ObjectLinkingLayer<> ObjLayer;

  std::unique_ptr<TargetMachine> TM(
    EngineBuilder().selectTarget(llvm::Triple(),
                                 "",
                                 "",
                                 SmallVector<std::string, 1>())
  );

  assert(TM.get());

  SimpleCompiler compiler(*TM);

  auto compiledModule_runnerTests              = compiler(*module_runnerTests);
  auto compiledModule_ReplaceNodeMutationTests = compiler(*module_ReplaceNodeMutationTests);
  auto compiledModule_DeleteNodeMutationTests  = compiler(*module_DeleteNodeMutationTests);

  auto compiledModule_report              = compiler(*module_report);
  auto compiledModule_NodeReplacement     = compiler(*module_NodeReplacement);
  auto compiledModule_Runner              = compiler(*module_Runner);
  auto compiledModule_MutationFactory     = compiler(*module_MutationFactory);
  auto compiledModule_DeleteNodeMutation  = compiler(*module_DeleteNodeMutation);
  auto compiledModule_ReplaceNodeMutation = compiler(*module_ReplaceNodeMutation);

  std::vector<object::ObjectFile*> objcSet;
  objcSet.push_back(compiledModule_runnerTests.getBinary());
  objcSet.push_back(compiledModule_DeleteNodeMutationTests.getBinary());
  objcSet.push_back(compiledModule_ReplaceNodeMutationTests.getBinary());

  objcSet.push_back(compiledModule_report.getBinary());
  objcSet.push_back(compiledModule_NodeReplacement.getBinary());
  objcSet.push_back(compiledModule_Runner.getBinary());
  objcSet.push_back(compiledModule_MutationFactory.getBinary());
  objcSet.push_back(compiledModule_DeleteNodeMutation.getBinary());
  objcSet.push_back(compiledModule_ReplaceNodeMutation.getBinary());

  ObjCResolver objcResolver;
  auto objcHandle = ObjLayer.addObjectSet(std::move(objcSet),
                                          make_unique<ObjCEnabledMemoryManager>(),
                                          &objcResolver);

  ObjLayer.emitAndFinalize(objcHandle);

  void *runnerPtr = sys::DynamicLibrary::SearchForAddressOfSymbol("CustomXCTestRunnerRun");
  auto runnerFPtr = ((int (*)(void))runnerPtr);
  runnerFPtr();
}
