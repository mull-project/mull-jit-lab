#include "ObjCResolver.h"

#include <llvm/ExecutionEngine/RTDyldMemoryManager.h>
#include <llvm/Support/raw_ostream.h>

using namespace llvm;

extern "C" int objc_printf( const char * format, ... ) {
  errs() << "**** objc_printf ****" << "\n";

  va_list arguments;
  va_start(arguments, format);
  int res = vprintf(format, arguments);
  va_end(arguments);

  return res;
}

RuntimeDyld::SymbolInfo ObjCResolver::findSymbol(const std::string &Name) {
    //errs() << "ObjCResolver::findSymbol> " << Name << "\n";
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

RuntimeDyld::SymbolInfo
ObjCResolver::findSymbolInLogicalDylib(const std::string &Name) {
    //errs() << "ObjCResolver::findSymbolInLogicalDylib> " << Name << "\n";

  return RuntimeDyld::SymbolInfo(nullptr);
}
