#include "SomeClass.hpp"

#import <XCTest/XCTest.h>

@implementation SomeClass
+ (void)clazzMethod {

}
- (BOOL)hello {
	[self printHello];
	return YES;
}
- (void)printHello {
	printf("hello sir!\n");
}

@end

@implementation FooClass; @end

@interface FooTest : XCTestCase
@end

@implementation FooTest
- (void)testFoo {
  printf("Success! Runtime sees the FooTest class!\n");
  XCTAssert([[SomeClass new] hello]);
}
- (void)testFoo2 {
  XCTAssert(NO);
}

@end
