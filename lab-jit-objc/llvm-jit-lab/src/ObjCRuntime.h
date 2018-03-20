
#pragma once

#include "llvm/Support/raw_ostream.h"

#include <dlfcn.h>

#include <objc/objc.h>
#include <objc/runtime.h>

#include <mach-o/getsect.h>
#include <mach-o/dyld.h>

#include <sstream>
#include <iostream>
#include <iomanip>
#include <string>
#include <queue>

using namespace llvm;

bool mull_isClassRegistered(Class cls);

Class class_getClassByName(const char *name);

void mull_dumpObjcMethods(Class clz);

bool isValidPointer(void *ptr);

#pragma mark - Objective-C Mach-O Types

struct method64_t {
  uint64_t name;  /* SEL (64-bit pointer) */
  uint64_t types; /* const char * (64-bit pointer) */
  uint64_t imp;   /* IMP (64-bit pointer) */

  std::string getDebugDescription(int level = 0) const {
    std::ostringstream os;
    std::string padding = std::string(level * 4, ' ');

    os << padding << "[method_list64_t]\n";
    os << padding << "\t" << "name: " << (char *)name << "\n";
    os << padding << "\t" << "types: " << (char *)types << "\n";
    os << padding << "\t" << "imp: " << (void *)imp << "\n";

    return os.str();
  }
};

struct method_list64_t {
  uint32_t entsize;
  uint32_t count;
  /* struct method64_t first;  These structures follow inline */

  method64_t *getFirstMethodPointer() const {
    return (method64_t *)(this + 1);
  }

  std::string getDebugDescription(int level = 0) const {
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
};

struct class_ro64_t {
  uint32_t flags;
  uint32_t instanceStart;
  uint32_t instanceSize;
  uint32_t reserved;
  uint64_t ivarLayout;     // const uint8_t * (64-bit pointer)
  const char *name;           // const char * (64-bit pointer)
  uint64_t baseMethods;    // const method_list_t * (64-bit pointer)
  uint64_t baseProtocols;  // const protocol_list_t * (64-bit pointer)
  uint64_t ivars;          // const ivar_list_t * (64-bit pointer)
  uint64_t weakIvarLayout; // const uint8_t * (64-bit pointer)
  uint64_t baseProperties; // const struct objc_property_list (64-bit pointer)

  bool isMetaClass() const {
    return (flags & 0x1) == 1;
  }

  char *getName() const {
    return (char *)name;
  }

  method_list64_t *getMethodListPtr() const {
    return (method_list64_t *)baseMethods;
  }

  std::string getDebugDescription(int level = 0) const {
    std::ostringstream os;
    std::string padding = std::string(level * 8, ' ');

    if (isValidPointer((void *)name) == false ||
        isValidPointer((void *)baseMethods) == false) {
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
  }};

struct class64_t {
  class64_t *isa;        // class64_t * (64-bit pointer)
  class64_t *superclass; // class64_t * (64-bit pointer)
  uint64_t cache;      // Cache (64-bit pointer)
  uint64_t vtable;     // IMP * (64-bit pointer)
  class_ro64_t *data;       // class_ro64_t * (64-bit pointer)

  class64_t *getIsaPointer() const {
    return (class64_t *)isa;
  }
  class64_t *getSuperclassPointer() const {
    return (class64_t *)superclass;
  }
  class_ro64_t *getDataPointer() const {
    return (class_ro64_t *)data;
  }

  std::string getDebugDescription(int level = 0) const {
    std::ostringstream os;
    std::string padding = std::string(level * 8, ' ');

    os << padding << "[class64_t]" << "\n";
    os << padding << "this: " << (void *)this << "\n";
    os << padding << "isa: " << (void *)isa << "\n";
    if (isValidPointer(getIsaPointer())) {
      os << getIsaPointer()->getDebugDescription(level + 1);
    }
    os << padding << "superclass: " << (void **)&superclass << "/" << (void *)superclass << "\n";
    if (isValidPointer(getSuperclassPointer())) {
      class64_t *superclassPointer = getSuperclassPointer();
      os << superclassPointer->getDebugDescription(level + 1);
    }
    if (isValidPointer((void *)cache)) {
      os << padding << "cache: " << (void **)&cache << "/" << (void *)cache << "\n";
    }
    if (isValidPointer((void *)vtable)) {
      os << padding << "vtable: " << (void **)&vtable << "/" << (void *)vtable << "\n";
    }

    os << padding << "data: " << (void **)&data << "/" << (void *)data << "\n";
    if (isValidPointer((void *)data)) {
      os << getDataPointer()->getDebugDescription(level + 1);
    }

    return os.str();
  }
};

#pragma mark -

namespace mull { namespace objc {

class Runtime {
  std::queue<class64_t *> classesToRegister;

  void registerOneClass(class64_t *isaPtr, Class superclass);


public:
  void registerSelectors(void *selRefsSectionPtr,
                         uintptr_t selRefsSectionSize);

  void addClassesFromSection(void *sectionPtr,
                             uintptr_t sectionSize);

  void registerClasses();
};

} }
