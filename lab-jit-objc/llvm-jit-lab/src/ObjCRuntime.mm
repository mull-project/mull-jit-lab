#include "ObjCRuntime.h"

#include "ObjCRuntimeHelpers.h"

#include <objc/message.h>

namespace mull { namespace objc {

mull::objc::Runtime::~Runtime() {
  for (Class &clz: runtimeClasses) {
    errs() << "disposing class: " << class_getName(clz) << "\n";
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
    class64_t **clzPointerRef = &classes[i];
    class64_t *clzPointer = *clzPointerRef;

    errs() << "mull::objc::Runtime> adding class: "
           << clzPointer->getDataPointer()->getName() << "\n";

    classesToRegister.push(clzPointerRef);
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
    assert(className);
    errs() << "Considering " << className << "\n";

    Class newClz = RuntimeHelpers::class_getClassByName(className);
    assert(class_isMetaClass(newClz) == false);
    errs() << "\tclass has address: " << (void *)newClz << "\n";

    if (*classrefPtr != newClz) {
      *classrefPtr = objc_getClass(className);
    }
  }
}

void mull::objc::Runtime::addClassesFromSuperclassRefsSection(void *sectionPtr,
                                                              uintptr_t sectionSize) {
  errs() << "Runtime> addClassesFromSuperclassRefsSection" << "\n";

  Class *classrefs = (Class *)sectionPtr;
  uint32_t count = sectionSize / 8;

  for (uint32_t i = 0; i < count / 2; i++) {
    int refType = 0; // 0 - unknown, 1 - class, 2 - metaclass

    Class *classrefPtr = (&classrefs[i]);
    Class classref = *classrefPtr;

    class64_t *ref = NULL;
    for (auto &clref: classRefs) {
      if ((void *)clref == (void *)classref) {
        errs() << "Ref is class" << "\n";
        refType = 1;
        ref = clref;

        assert(ref);

        break;
      }
    }

    if (refType == 0) {
      for (auto &metaclref: metaclassRefs) {
        if ((void *)metaclref == (void *)classref) {
          errs() << "Ref is metaclass" << "\n";
          refType = 2;
          ref = metaclref;
          break;
        }
      }
    }

    const char *className;
    if (ref == NULL) {
      className = object_getClassName(classref);

      errs() << "Class is already registered (not by us) - " << className << "\n";
    } else {
      className = ref->getDataPointer()->getName();
    }

    errs() << "Considering " << className << "\n";
    Class newClz = RuntimeHelpers::class_getClassByName(className);

    assert(refType != 0);
    if (refType == 2) {
      newClz = objc_getMetaClass(className);
      assert(newClz);
      assert(class_isMetaClass(newClz));
    }

    if (*classrefPtr != newClz) {
      *classrefPtr = newClz;
    }
  }

  errs() << "Runtime> addClassesFromSuperclassRefsSection DONE" << "\n";
}

#pragma mark - Private


void mull::objc::Runtime::registerClasses() {
  while (classesToRegister.empty() == false) {
    class64_t **classrefPtr = classesToRegister.front();
    class64_t *classref = *classrefPtr;
    classesToRegister.pop();

    errs() << "registerClasses() " << classref->getDataPointer()->getName() << "\n";

    class64_t *superClz64 = classref->getSuperclassPointer();
    Class superClz = (Class)superClz64;
    if (RuntimeHelpers::class_isRegistered(superClz) == false) {
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

    errs() << "registerClasses() "
           << "superclass is registered for class: " << classref->getDataPointer()->getName()
           << "\n";
    errs() << classref->getDebugDescription() << "\n";

    assert(superClz);

    Class runtimeClass = registerOneClass(classrefPtr, superClz);
    runtimeClasses.push_back(runtimeClass);

    oldAndNewClassesMap.push_back(std::pair<class64_t **, Class>(classrefPtr, runtimeClass));

    errs() << classref->getDebugDescription() << "\n";
  }

  assert(classesToRegister.empty());
}

Class mull::objc::Runtime::registerOneClass(class64_t **classrefPtr,
                                            Class superclass) {
  assert(objc_debug_isa_class_mask == FAST_DATA_MASK);

  class64_t *classref = *classrefPtr;
  class64_t *metaclassRef = classref->getIsaPointer();

  assert(strlen(classref->getDataPointer()->name) > 0);
  errs() << "registerOneClass: " << classref->getDataPointer()->name << "\n";
  classRefs.push_back(classref);
  metaclassRefs.push_back(metaclassRef);

  const method_list64_t *metaClzMethodListPtr =
    metaclassRef->getDataPointer()->getMethodListPtr();

  here_objc_class *superClsLL = (here_objc_class *)superclass;
  here_objc_class *oldClsLL = (here_objc_class *)classref;

  Class clz =
    objc_allocateClassPair(superclass,
                           classref->getDataPointer()->getName(),
                           0);

  /*
  here_objc_class *newClsLL = (here_objc_class *)clz;
  newClsLL->data()->ro = (class_ro64_t *)oldClsLL->data();
  here_class_rw_t *data = newClsLL->data();
  class_ro64_t *ro = newClsLL->data()->ro;
  newClsLL->setInstanceSize(ro->instanceSize);

  method_list_t *mList = (method_list_t *)ro->baseMethods;
  for (auto& meth : *mList) {
    const char *name = sel_getName(meth.name);
    meth.name = sel_registerName(name);
  }
  method64_t::SortBySELAddress sorter;
  std::stable_sort(mList->begin(), mList->end(), sorter);

  mList->setFixedUp();
  data->methods.attachLists((method_list_t **)&ro->baseMethods, 1);

  assert(newClsLL->isSwift());
  assert(oldClsLL->isSwift());
  assert(superClsLL->isSwift());
*/

  /* INSTANCE METHODS */
  const method_list64_t *clzMethodListPtr = classref->getDataPointer()->getMethodListPtr();
  if (clzMethodListPtr) {
    const method64_t *methods = (const method64_t *)clzMethodListPtr->getFirstMethodPointer();

    for (uint32_t i = 0; i < clzMethodListPtr->count; i++) {
      const method64_t *methodPtr = methods + i;

//      errs() << methodPtr->getDebugDescription();
      errs() << "METHH: " << sel_getName(methodPtr->name) << "\n";


      IMP dummyIMP = imp_implementationWithBlock(^(id self, id arg1, id arg2) {
        printf("accessing imp of: %s\n", methodPtr->name);
        fflush(stdout);
//        exit(1);
        abort();
      });

      IMP imp = (IMP)methodPtr->imp;

      if (strcmp("methodOfStan", sel_getName(methodPtr->name)) == 0) {
        imp = (IMP)dummyIMP; //methodPtr->imp;
      }

      BOOL added = class_addMethod(clz,
                                   sel_registerName(sel_getName(methodPtr->name)),
                                   (IMP)imp,
                                   (const char *)methodPtr->types);
      assert(added);
    }
  }

//  abort();
  /* IVARS */
  const ivar_list64_t *clzIvarListPtr = classref->getDataPointer()->ivars;
  if (clzIvarListPtr) {
    const ivar64_t *ivars = (const ivar64_t *)(clzIvarListPtr + 1);

    for (uint32_t i = 0; i < clzIvarListPtr->count; i++) {
      const ivar64_t *ivar = ivars + i;

      // TODO: Can be dangerous: we are passing ivar->type which is something
      // like NSString instead of @encode(id) which is "@".
      // This is probably needed for runtime introspection.
      bool success = class_addIvar(clz, ivar->name, ivar->size, log2(ivar->size), ivar->type);

      assert(success);

      errs() << "adding ivar: " << ivar->name << " / " << ivar->type << "\n";
    }
  }

  /* PROPERTIES */
  const objc_property_list64 *propertyListPtr = classref->getDataPointer()->baseProperties;
  if (propertyListPtr) {
    const objc_property64 *properties = (const objc_property64 *)(propertyListPtr + 1);

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
  objc_registerClassPair(clz);
#define RW_CONSTRUCTED        (1<<25)

  errs() << "ZER\n";

//  objc_registerClassPair((Class)classref);

  /* CLASS REGISTRATION */
  Class metaClz = objc_getMetaClass(class_getName(clz));

  errs() << "+++ Registering Class: " << object_getClassName(clz)
  << " (" << clz << ")" << "\n";

  assert(RuntimeHelpers::class_isRegistered(clz));

  /* METACLASS METHODS REGISTRATION */
  if (metaClzMethodListPtr) {
    const method64_t *firstMetaclassMethodPtr = metaClzMethodListPtr->getFirstMethodPointer();

    errs() << "Dumping metaclass' methods" << "\n";
    for (uint32_t i = 0; i < metaClzMethodListPtr->count; i++) {
      const method64_t *methodPtr = firstMetaclassMethodPtr + i;

      errs() << methodPtr->getDebugDescription();

      IMP initIMP = imp_implementationWithBlock(^(id self, id arg1, id arg2) {
        printf("accessing imp of: %s\n", methodPtr->name);

        abort();
      });

//      IMP imp = (IMP)initIMP; //methodPtr->imp;

      auto imp = (IMP)methodPtr->imp;
      class_addMethod(metaClz,
                      sel_registerName(sel_getName(methodPtr->name)),
                      imp,
                      (const char *)methodPtr->types);
    }
  }

  Class registeredMetaClass = objc_getMetaClass(classref->getDataPointer()->getName());
  assert(metaClz == registeredMetaClass);

//  objc_msgSend(registeredMetaClass, sel_registerName("load"));
//  objc_msgSend(registeredMetaClass, sel_registerName("initialize"));

  RuntimeHelpers::class_dumpMethods(clz);
  RuntimeHelpers::class_dumpMethods(metaClz);

  return clz;
}

void
mull::objc::Runtime::parsePropertyAttributes(const char *const attributesStr,
                                             char *const stringStorage,
                                             objc_property_attribute_t *attributes,
                                             size_t *count) {
  size_t attrFound = 0;

  printf("parsePropertyAttributes attr string: %s\n", attributesStr);
  char attributesCopy[128];

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

      case '&': case 'N': case 'C': case 'R': {
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

  void Runtime::fixupClassListReferences() {
    for (auto &pair: oldAndNewClassesMap) {
      class64_t **classref_ref = pair.first;

      class64_t *classref = *classref_ref;

      errs() << "Is Swift: " << classref->isSwift() << "\n";
      errs() << "Is Fast data mask: " << classref->isFastDataMask() << "\n";

      Class runtimeClass = pair.second;

      class64_t *classRegisteredRef = (class64_t *)pair.second;
      errs() << "Is Swift Registered: " << classRegisteredRef->isSwift() << "\n";
      errs() << "Is Swift Registered fast data mask: " << classRegisteredRef->isFastDataMask() << "\n";

//      ((class64_t *)runtimeClass)->getDataPointer()->flags |= (1UL<<0);
//      ((class64_t *)runtimeClass)->getDataPointer()->flags |= 0x00007ffffffffff8UL;

//      Class runtimeMetaClass = objc_getMetaClass(object_getClassName(runtimeClass));
//
//      here_objc_class *newClsLL = (here_objc_class *)runtimeClass;
//      here_objc_class *oldClsLL = (here_objc_class *)classref;

      *classref_ref = ((class64_t *)runtimeClass);

      Class pointerr = (Class)*classref_ref;
//      *classref = NULL; //*((class64_t *)runtimeClass);
//      classref->isa = NULL;
//      classref->data = NULL;
//      classref->superclass = NULL;
//      classref->getDataPointer()->flags = oldData;
//      classref->isa = ((class64_t *)runtimeClass)->isa;
//      memcpy(classref, runtimeClass, 40);
      errs() << "Is Swift: " << classref->isSwift() << "\n";
      errs() << "Is Fast data mask: " << classref->isFastDataMask() << "\n";
      errs() << "Is Swift Registered: " << classRegisteredRef->isSwift() << "\n";
      errs() << "Is Swift Registered fast data mask: " << classRegisteredRef->isFastDataMask() << "\n";


//      unsigned int outClasses = 0;
//      Class  *runttimeClass = objc_copyClassList(&outClasses);



      errs() << "FOOO" << "\n";
    }
  }
} }

