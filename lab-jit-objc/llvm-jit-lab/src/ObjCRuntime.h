
#pragma once

#include "llvm/Support/raw_ostream.h"

#include <dlfcn.h>

#include "ObjCType.h"

#include <objc/objc.h>
#include <objc/message.h>

#include <mach-o/getsect.h>
#include <mach-o/dyld.h>

#include <queue>
#include <vector>

using namespace llvm;

bool mull_isClassRegistered(Class cls);

Class class_getClassByName(const char *name);

void mull_dumpObjcMethods(Class clz);

bool isValidPointer(void *ptr);

#pragma mark -

namespace mull { namespace objc {

class Runtime {
  std::queue<class64_t **> classesToRegister;
  std::vector<Class> runtimeClasses;

  Class registerOneClass(class64_t **classrefPtr, Class superclass);
  void parsePropertyAttributes(const char *const attributesStr,
                               char *const stringStorage,
                               objc_property_attribute_t *attributes,
                               size_t *count);

public:
  ~Runtime();

  void registerSelectors(void *selRefsSectionPtr,
                         uintptr_t selRefsSectionSize);

  void addClassesFromSection(void *sectionPtr,
                             uintptr_t sectionSize);
  void addClassesFromClassRefsSection(void *sectionPtr,
                                      uintptr_t sectionSize);
  void addClassesFromSuperclassRefsSection(void *sectionPtr,
                                           uintptr_t sectionSize);

  void registerClasses();
};

} }
