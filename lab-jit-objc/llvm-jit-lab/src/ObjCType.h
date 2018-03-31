#pragma once

#include <objc/runtime.h>

#include <string>

namespace mull { namespace objc {

struct method64_t {
  SEL name;  /* SEL (64-bit pointer) */
  const char *types; /* const char * (64-bit pointer) */
  uint64_t imp;   /* IMP (64-bit pointer) */

  std::string getDebugDescription(int level = 0) const;
};

struct method_list64_t {
  uint32_t entsize;
  uint32_t count;
  /* struct method64_t first;  These structures follow inline */

  const method64_t *getFirstMethodPointer() const {
    return (const method64_t *)(this + 1);
  }

  std::string getDebugDescription(int level = 0) const;
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

  const char *getName() const {
    return (const char *)name;
  }

  method_list64_t *getMethodListPtr() const {
    return baseMethods;
  }
  
  std::string getDebugDescription(int level = 0) const;
};

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
    #define FAST_DATA_MASK          0x00007ffffffffff8UL

    return (class_ro64_t *)((uintptr_t)data & FAST_DATA_MASK);
//    return (class_ro64_t *)data;
  }

  std::string getDebugDescription(int level = 0) const;
};

} } // namespace mull { namespace objc {

