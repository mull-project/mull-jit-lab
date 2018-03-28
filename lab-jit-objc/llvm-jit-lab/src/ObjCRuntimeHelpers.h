#pragma once

#include <objc/runtime.h>

namespace mull { namespace objc {

class RuntimeHelpers {
public:
  static bool isValidPointer(void *ptr);

  static bool class_isRegistered(Class cls);

  static Class class_getClassByName(const char *name);

  static void class_dumpMethods(Class clz);
};

} } // namespace mull { namespace objc
