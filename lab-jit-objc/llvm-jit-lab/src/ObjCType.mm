#include "ObjCType.h"

#include "ObjCRuntimeHelpers.h"

#include <iostream>
#include <iomanip>
#include <string>
#include <sstream>

namespace mull { namespace objc {

std::string method64_t::getDebugDescription(int level) const {
  std::ostringstream os;
  std::string padding = std::string(level * 4, ' ');

  os << padding << "[method_list64_t]\n";
  os << padding << "\t" << "name: " << sel_getName(name) << "\n";
  os << padding << "\t" << "types: " << (char *)types << "\n";
  os << padding << "\t" << "imp: " <<  (void **)&imp << "/" << (void *)imp << "\n";

  return os.str();
}

std::string method_list64_t::getDebugDescription(int level) const {
  std::ostringstream os;
  std::string padding = std::string(level * 8, ' ');

  if (count > 100 || entsize == 0) {
    os << padding << "[error]" << "\n";
    return os.str();
  }

  os << padding << "[method_list64_t]\n";
  os << padding << "entsize: " << entsize << "\n";
  os << padding << "count: " << count << "\n";
  for (uint32_t i = 0; i < count; i++) {
    method64_t *method = getFirstMethodPointer() + i;
    os << method->getDebugDescription(level + 1);
  }

  return os.str();
}

std::string class_ro64_t::getDebugDescription(int level) const {
  std::ostringstream os;
  std::string padding = std::string(level * 8, ' ');

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

std::string class64_t::getDebugDescription(int level) const {
  std::ostringstream os;
  std::string padding = std::string(level * 8, ' ');

  os << padding << "[class64_t]" << "\n";
  os << padding << "this: " << (void *)this << "\n";
  os << padding << "isa: " << (void *)isa << "\n";
  if (RuntimeHelpers::isValidPointer(getIsaPointer())) {
    os << getIsaPointer()->getDebugDescription(level + 1);
  }
  os << padding << "superclass: " << (void **)&superclass << "/" << (void *)superclass << "\n";
  if (RuntimeHelpers::isValidPointer(getSuperclassPointer())) {
    class64_t *superclassPointer = getSuperclassPointer();
    os << superclassPointer->getDebugDescription(level + 1);
  }
  if (RuntimeHelpers::isValidPointer((void *)cache)) {
    os << padding << "cache: " << (void **)&cache << "/" << (void *)cache << "\n";
  }
  if (RuntimeHelpers::isValidPointer((void *)vtable)) {
    os << padding << "vtable: " << (void **)&vtable << "/" << (void *)vtable << "\n";
  }

  os << padding << "data: " << (void **)&data << "/" << (void *)data << "\n";
  if (RuntimeHelpers::isValidPointer((void *)data)) {
    os << getDataPointer()->getDebugDescription(level + 1);
  }

  return os.str();
}

} }

