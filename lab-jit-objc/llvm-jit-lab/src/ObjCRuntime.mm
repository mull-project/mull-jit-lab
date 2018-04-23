#include "ObjCRuntime.h"

#include "DebugUtils.h"
#include "ObjCRuntimeHelpers.h"

#include <objc/message.h>

#include <iostream>
#include <inttypes.h>

namespace mull { namespace objc {


mull::objc::Runtime::~Runtime() {
#define RW_CONSTRUCTED        (1<<25)

  for (const Class &clz: runtimeClasses) {
    char *dd = strdup(class_getName(clz));
    errs() << "disposing class: " << class_getName(clz) << "\n";

    here_objc_class *objcClass = (here_objc_class *)clz;
    here_class_rw_t *rw = objcClass->data();
    rw->flags |= RW_CONSTRUCTED;

    here_objc_class *objcMetaClass = (here_objc_class *)objc_getMetaClass(class_getName(clz));
    objcMetaClass->data()->flags |= RW_CONSTRUCTED;

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
  errs() << "mull::objc::Runtime> adding section for later registration: "
         << sectionPtr << ", " << sectionSize << "\n";

  class64_t **classes = (class64_t **)sectionPtr;

  uint32_t count = sectionSize / 8;
  // 16 is "8 + alignment" (don't know yet what alignment is for).
  for (uintptr_t i = 0; i < count / 2; i += 1) {
    class64_t **clzPointerRef = &classes[i];
    class64_t *clzPointer = *clzPointerRef;

    errs() << "mull::objc::Runtime> adding class for registration: "
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
      *classrefPtr = objc_getRequiredClass(className);
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

    assert(refType != 0);
    const char *className;
    if (ref == NULL) {
      className = object_getClassName(classref);

      errs() << "Class is already registered (not by us) - " << className << "\n";
    } else {
      className = ref->getDataPointer()->getName();
    }
    here_objc_class *objcClass = (here_objc_class *)classref;
    if (refType == 1 && runtimeClasses.count(classref) > 0) {
      className = objcClass->data()->ro->name;
    }
    else if (refType == 2) {
      Class classForMetaClass = objc_getClass(object_getClassName(classref));
      assert(classForMetaClass);
      className = objcClass->data()->ro->name;
    }
    assert(className);

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
    //errs() << classref->getDebugDescription() << "\n";

    assert(superClz);

    Class runtimeClass = registerOneClass(classrefPtr, superClz);
    runtimeClasses.insert(runtimeClass);

    oldAndNewClassesMap.push_back(std::pair<class64_t **, Class>(classrefPtr, runtimeClass));

    errs() << classref->getDebugDescription() << "\n";
  }

  assert(classesToRegister.empty());
}

extern "C" Class objc_readClassPair(Class bits, const struct objc_image_info *info);

Class mull::objc::Runtime::registerOneClass(class64_t **classrefPtr,
                                            Class superclass) {

  class64_t *classref = *classrefPtr;
  class64_t *metaclassRef = classref->getIsaPointer();

  assert(strlen(classref->getDataPointer()->name) > 0);
  printf("registerOneClass: %s \n", classref->getDataPointer()->name);
  printf("\t" "source ptr: 0x%016" PRIxPTR "\n", (uintptr_t)classref);
  printf("0x%016" PRIXPTR "\n", (uintptr_t) classref);

  classRefs.push_back(classref);
  metaclassRefs.push_back(metaclassRef);

//  assert(objc_getClass(classref->getDataPointer()->name) == NULL);
  const method_list64_t *metaClzMethodListPtr =
    metaclassRef->getDataPointer()->getMethodListPtr();

  Class cllll = objc_readClassPair((Class)classref, NULL);
  assert(cllll);
  here_objc_class *runtimeCllll = (here_swift_class_t *)cllll;
  here_objc_class *runtimeMetaCllll = (here_objc_class *)runtimeCllll->ISA__();

#define RW_CONSTRUCTING       (1<<26)

  here_class_rw_t *sourceClassData = runtimeCllll->data();
//  here_class_rw_t *sourceMetaclassData = ((classref->isa))->getDataPointer();
  here_class_rw_t *sourceMetaclassData = (here_class_rw_t *)runtimeMetaCllll->data();
  sourceClassData->flags |= RW_CONSTRUCTING;
  sourceMetaclassData->flags |= RW_CONSTRUCTING;
  objc_registerClassPair(cllll);

  return cllll;

  Class clz =
    objc_allocateClassPair(superclass,
                           classref->getDataPointer()->getName(),
                           0);

  here_swift_class_t *runtimeSwiftClass = (here_swift_class_t *)clz;
//  here_swift_class_t *runtimeSwiftClass = (here_swift_class_t *)malloc(sizeof(here_swift_class_t));
//  runtimeSwiftClass->data()
  class_ro64_t *runtimeRO = runtimeSwiftClass->data()->ro;
  class_ro64_t *deadRO = classref->getDataPointer();

//  runtimeSwiftClass->classSize = correctSwiftClass->classSize;
//  memcpy(runtimeSwiftClass->data()->ro, classref->getDataPointer(), sizeof(class_ro64_t));
//  memcpy(&runtimeSwiftClass->data()->ro->flags, &classref->getDataPointer()->flags, sizeof(uint32_t));
//  memcpy(runtimeSwiftClass->data()->ro->ivars, classref->getDataPointer()->ivars, sizeof(uint32_t));
#define RO_IS_ARC             (1<<7)
  ivar64_t *firstIvar = (ivar64_t *)&classref->getDataPointer()->ivars->first;

//  id runtimeClass = (id)objc_getRequiredClass("NSObject");
//  id allocatedInstance = objc_msgSend(runtimeClass, sel_registerName("alloc"));
//  id initializedInstance = objc_msgSend(allocatedInstance, sel_registerName("init"));
//  assert(initializedInstance);
//  assert((id)object_getClass(initializedInstance) == runtimeClass);

  uint32_t offset = 0x88888; //runtimeSwiftClass->data()->ro->instanceSize;
  uint32_t alignMask = (1 << firstIvar->alignment) - 1;
//  firstIvar->offset = (char *)runtimeSwiftClass + 88;

//  runtimeSwiftClass->data()->ro->ivars = classref->getDataPointer()->ivars;
//  runtimeSwiftClass->data()->ro->instanceSize = classref->getDataPointer()->instanceSize;
//  runtimeSwiftClass->data()->ro->instanceStart = classref->getDataPointer()->instanceStart;
//  runtimeSwiftClass->data()->ro->flags |= RO_IS_ARC;
//  runtimeSwiftClass->data()->d->flags |= RO_IS_ARC;
//  newClsLL->getDataPointer() = (class_ro64_t *)oldClsLL->data();
//  here_class_rw_t *data = runtimeSwiftClass->data();
//  class_ro64_t *ro = runtimeSwiftClass->data()->ro;
//  newClsLL->setInstanceSize(ro->instanceSize);
//
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

  /* IVARS */
  const ivar_list64_t *clzIvarListPtr = classref->getDataPointer()->ivars;
  if (clzIvarListPtr) {
    const ivar64_t *ivars = &clzIvarListPtr->first;

    for (uint32_t i = 0; i < clzIvarListPtr->count; i++) {
      const ivar64_t *ivar = ivars + i;

      errs() << "adding ivar: " << to_hex16(ivar) << " name: " << ivar->name << " / " << ivar->type << "\n"\
             << "alignment: " << ivar->alignment << " size: " << ivar->size << "\n";;

        // TODO: Can be dangerous: we are passing ivar->type which is something
        // like NSString instead of @encode(id) which is "@".
        // This is probably needed for runtime introspection.
      bool success = class_addIvar(clz, ivar->name, ivar->size, log2(ivar->size), "@");

      assert(success);
    }
  }

  /* INSTANCE METHODS */
  const method_list64_t *clzMethodListPtr = classref->getDataPointer()->getMethodListPtr();
  if (clzMethodListPtr) {
    const method64_t *methods = (const method64_t *)clzMethodListPtr->getFirstMethodPointer();

    for (uint32_t i = 0; i < clzMethodListPtr->count; i++) {
      const method64_t *methodPtr = methods + i;

      //errs() << methodPtr->getDebugDescription();
      errs() << "Registering method: " << sel_getName(methodPtr->name) << "\n";

      IMP dummyIMP = imp_implementationWithBlock(^(id self, id arg1, id arg2) {
        printf("accessing imp of: %s\n", sel_getName(methodPtr->name));
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

  /* PROPERTIES */
  const objc_property_list64 *propertyListPtr = classref->getDataPointer()->baseProperties;
  if (NO && propertyListPtr) {
    const objc_property64 *properties = &propertyListPtr->first;

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
  
  /* CLASS REGISTRATION */
  Class metaClz = objc_getMetaClass(class_getName(clz));

  errs() << "+++ Registering Class: " << object_getClassName(clz)
         << "\t" << "runtimeptr: (" << clz << ")" << "\n";

  assert(RuntimeHelpers::class_isRegistered(clz));

  /* METACLASS METHODS REGISTRATION */
  if (metaClzMethodListPtr) {
    const method64_t *firstMetaclassMethodPtr = metaClzMethodListPtr->getFirstMethodPointer();

    errs() << "Dumping metaclass' methods" << "\n";
    for (uint32_t i = 0; i < metaClzMethodListPtr->count; i++) {
      const method64_t *methodPtr = firstMetaclassMethodPtr + i;

      errs() << methodPtr->getDebugDescription();

      auto imp = (IMP)methodPtr->imp;
      class_addMethod(metaClz,
                      sel_registerName(sel_getName(methodPtr->name)),
                      imp,
                      (const char *)methodPtr->types);
    }
  }

  Class registeredMetaClass = objc_getMetaClass(classref->getDataPointer()->getName());
  assert(metaClz == registeredMetaClass);

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
    errs() << "fixupClassListReferences() starts" << "\n";

    for (auto &pair: oldAndNewClassesMap) {
      class64_t **classref_ref = pair.first;

      class64_t *classref = *classref_ref;

      errs() << "Is Swift: " << classref->isSwift() << "\n";

      Class runtimeClass = pair.second;
      errs() << "fixupClassListReferences()> clref " << *classref_ref << "\n";

      class64_t *classRegisteredRef = (class64_t *)pair.second;

      here_objc_class *runtimeObjCClass = (here_objc_class *)runtimeClass;

      // Ugly hack to "realizeClass" old class before the new one gets called.
      // This means that runtime works with through the old class's pointers,
      // but we are not getting crashes for new class, whose structs we cannot
      // replicate with the Objective-C Runtime APIs.

      assert((void *)objc_getMetaClass(object_getClassName(runtimeClass)) != ((class64_t *)runtimeClass)->isa);
      assert((void *)class_getSuperclass(runtimeClass) == ((class64_t *)runtimeClass)->superclass);
//      *classref_ref = NULL;// (class64_t *)runtimeClass;

//      classref->vtable = ((class64_t *)runtimeClass)->vtable;
//      classref->cache = ((class64_t *)runtimeClass)->cache;

      void *pointerToData = classref->getDataPointer();
//      *classref = *((class64_t *)runtimeClass);
//      classref->isa = (class64_t *)objc_getMetaClass(object_getClassName(runtimeClass));
//      classref->isa = NULL;
//      classref->superclass = (class64_t *)class_getSuperclass(runtimeClass);
//      classref->superclass = NULL;
//      classref->data = (class_ro64_t *)runtimeObjCClass->data()->ro;
//      classref->getDataPointer()->name = "BinarySearchTest";
//      classref->cache = NULL;
//      classref->cache = runtimeObjCClass->cache.__unused_buckets;
//      classref->vtable = NULL;
//      classref->vtable = NULL; //runtimeObjCClass->unused2_vtable;
//      *classref_ref = NULL; //((class64_t *)runtimeClass);

        //  here_swift_class_t *runtimeSwiftClass = (here_swift_class_t *)malloc(sizeof(here_swift_class_t));
        //  runtimeSwiftClass->data()
//      class_ro64_t *runtimeRO = runtimeObjCClass->data()->ro;
//      class_ro64_t *deadRO = classref->getDataPointer();

//      auto oldIvarOffsetRuntime = runtimeObjCClass->data()->ro->ivars->first.offset;
//      auto oldIvarOffsetDead = deadRO->ivars->first.offset;
      Class classObjCRef = (Class)classref;
//      __unused id _ = objc_msgSend(classObjCRef, sel_registerName("description"));

//      auto newIvarOffsetRuntime = runtimeObjCClass->data()->ro->ivars->first.offset;
//      auto newIvarOffsetDead = deadRO->ivars->first.offset;

        //      objc_disposeClassPair(classObjCRef);
      errs() << "Is Swift: " << classref->isSwift() << "\n";
      errs() << "Is Swift Registered: " << classRegisteredRef->isSwift() << "\n";
    }
  }
} }
