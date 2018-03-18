#include <Cocoa/Cocoa.h>
#include <CoreFoundation/CoreFoundation.h>
// #include <CoreFoundation/CFRuntime.h>
#include <cstdio>
#include <iostream>
#include <objc/objc-load.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include "SomeClass.hpp"
#import "MUT_XCTestDriver.h"

extern "C" void objc_function () {

    SomeClass *someClass = [SomeClass new];
    [someClass hello];

	printf("before test call\n");
	MUT_RunXCTests();
	printf("after test call\n");
}

extern "C" int main (int, char**) {

	objc_function();
	// SEL p = sel_registerName("alloc");
	// Class cls = objc_getClass("NSAutoreleasePool");
	// printf("%p %p\n", p, cls);
 //    int error;
 //    std::cout << "==== step 1" << std::endl;

 //    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
 //    [pool release];

 //    std::cout << "==== step 2" << std::endl;

    return 0;
}

