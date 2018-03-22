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
  assert(name);
  int numRegisteredClasses = objc_getClassList(NULL, 0);
  assert(numRegisteredClasses > 0);

  Class *classes = (Class *)malloc(sizeof(Class) * numRegisteredClasses);

  numRegisteredClasses = objc_getClassList(classes, numRegisteredClasses);

  for (int i = 0; i < numRegisteredClasses; i++) {
//    errs() << "bl: " << object_getClassName(classes[i]) << " ";
    if (strcmp(object_getClassName(classes[i]), name) == 0) {
      Class goodClass = classes[i];
      free(classes);
      return goodClass;
    }
  }

  free(classes);

  errs() << "Could not find a class: " << name << "\n";
  abort();
  return NULL;
}

void mull_dumpObjcMethods(Class clz) {
  printf("mull_dumpObjcMethods() dumping class: %p\n", (void *)clz);

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

void hexPrint(const char *const bytes, size_t size) {
  printf("hexPrint:\n");

  for (size_t i = 0; i < size; i++) {
      //    printf("%ld: %02hhx ", i, bytes[i]);
    printf("%02hhx ", bytes[i]);
  }

  printf("\n");
}

#pragma mark - mull::objc::Runtime

mull::objc::Runtime::~Runtime() {
  for (Class &clz: runtimeClasses) {
    objc_disposeClassPair(clz);
  }
}

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

  class64_t **classes = (class64_t **)sectionPtr;

  uint32_t count = sectionSize / 8;
  // 16 is "8 + alignment" (don't know yet what alignment is for).
  for (uintptr_t i = 0; i < count / 2; i += 1) {
    class64_t *const clzPointer = classes[i];
    errs() << "mull::objc::Runtime> adding class: "
           << clzPointer->getDataPointer()->getName() << "\n";

//    class64_t *clzIsaPointer = clzPointer->getIsaPointer();

    classesToRegister.push(&classes[i]);
  }
}

void mull::objc::Runtime::addClassesFromClassRefsSection(void *sectionPtr,
                                                         uintptr_t sectionSize) {
  errs() << "Runtime> addClassesFromClassRefsSection" << "\n";

  Class *classrefs = (Class *)sectionPtr;
  uint32_t count = sectionSize / 8;

  for (uint32_t i = 0; i < count / 2; i++) {
    Class *classrefPtr = (&classrefs[i]);

    const char *className = object_getClassName(*classrefPtr);

    errs() << "Considering " << className << "\n";

    assert(className);
    Class newClz = class_getClassByName(className);
    errs() << "\tclass has address: " << (void *)newClz << "\n";

    if (*classrefPtr != newClz) {
      *classrefPtr = newClz;
    }
  }
}

void mull::objc::Runtime::addClassesFromSuperclassRefsSection(void *sectionPtr,
                                                              uintptr_t sectionSize) {
//  return;
  errs() << "Runtime> addClassesFromSuperclassRefsSection" << "\n";

  Class *classrefs = (Class *)sectionPtr;
  uint32_t count = sectionSize / 8;

  for (uint32_t i = 0; i < count / 2; i++) {
    Class *classrefPtr = (&classrefs[i]);
    Class classref = *classrefPtr;
    const char *className = object_getClassName(*classrefPtr);

    errs() << "Considering " << className << "\n";

//    if (class_isMetaClass(classref)) {
//      errs() << "OBjc is metaclass" << "\n";
//    }

    assert(className);
    Class newClz = class_getClassByName(className);
    errs() << "\tclass has address: " << (void *)newClz << "\n";

    if (*classrefPtr != newClz) {
//      *classrefPtr = newClz;
    }
  }
}

#pragma mark - Private

void mull::objc::Runtime::registerClasses() {
  std::vector<std::pair<Class, class64_t **>> pairs;

  while (classesToRegister.empty() == false) {
    class64_t **classrefPtr = classesToRegister.front();
    class64_t *classref = *classrefPtr;
    classesToRegister.pop();

    errs() << "registerClasses() " << classref->getDataPointer()->getName() << "\n";

    class64_t *superClz64 = classref->getSuperclassPointer();
    Class superClz = (Class)superClz64;
    if (mull_isClassRegistered(superClz) == false) {
      const char *superclzName = superClz64->getDataPointer()->getName();
      if (Class registeredSuperClz = objc_getClass(superclzName)) {
        errs() << "registerClasses() " << "superclass is registered" << "\n";
        superClz = registeredSuperClz;
      } else {
        errs() << "registerClasses() " << "superclass is not registered" << "\n";

        classesToRegister.push(classrefPtr);
        continue;
      }
    }

    errs() << "registerClasses() " << "superclass is registered" << "\n";
//    errs() << classref->getDebugDescription() << "\n";

    assert(superClz);

    Class runtimeClass = registerOneClass(classrefPtr, superClz);
    runtimeClasses.push_back(runtimeClass);

    pairs.push_back(std::make_pair(runtimeClass, classrefPtr));
//    errs() << classref->getDebugDescription() << "\n";
  }

  for (auto &pair: pairs) {
    Class clz = pair.first;
    Class *classref = (Class *)pair.second;

//    *classref = clz;
//    memcpy(*classref, clz, sizeof(8 * 5));
  }

  assert(classesToRegister.empty());
}

static void dummy() {
  abort();
}

Class mull::objc::Runtime::registerOneClass(class64_t **classrefPtr,
                                            Class superclass) {
  class64_t *classref = *classrefPtr;
  const method_list64_t *metaClzMethodListPtr = classref->getIsaPointer()->getDataPointer()->getMethodListPtr();

  Class clz =
    objc_allocateClassPair(superclass,
                           classref->getDataPointer()->getName(),
                           0);

  /* INSTANCE METHODS */
  const method_list64_t *clzMethodListPtr = classref->getDataPointer()->getMethodListPtr();
  if (clzMethodListPtr) {
    method64_t *methods = (method64_t *)clzMethodListPtr->getFirstMethodPointer();

    for (uint32_t i = 0; i < clzMethodListPtr->count; i++) {
      const method64_t *methodPtr = methods + i;

      errs() << methodPtr->getDebugDescription();

//      auto imp = ((void (*)(void))dummy);

      IMP imp = (IMP)methodPtr->imp;
      BOOL added = class_addMethod(clz,
                                   sel_registerName(sel_getName(methodPtr->name)),
                                   (IMP)imp,
                                   (char *)methodPtr->types);
      assert(added);
    }
  }

  /* INSTANCE METHODS */
  const ivar_list64_t *clzIvarListPtr = classref->getDataPointer()->ivars;
  if (clzIvarListPtr) {
    ivar64_t *ivars = (ivar64_t *)(clzIvarListPtr + 1);

    for (uint32_t i = 0; i < clzIvarListPtr->count; i++) {
      const ivar64_t *ivar = ivars + i;

      // TODO: Can be dangerous: we are passing ivar->type which is something
      // like NSString instead of @encode(id) which is "@".
      // This is probably needed for runtime introspection.
      class_addIvar(clz, ivar->name, ivar->size, log2(ivar->size), ivar->type);
    }
  }

  /* PROPERTIES */
  const objc_property_list64 *propertyListPtr = classref->getDataPointer()->baseProperties;
  if (propertyListPtr) {
    objc_property64 *properties = (objc_property64 *)(propertyListPtr + 1);

    objc_property_attribute_t attributesBuf[10];
    memset(attributesBuf, 0, 10 * sizeof(objc_property_attribute_t));

    char stringStorage[1024];

    for (uint32_t i = 0; i < propertyListPtr->count; i++) {
      const objc_property64 *property = properties + i;

      errs() << "Property: " << property->name << "\n";

      size_t attributeCount = 0;
      parsePropertyAttributes(property->attributes,
                              stringStorage,
                              attributesBuf,
                              &attributeCount);
      class_addProperty(clz, property->name, attributesBuf, attributeCount);
    }
  }

  /* CLASS REGISTRATION */
  objc_registerClassPair(clz);
  Class metaClz = objc_getMetaClass("FirstClass");

  errs() << "+++ Registering Class: " << object_getClassName(clz)
  << " (" << clz << ")" << "\n";

  assert(mull_isClassRegistered(clz));

  /* METACLASS METHODS REGISTRATION */
  if (metaClzMethodListPtr) {
    const method64_t *firstMetaclassMethodPtr = metaClzMethodListPtr->getFirstMethodPointer();

    errs() << "Dumping metaclass' methods" << "\n";
    for (uint32_t i = 0; i < metaClzMethodListPtr->count; i++) {
      const method64_t *methodPtr = firstMetaclassMethodPtr + i;

      errs() << methodPtr->getDebugDescription();
//      auto imp = (IMP)((void (*)(void))dummy);

      auto imp = (IMP)methodPtr->imp;
      class_addMethod(metaClz,
                      sel_registerName(sel_getName(methodPtr->name)),
                      imp,
                      (char *)methodPtr->types);
    }
  }

  mull_dumpObjcMethods(clz);
  mull_dumpObjcMethods(metaClz);

  return clz;
}

void
mull::objc::Runtime::parsePropertyAttributes(const char *const attributesStr,
                                             char *const stringStorage,
                                             objc_property_attribute_t *attributes,
                                             size_t *count) {
  size_t attrFound = 0;

  char attributesCopy[32];

  strcpy(attributesCopy, attributesStr);

  size_t storageIndex = 0;

  char *token;
  char *rest = attributesCopy;
  while((token = strtok_r(rest, ",", &rest))) {
    printf("token:%s\n", token);
    size_t tokenLen = strlen(token);

    switch (token[0]) {
      case 'T': case 'V': {
        objc_property_attribute_t tAttr;

        stringStorage[storageIndex] = token[0];
        stringStorage[storageIndex + 1] = '\0';
        tAttr.name = stringStorage + storageIndex;

        storageIndex += 2;

        tAttr.value = stringStorage + storageIndex;
        strcpy(stringStorage + storageIndex, token + 1);
        storageIndex += tokenLen - 1;
        strcpy(stringStorage + storageIndex, "\0");
        storageIndex += 1;

        attributes[attrFound++] = tAttr;

        break;
      }

      case '&': case 'N': {
        objc_property_attribute_t tAttr;

        tAttr.name = stringStorage + storageIndex;
        tAttr.value = NULL;
        stringStorage[storageIndex] = token[0];
        stringStorage[storageIndex + 1] = '\0';
        storageIndex += 2;

        attributes[attrFound++] = tAttr;

        break;
      }

      default:
        assert(false && "Unknown type");
        break;
    }
  }

  *count = attrFound;
}
