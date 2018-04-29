#include "ObjCRuntime.h"

#include "ObjCRuntimeHelpers.h"

#include <objc/message.h>

namespace mull { namespace objc {

mull::objc::Runtime::~Runtime() {
  for (Class &clz: runtimeClasses) {
    assert(class_isMetaClass(objc_getClass(class_getName(clz))) == false);

    errs() << "disposing class: " << class_getName(clz) << "\n";
    assert(class_isMetaClass(clz) == false);
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

    class_ro64_t *clzPointerRO = clzPointer->getDataPointer();
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

    assert(class_isMetaClass(runtimeClass) == false);
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

  here_swift_class_t *correctObjCClass = (here_swift_class_t *)objc_getClass("BinarySearchTestCorrect");
  assert(correctObjCClass);

  const method_list64_t *metaClzMethodListPtr =
    metaclassRef->getDataPointer()->getMethodListPtr();

  errs() << "SUPPORT_PACKED_ISA: " << SUPPORT_PACKED_ISA << "\n";
  errs() << "SUPPORT_INDEXED_ISA: " << SUPPORT_INDEXED_ISA << "\n";
  errs() << "SUPPORT_NONPOINTER_ISA: " << SUPPORT_NONPOINTER_ISA << "\n";


//  here_objc_class *superClsLL = (here_objc_class *)superclass;
//  here_objc_class *oldClsLL = (here_objc_class *)classref;

  Class clz = objc_allocateClassPair(superclass,
                                     classref->getDataPointer()->getName(),
                                     0);

//  errs() << "POINTR before" << (void *)clz << "\n";
  here_swift_class_t *swiftClassRuntimeRef = (here_swift_class_t *)clz;

//  here_swift_class_t *swiftMetaclassRuntimeRef = (here_swift_class_t *)swiftClassRuntimeRef->ISA;
//
//  class_ro64_t *classRefRO = classref->getDataPointer();
//  class_ro64_t *swiftClassRuntimeRefRO = swiftClassRuntimeRef->data()->ro;
//
//  memcpy(swiftClassRuntimeRef->data()->ro, classref->getDataPointer(), sizeof(class_ro64_t));


//  memcpy((void *)swiftClassRuntimeRef->bits.bits, classref->data, sizeof(uintptr_t));
////  swiftClassRuntimeRef->data()->flags = correctObjCClass->data()->flags;
//
////  assert(correctObjCClass->isARC());
  swiftClassRuntimeRef->data()->ro->flags |= RO_IS_ARC;
////  assert(swiftClassRuntimeRef->isARC());
//  assert(swiftClassRuntimeRef->isSwift());
//
//#define RO_IS_ARC             (1<<7)
//
////  swiftClassRuntimeRef->data()->fl = correctObjCClass->data()->flags;
////  here_swift_class_t *correctSwiftClassRuntimeRef = (here_swift_class_t *)objc_getClass("BinarySearchTestCorrect");
////
////  class_ro64_t *oldRO = (class_ro64_t *)classref->getDataPointer();
////  class_ro64_t *correctSwiftClassRO = correctSwiftClassRuntimeRef->data()->ro;
////  class_ro64_t *runtimeRO = (class_ro64_t *)classref->getDataPointer();
////
////  here_class_rw_t *correctRW = correctSwiftClassRuntimeRef->data();
////  here_class_rw_t *runtimeRW = swiftClassRuntimeRef->data();
//
////  swiftClassRuntimeRef->bits.bits = (uintptr_t)classref->data;
////  swiftClassRuntimeRef->bits.bits = (uintptr_t)classref->data;
//
//#define RW_CONSTRUCTED        (1<<25)
//#define RW_CONSTRUCTING       (1<<26)
////  swiftClassRuntimeRef->data()->flags &= RW_CONSTRUCTED;
////  swiftClassRuntimeRef->data()->flags |= RW_CONSTRUCTING;
////  swiftMetaclassRuntimeRef->data()->flags &= RW_CONSTRUCTED;
////  swiftMetaclassRuntimeRef->data()->flags |= RW_CONSTRUCTING;
//
////  class_ro64_t *runtimeData = (class_ro64_t *)swiftClassRuntimeRef->data();
////  *runtimeData = *oldRO;
////  = classref->getDataPointer();
//
////  here_swift_class_t *newClsLL = (here_swift_class_t *)clz;
////  newClsLL->flags                 = correctObjCClass->flags;
////  newClsLL->instanceAddressOffset = correctObjCClass->instanceAddressOffset;
////  newClsLL->instanceSize          = correctObjCClass->instanceSize;
////  newClsLL->instanceAlignMask     = correctObjCClass->instanceAlignMask;
////  newClsLL->classSize     = correctObjCClass->classSize;
////
////  newClsLL->data()->ro = (class_ro64_t *)oldClsLL->data();
  here_class_rw_t *data = swiftClassRuntimeRef->data();
//  class_ro64_t *ro = data->ro;
  assert(swiftClassRuntimeRef->isARC());
  assert(swiftClassRuntimeRef->isSwift());
//////  newClsLL->setInstanceSize(ro->instanceSize);
////
//////  newClsLL->data()->methods = correctObjCClass->data()->methods;
////
//  method_list_t *mList = (method_list_t *)ro->baseMethods;
//  for (auto& meth : *mList) {
//    const char *name = sel_getName(meth.name);
//    meth.name = sel_registerName(name);
//  }
//  method64_t::SortBySELAddress sorter;
//  std::stable_sort(mList->begin(), mList->end(), sorter);
//
//  mList->setFixedUp();
//  data->methods.attachLists((method_list_t **)&ro->baseMethods, 1);
//
//  property_list_t *proplist = ro->baseProperties;
//  if (proplist) {
//    data->properties.attachLists(&proplist, 1);
//  }

////  objc_msgSend(clz, sel_registerName("description"));
////  assert(newClsLL->isSwift());
////
////  assert(oldClsLL->isSwift());
////  assert(superClsLL->isSwift());
//
////  newClsLL->data()->ro->flags = correctObjCClass->data()->flags;
////  newClsLL->data()-> = correctObjCClass->data();
////  memcpy(newClsLL, correctObjCClass, sizeof(here_swift_class_t));
//
////  newClsLL->data() = correctObjCClass->data()->methods;
//
//    //  abort();
//  /* IVARS */
  const ivar_list64_t *clzIvarListPtr = classref->getDataPointer()->ivars;
  if (clzIvarListPtr) {
    const ivar64_t *ivars = &clzIvarListPtr->first;

    for (uint32_t i = 0; i < clzIvarListPtr->count; i++) {
      const ivar64_t *ivar = ivars + i;

        // TODO: Can be dangerous: we are passing ivar->type which is something
        // like NSString instead of @encode(id) which is "@".
        // This is probably needed for runtime introspection.
      bool success = class_addIvar(clz, ivar->name, ivar->size, log2(ivar->size), ivar->type);
      assert(success);

      errs() << "adding ivar - name: " << ivar->name
             << " size: " << ivar->size
             << " alignment: " << ivar->alignment
             << "types: " << ivar->type
             << "\n";
    }
  }

  /* INSTANCE METHODS */
  const method_list64_t *clzMethodListPtr = classref->getDataPointer()->getMethodListPtr();
  if (clzMethodListPtr) {
    const method64_t *methods = (const method64_t *)clzMethodListPtr->getFirstMethodPointer();

    for (uint32_t i = 0; i < clzMethodListPtr->count; i++) {
      const method64_t *methodPtr = methods + i;

//      errs() << methodPtr->getDebugDescription();
      errs() << "METHH: " << sel_getName(methodPtr->name) << "/" << methodPtr->types << "\n";

      IMP dummyIMP = imp_implementationWithBlock(^(id self, id arg1, id arg2) {
        printf("accessing imp of: %s\n", methodPtr->name);
        fflush(stdout);
//        exit(1);
        abort();
      });

      IMP imp = (IMP)methodPtr->imp;

      if (strcmp("testEEEE", sel_getName(methodPtr->name)) != 0) {
//        continue;
//        imp = (IMP)dummyIMP; //methodPtr->imp;
      }

      BOOL added = class_addMethod(clz,
                                   sel_registerName(sel_getName(methodPtr->name)),
                                   (IMP)imp,
                                   (const char *)methodPtr->types);
      assert(added);
    }
  }

  /* PROPERTIES */
  objc_property_list64 *propertyListPtr = classref->getDataPointer()->baseProperties;
  if (propertyListPtr) {
    const objc_property64 *properties = &propertyListPtr->first;
//    const objc_property64 *properties = (const objc_property64 *)(propertyListPtr + 1);

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
      assert(class_addProperty(clz, property->name, attributesBuf, attributeCount));
    }
  }
  objc_registerClassPair(clz);
  assert(swiftClassRuntimeRef->isARC());
  assert(swiftClassRuntimeRef->isSwift());

//  assert(swiftClassRuntimeRef->isARC());

//  objc_registerClassPair((Class)classref);

  /* CLASS REGISTRATION */
//  here_swift_class_t * metaclassRuntimeRef = (here_swift_class_t *)objc_getMetaClass(class_getName(clz));
//  memcpy(metaclassRuntimeRef->data()->ro, classref->isa->getDataPointer(), sizeof(class_ro64_t));
//
  Class metaClz = objc_getMetaClass(class_getName(clz));
//
//  errs() << "+++ Registering Class: " << object_getClassName(clz)
//  << " (" << clz << ")" << "\n";
//
//  assert(RuntimeHelpers::class_isRegistered(clz));
//
//  /* METACLASS METHODS REGISTRATION */
//  if (metaClzMethodListPtr) {
//    const method64_t *firstMetaclassMethodPtr = metaClzMethodListPtr->getFirstMethodPointer();
//
//    errs() << "Dumping metaclass' methods" << "\n";
//    for (uint32_t i = 0; i < metaClzMethodListPtr->count; i++) {
//      const method64_t *methodPtr = firstMetaclassMethodPtr + i;
//
//      errs() << methodPtr->getDebugDescription();
//
//      IMP initIMP = imp_implementationWithBlock(^(id self, id arg1, id arg2) {
//        printf("accessing imp of: %s\n", methodPtr->name);
//
//        abort();
//      });
//
////      IMP imp = (IMP)initIMP; //methodPtr->imp;
//
//      auto imp = (IMP)methodPtr->imp;
//      class_addMethod(metaClz,
//                      sel_registerName(sel_getName(methodPtr->name)),
//                      imp,
//                      (const char *)methodPtr->types);
//    }
//  }
//
  Class registeredMetaClass = objc_getMetaClass(classref->getDataPointer()->getName());
  assert(metaClz == registeredMetaClass);

//  objc_msgSend(registeredMetaClass, sel_registerName("load"));
//  objc_msgSend(registeredMetaClass, sel_registerName("initialize"));

//  RuntimeHelpers::class_dumpMethods(clz);
//  RuntimeHelpers::class_dumpMethods(metaClz);

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

  void print_timediff(const char* prefix, const struct timespec& start, const
                      struct timespec& end)
  {
    double milliseconds = (end.tv_nsec - start.tv_nsec) / 1e6 + (end.tv_sec - start.tv_sec) * 1e3;
    printf("%s: %lf milliseconds\n", prefix, milliseconds);
  }

  void Runtime::fixupClassListReferences() {
    for (auto &pair: oldAndNewClassesMap) {
      class64_t **classref_ref = pair.first;

      class64_t *classref = *classref_ref;

      errs() << "Is Swift: " << classref->isSwift() << "\n";
      errs() << "Is Fast data mask: " << classref->isFastDataMask() << "\n";

      Class runtimeClass = pair.second;
      here_swift_class_t *swiftClassRuntimeRef = (here_swift_class_t *)runtimeClass;
      here_swift_class_t *correctSwiftClassRuntimeRef = (here_swift_class_t *)objc_getClass("BinarySearchTestCorrect");

#   define ISA_MASK        0x00007ffffffffff8ULL
//      assert((void *)objc_getMetaClass("BinarySearchTest") == (void *)swiftClassRuntimeRef->ISA);
//      assert((void *)objc_getMetaClass("BinarySearchTest") == ((class64_t *)swiftClassRuntimeRef)->isa);
      classref->isa = (class64_t *)objc_getMetaClass(object_getClassName(runtimeClass));
      classref->superclass = (class64_t *)class_getSuperclass(runtimeClass); //(class64_t *)swiftClassRuntimeRef->superclass;
//      classref->data = (class_ro64_t *)swiftClassRuntimeRef->bits.bits;
//      classref->data = (class_ro64_t *)swiftClassRuntimeRef->data();
//      classref->data = (class_ro64_t *)swiftClassRuntimeRef->data()->ro;
//      memcpy(classref->data, (void *)swiftClassRuntimeRef->data()->ro, sizeof(class_ro64_t));

//      *classref_ref = (class64_t *)swiftClassRuntimeRef;
//      *classref = *((class64_t *)swiftClassRuntimeRef);
      assert(swiftClassRuntimeRef->isARC());

//      class_ro64_t *oldRO = (class_ro64_t *)classref->getDataPointer();
//      class_ro64_t *correctSwiftClassRO = correctSwiftClassRuntimeRef->data()->ro;
//      class_ro64_t *runtimeRO = (class_ro64_t *)classref->getDataPointer();
//
//      here_class_rw_t *correctRW = correctSwiftClassRuntimeRef->data();
//      here_class_rw_t *runtimeRW = swiftClassRuntimeRef->data();
//      swiftClassRW->ro->weakIvarLayout
//      assert(class_isMetaClass(runtimeClass) == false);

//      classrefRO->flags = 0;

//      runtimeRW->ro = oldRO;

//      swiftClassRW->flags = 0;
      class64_t *classRegisteredRef = (class64_t *)pair.second;
//      errs() << "Is Swift Registered: " << classRegisteredRef->isSwift() << "\n";
//      errs() << "Is Swift Registered fast data mask: " << classRegisteredRef->isFastDataMask() << "\n";

//      ((class64_t *)runtimeClass)->getDataPointer()->flags |= (1UL<<0);
//      ((class64_t *)runtimeClass)->getDataPointer()->flags |= 0x00007ffffffffff8UL;

//      Class runtimeMetaClass = objc_getMetaClass(object_getClassName(runtimeClass));
//
//      here_objc_class *newClsLL = (here_objc_class *)runtimeClass;
//      here_objc_class *oldClsLL = (here_objc_class *)classref;

//      classref->isa = NULL;
//      *classref_ref = ((class64_t *)runtimeClass);
//      *classref_ref = ((class64_t *)runtimeClass);
//      *classref = *((class64_t *)runtimeClass);
//      classref->getDataPointer()->flags = 0x184;
//      Class pointerr = (Class)*classref_ref;
//      classref->isa = NULL;
//      classref->data = NULL;
//      classref->superclass = NULL;
//      classref->vtable = NULL;
//      classref->cache = NULL;
#define RO_IS_ARC             (1<<7)

//      classref->isa = ((class64_t *)runtimeClass)->isa;
//      classref->superclass = ((class64_t *)runtimeClass)->superclass;

//      classref->data = ((here_objc_class *)runtimeClass)->data()->ro;
//      classref->data->flags |= RO_IS_ARC;
//      class_ro64_t *dd = classref->getDataPointer();
//      dd->flags |= RO_IS_ARC;
//      classref->vtable = NULL;
//      classref->cache = ((class64_t *)runtimeClass)->cache;;
//      classref->getDataPointer()->flags = oldData;
//      classref->isa = ((class64_t *)runtimeClass)->isa;
//      memcpy(classref, runtimeClass, 40);

      errs() << "old class pointers: " << (void *)classref_ref << " / " << (void *)classref << "\n";
      errs() << "new class pointers: " << (void *)runtimeClass << " / " << (void *)classref << "\n";

      Class classObjCRef = (Class)classref;
      __unused id _ = objc_msgSend(classObjCRef, sel_registerName("description"));

//      id instance = objc_msgSend(objc_msgSend(runtimeClass, sel_registerName("alloc")), sel_registerName("description"));

//      objc_msgSend(instance, sel_registerName("setUp"));

//      objc_msgSend(bb, sel_registerName("description"));
//      objc_msgSend(instance, sel_registerName("description"));

//      here_objc_class *registeredClassAsObjC = (here_objc_class *)runtimeClass;

//      registeredClassAsObjC->data()->ro->baseMethods = classref->getDataPointer()->baseMethods;
//      registeredClassAsObjC->data()->ro->instanceStart = classref->getDataPointer()->instanceStart;
//      registeredClassAsObjC->data()->ro->instanceSize = classref->getDataPointer()->instanceSize;
//      registeredClassAsObjC->data()->ro->flags = classref->getDataPointer()->flags;
//      registeredClassAsObjC->data()->ro->ivars = classref->getDataPointer()->ivars;

//      registeredClassAsObjC->data()->flags |= 388;
//      assert(class_isMetaClass(runtimeClass) == false);

//      errs() << "Is Swift: " << classref->isSwift() << "\n";
//      errs() << "Is Fast data mask: " << classref->isFastDataMask() << "\n";
//      errs() << "Is Swift Registered: " << classRegisteredRef->isSwift() << "\n";
//      errs() << "Is Swift Registered fast data mask: " << classRegisteredRef->isFastDataMask() << "\n";
    }
  }
} }


