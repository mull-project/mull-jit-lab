#include <Cocoa/Cocoa.h>
#include <CoreFoundation/CoreFoundation.h>
// #include <CoreFoundation/CFRuntime.h>
#include <cstdio>
#include <iostream>
#include <objc/objc-load.h>
#include <objc/runtime.h>
#include <dlfcn.h>

extern "C" int main (int, char**) {
	
	SEL p = sel_registerName("alloc");
	Class cls = objc_getClass("NSAutoreleasePool");
	printf("%p %p\n", p, cls);
    int error;
    std::cout << "==== step 1" << std::endl;

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [pool release];

    std::cout << "==== step 2" << std::endl;

    return 0;
}

