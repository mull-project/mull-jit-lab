#include "ObjCResolver.h"

#include <llvm/ExecutionEngine/RTDyldMemoryManager.h>
#include <llvm/Support/raw_ostream.h>

using namespace llvm;

extern "C" void dummy_abort(void *value) {
  printf("called on object %p\n", value);
  abort();
}

extern "C" int objc_printf( const char * format, ... ) {
  errs() << "**** objc_printf ****" << "\n";

  va_list arguments;
  va_start(arguments, format);
  int res = vprintf(format, arguments);
  va_end(arguments);

  return res;
}
//#define FAST_DATA_MASK
uintptr_t swift_isaMask = 0x00007ffffffffff8UL;

JITSymbol ObjCResolver::findSymbol(const std::string &Name) {
  errs() << "ObjCResolver::findSymbol> " << Name << "\n";
  if (Name == "_printf") {
    return
    JITSymbol((uint64_t)objc_printf,
              JITSymbolFlags::Exported);
  }

//  if (Name == "_objc_retain") {
//    printf("dummy abort address: %p\n", (void *)dummy_abort);
//
//    return JITSymbol((uint64_t)dummy_abort,
//                     JITSymbolFlags::Exported);
//
//  }

  if (Name == "_swift_isaMask") {
    auto si =
      JITSymbol((uint64_t)&swift_isaMask,
                JITSymbolFlags::Exported);

    return si;
  }

  if (auto SymAddr = RTDyldMemoryManager::getSymbolAddressInProcess(Name)) {
    return JITSymbol(SymAddr, JITSymbolFlags::Exported);
  }

  return JITSymbol(nullptr);
}

JITSymbol
ObjCResolver::findSymbolInLogicalDylib(const std::string &Name) {
    //errs() << "ObjCResolver::findSymbolInLogicalDylib> " << Name << "\n";

  return JITSymbol(nullptr);
}
