#pragma once

#include <llvm/ExecutionEngine/RuntimeDyld.h>

class ObjCResolver : public llvm::RuntimeDyld::SymbolResolver {
public:
  ObjCResolver() {}
  llvm::RuntimeDyld::SymbolInfo findSymbol(const std::string &Name);
  llvm::RuntimeDyld::SymbolInfo findSymbolInLogicalDylib(const std::string &Name);
};
