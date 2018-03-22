#include <objc/runtime.h>

#include <iostream>
#include <iomanip>
#include <string>
#include <sstream>

#pragma mark - Objective-C Mach-O Types

static bool isValidPointer(void *ptr) {
  return (ptr != NULL) &&
  ((uintptr_t)ptr > 0x1000) &&
  ((uintptr_t)ptr < 0x7fffffffffff);
}

struct method64_t {
  SEL name;  /* SEL (64-bit pointer) */
  const char *types; /* const char * (64-bit pointer) */
  uint64_t imp;   /* IMP (64-bit pointer) */

  std::string getDebugDescription(int level = 0) const {
    std::ostringstream os;
    std::string padding = std::string(level * 4, ' ');

    os << padding << "[method_list64_t]\n";
    os << padding << "\t" << "name: " << sel_getName(name) << "\n";
    os << padding << "\t" << "types: " << (char *)types << "\n";
    os << padding << "\t" << "imp: " <<  (void **)&imp << "/" << (void *)imp << "\n";

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

struct ivar_list64_t {
  uint32_t entsize;
  uint32_t count;
  /* struct ivar64_t first;  These structures follow inline */
};

struct ivar64_t {
  uint64_t offset; /* uintptr_t * (64-bit pointer) */
  const char *name;   /* const char * (64-bit pointer) */
  const char *type;   /* const char * (64-bit pointer) */
  uint32_t alignment;
  uint32_t size;
};

struct objc_property64 {
  const char *name;       /* const char * (64-bit pointer) */
  const char *attributes; /* const char * (64-bit pointer) */
};

struct objc_property_list64 {
  uint32_t entsize;
  uint32_t count;
  /* struct objc_property64 first;  These structures follow inline */
};

struct class_ro64_t {
  uint32_t flags;
  uint32_t instanceStart;
  uint32_t instanceSize;
  uint32_t reserved;
  uint64_t ivarLayout;     // const uint8_t * (64-bit pointer)
  const char *name;           // const char * (64-bit pointer)
  method_list64_t *baseMethods;    // const method_list_t * (64-bit pointer)
  uint64_t baseProtocols;  // const protocol_list_t * (64-bit pointer)
  const ivar_list64_t *ivars;          // const ivar_list_t * (64-bit pointer)
  uint64_t weakIvarLayout; // const uint8_t * (64-bit pointer)
  const struct objc_property_list64 *baseProperties; // const struct objc_property_list (64-bit pointer)

  bool isMetaClass() const {
    return (flags & 0x1) == 1;
  }

  char *getName() const {
    return (char *)name;
  }

  method_list64_t *getMethodListPtr() const {
    return baseMethods;
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

