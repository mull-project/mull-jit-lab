#include "ObjCRuntime.h"

bool mull_isClassRegistered(Class cls) {
  int numRegisteredClasses = objc_getClassList(NULL, 0);
  assert(numRegisteredClasses > 0);

  Class *classes = (Class *)malloc(sizeof(Class) * numRegisteredClasses);

  numRegisteredClasses = objc_getClassList(classes, numRegisteredClasses);

  for (int i = 0; i < numRegisteredClasses; i++) {
      //    errs() << object_getClassName(classes[i]) << "\n";
    if (classes[i] == cls) {
      free(classes);
      return true;
    }
  }

  free(classes);
  return false;
}

Class class_getClassByName(const char *name) {
  int numRegisteredClasses = objc_getClassList(NULL, 0);
  assert(numRegisteredClasses > 0);

  Class *classes = (Class *)malloc(sizeof(Class) * numRegisteredClasses);

  numRegisteredClasses = objc_getClassList(classes, numRegisteredClasses);

  for (int i = 0; i < numRegisteredClasses; i++) {
    if (strcmp(object_getClassName(classes[i]), name) == 0) {
      Class goodClass = classes[i];
      free(classes);
      return goodClass;
    }
  }

  free(classes);

  assert(false && "Class not found!");
  return NULL;
}

void mull_dumpObjcMethods(Class clz) {
  printf("mull_dumpObjcMethods() dumping class: %p\n", (void *)clz);

  unsigned int methodCount = 0;
  Method *methods = class_copyMethodList(clz, &methodCount);

  printf("Found %d methods on '%s'\n", methodCount, class_getName(clz));

  for (unsigned int i = 0; i < methodCount; i++) {
    Method method = methods[i];

    printf("\t'%s' has method named '%s' of encoding '%s'\n",
           class_getName(clz),
           sel_getName(method_getName(method)),
           method_getTypeEncoding(method));

    /**
     *  Or do whatever you need here...
     */
  }

  free(methods);
}

bool isValidPointer(void *ptr) {
  return (ptr != NULL) &&
  ((uintptr_t)ptr > 0x1000) &&
  ((uintptr_t)ptr < 0x7fffffffffff);
}

void hexPrint(char *bytes, size_t size) {
  printf("hexPrint:\n");

  for (size_t i = 0; i < size; i++) {
      //    printf("%ld: %02hhx ", i, bytes[i]);
    printf("%02hhx ", bytes[i]);
  }

  printf("\n");
}

#pragma mark - mull::objc::Runtime

void mull::objc::Runtime::registerSelectors(void *selRefsSectionPtr,
                                            uintptr_t selRefsSectionSize) {
  uint8_t *sectionStart = (uint8_t *)selRefsSectionPtr;

  for (uint8_t *cursor = sectionStart;
       cursor < (sectionStart + selRefsSectionSize);
       cursor = cursor + sizeof(SEL)) {
    SEL *selector = (SEL *)cursor;

      // TODO: memory padded/aligned by JIT.
    if (*selector == NULL) {
      continue;
    }
    const char *name = sel_getName(*selector);
    errs() << "Trying to register selector: " << *selector << "/" << name << "\n";
    *selector = sel_registerName(name);
  }
}

void mull::objc::Runtime::addClassesFromSection(void *sectionPtr,
                                                uintptr_t sectionSize) {
  errs() << "mull::objc::Runtime> adding class_t for later registration: "
         << sectionPtr << ", " << sectionSize << "\n";

  // 16 is "8 + alignment" (don't know yet what alignment is for).
  for (uintptr_t i = 0; i < sectionSize / 2; i += 8) {
    class64_t *const clzPointer = (class64_t *)((uint8_t *)sectionPtr + i);
    errs() << "mull::objc::Runtime> adding class: "
           << clzPointer->getIsaPointer()->getDataPointer()->getName() << "\n";

    class64_t *clzIsaPointer = clzPointer->getIsaPointer();

    classesToRegister.push(clzIsaPointer);
  }
}

void mull::objc::Runtime::registerClasses() {

  while (classesToRegister.empty() == false) {
    class64_t *clzIsaPointer = classesToRegister.front();
    classesToRegister.pop();

    errs() << "registerClasses() " << clzIsaPointer->getDataPointer()->getName() << "\n";

    class64_t *superClz64 = clzIsaPointer->getSuperclassPointer();
    Class superClz = (Class)superClz64;
    if (mull_isClassRegistered(superClz) == false) {
      const char *superclzName = superClz64->getDataPointer()->getName();
      if (Class registeredSuperClz = objc_getClass(superclzName)) {
        errs() << "registerClasses() " << "superclass is registered" << "\n";
        superClz = registeredSuperClz;
      } else {
        errs() << "registerClasses() " << "superclass is not registered" << "\n";

        classesToRegister.push(clzIsaPointer);
        continue;
      }
    }

    errs() << "registerClasses() " << "superclass is registered" << "\n";
    assert(superClz);

    registerOneClass(clzIsaPointer, superClz);
  }

  assert(classesToRegister.empty());
}

void mull::objc::Runtime::registerOneClass(class64_t *clzIsaPointer,
                                           Class superclass) {
  Class clz =
    objc_allocateClassPair(superclass,
                           clzIsaPointer->getDataPointer()->getName(),
                           0);

  /* INSTANCE METHODS */
  const class_ro64_t *clzIsaData = clzIsaPointer->getDataPointer();

  const method_list64_t *clzMethodListPtr = clzIsaData->getMethodListPtr();
  if (clzMethodListPtr) {
    const method64_t *firstMethodPtr = clzMethodListPtr->getFirstMethodPointer();

    for (uint32_t i = 0; i < clzMethodListPtr->count; i++) {
      const method64_t *methodPtr = firstMethodPtr + i;

      errs() << methodPtr->getDebugDescription();

      class_addMethod(clz, sel_registerName((char *)methodPtr->name), (IMP)methodPtr->imp, (char *)methodPtr->types);
    }
  }

  /* CLASS REGISTRATION */
  objc_registerClassPair(clz);
    //clzPointer->isa = ((class64_t *)clz);

  errs() << "+++ Registering Class: " << object_getClassName(clz)
  << " (" << clz << ")" << "\n";

  assert(mull_isClassRegistered(clz));
    //    assert(mull_isClassRegistered(objc_getClass(clzIsaPointer->getDataPointer()->getName())));
    //    assert(mull_isClassRegistered(objc_getClass(clzPointer->getIsaPointer()->getDataPointer()->getName())));

  /* METACLASS METHODS REGISTRATION */
  Class metaClz = objc_getMetaClass(object_getClassName(clz));

  const method_list64_t *metaClzMethodListPtr = clzIsaPointer->getIsaPointer()->getDataPointer()->getMethodListPtr();
  if (metaClzMethodListPtr) {
    const method64_t *firstMetaclassMethodPtr = metaClzMethodListPtr->getFirstMethodPointer();

    errs() << "Dumping metaclass' methods" << "\n";
    for (uint32_t i = 0; i < metaClzMethodListPtr->count; i++) {
      const method64_t *methodPtr = firstMetaclassMethodPtr + i;

      errs() << methodPtr->getDebugDescription();

      class_addMethod(metaClz,
                      sel_registerName((char *)methodPtr->name),
                      (IMP)methodPtr->imp,
                      (char *)methodPtr->types);
    }
  }

  mull_dumpObjcMethods(clz);
  mull_dumpObjcMethods(metaClz);
}
