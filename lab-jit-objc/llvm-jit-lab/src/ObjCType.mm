#include "ObjCType.h"

#include "ObjCRuntimeHelpers.h"
#include "DebugUtils.h"

#include <llvm/Support/raw_ostream.h>

#include <iostream>
#include <iomanip>
#include <string>
#include <sstream>

using namespace llvm;

namespace mull { namespace objc {

  std::string method64_t::getDebugDescription(int level) const {
    std::ostringstream os;
    std::string padding = std::string(level * 4, ' ');

    os << padding << "[method64_t]\n";
    os << padding << "\t" << "name: " << sel_getName(name) << "\n";
    os << padding << "\t" << "types: " << (const char *)types << "\n";
    os << padding << "\t" << "imp: " <<  (const void * const *)&imp << " / " << (const void *)imp << " / " << to_hex16(imp) << "\n";

    return os.str();
  }

  std::string method_list64_t::getDebugDescription(int level) const {
    std::ostringstream os;
    std::string padding = std::string(level * 4, ' ');

    if (count > 100 || entsize == 0) {
      os << padding << "[error]" << "\n";
      return os.str();
    }

    os << padding << "[method_list64_t]\n";
    os << padding << "entsize: " << entsize << "\n";
    os << padding << "count: " << count << "\n";
    for (uint32_t i = 0; i < count; i++) {
      const method64_t *method = getFirstMethodPointer() + i;
      os << method->getDebugDescription(level + 1);
    }

    return os.str();
  }

  std::string class_ro64_t::getDebugDescription(int level) const {
    std::ostringstream os;
    std::string padding = std::string(level * 4, ' ');

    if (RuntimeHelpers::isValidPointer((void *)name) == false ||
        RuntimeHelpers::isValidPointer((void *)baseMethods) == false) {
      os << padding << "[error]" << "\n";
      return os.str();
    }

    os << padding << "[class_ro64_t] (metaclass: " << (isMetaClass() ? "yes" : "no") << ")\n";
    os << padding << "name: " << getName() << "\n";
    os << padding << "baseMethods: " << (void *)baseMethods << "\n";
    if (method_list64_t *methodListPointer = getMethodListPtr()) {
      os << methodListPointer->getDebugDescription(level + 1);
    }

    return os.str();
  }

  std::string class64_t::getDebugDescription(Description level) const {
    std::ostringstream os;
    std::string padding = std::string(level * 4, ' ');

    os << padding << "[class64_t]" << "\n";
    os << padding << "this: " << (void *)this << " / " << to_hex16(this) << "\n";
    os << padding << "isa: " << (void *)isa << "\n";
    if (level == Clazz && RuntimeHelpers::isValidPointer(getIsaPointer())) {
      os << getIsaPointer()->getDebugDescription(IsaOrSuperclass);
    }
    os << padding << "superclass: " << (void *const *)&superclass << "/" << (void *)superclass << "\n";
    if (level == Clazz &&
        RuntimeHelpers::isValidPointer(getSuperclassPointer())) {

      Class superClz = (Class)getSuperclassPointer();
      if (RuntimeHelpers::class_isRegistered(superClz)) {
        os << padding << "\t(registered) " << object_getClassName(superClz) << "\n";
      } else {
        class64_t *superclassPointer = getSuperclassPointer();
        os << superclassPointer->getDebugDescription(IsaOrSuperclass);
      }
    }
    if (RuntimeHelpers::isValidPointer((void *)cache)) {
      os << padding << "cache: " << (void *const *)&cache << "/" << (void *)cache << "\n";
    }
    if (RuntimeHelpers::isValidPointer((void *)vtable)) {
      os << padding << "vtable: " << (void *const *)&vtable << "/" << (void *)vtable << "\n";
    }

    os << padding << "data: " << (void *const *)&data << "/" << (void *)data << "\n";
    if (RuntimeHelpers::isValidPointer((void *)data)) {
      auto dataPtr = getDataPointer();
      os << dataPtr->getDebugDescription(level + 1);
    }

    return os.str();
  }

} }

