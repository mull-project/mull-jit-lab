#include "ObjCRuntimeHelpers.h"

#include <llvm/Support/raw_ostream.h>

#include <assert.h>

using namespace llvm;

bool RuntimeHelpers::isValidPointer(void *ptr) {
  return (ptr != NULL) &&
  ((uintptr_t)ptr > 0x1000) &&
  ((uintptr_t)ptr < 0x7fffffffffff);
}

bool RuntimeHelpers::class_isRegistered(Class cls) {
  int numRegisteredClasses = objc_getClassList(NULL, 0);
  assert(numRegisteredClasses > 0);

  Class *classes = (Class *)malloc(sizeof(Class) * numRegisteredClasses);

  numRegisteredClasses = objc_getClassList(classes, numRegisteredClasses);

  for (int i = 0; i < numRegisteredClasses; i++) {
    if (classes[i] == cls) {
      free(classes);
      return true;
    }
  }

  free(classes);
  return false;
}

Class RuntimeHelpers::class_getClassByName(const char *name) {
  assert(name);
  int numRegisteredClasses = objc_getClassList(NULL, 0);
  assert(numRegisteredClasses > 0);

  Class *classes = (Class *)malloc(sizeof(Class) * numRegisteredClasses);

  numRegisteredClasses = objc_getClassList(classes, numRegisteredClasses);

  for (int i = 0; i < numRegisteredClasses; i++) {
    if (strcmp(object_getClassName(classes[i]), name) == 0) {
      Class foundClass = classes[i];
      assert(class_isMetaClass(foundClass) == false);
      free(classes);
      return foundClass;
    }
  }

  free(classes);

  errs() << "Could not find a class: " << name << "\n";
  abort();

  return NULL;
}

void RuntimeHelpers::class_dumpMethods(Class clz) {
  bool isMetaClass = class_isMetaClass(clz);
  std::string clOrMetaclazz(isMetaClass ? "metaclass" : "class");

  printf("class_dumpMethods() dumping %s: %p\n", clOrMetaclazz.c_str(), (void *)clz);

  unsigned int methodCount = 0;
  Method *methods = class_copyMethodList(clz, &methodCount);

  printf("Found %d methods on '%s'\n", methodCount, class_getName(clz));

  for (unsigned int i = 0; i < methodCount; i++) {
    Method method = methods[i];

    printf("\t'%s' has method named '%s' of encoding '%s' %p\n",
           class_getName(clz),
           sel_getName(method_getName(method)),
           method_getTypeEncoding(method),
           (void *)method);

    /**
     *  Or do whatever you need here...
     */
  }

  free(methods);
}
