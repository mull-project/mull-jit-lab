#include "SomeClass.hpp"

#import <XCTest/XCTest.h>

// @implementation FirstClass_Subclass_Subclass
// - (id)init {
//     self = [super init];
//     self.uniqueProperty3 = @"FirstClass_Subclass_Subclass@uniqueProperty";
//     return self;
// }
// + (void)clazzMethod {
//     [super clazzMethod];
//     NSLog(@"FirstClass_Subclass_Subclass +clazzMethod\n");
// }

// - (BOOL)hello {
//     [super hello];
//     NSLog(@"FirstClass_Subclass_Subclass -hello: %@ %@\n",
//            self.theSameProperty, self.uniqueProperty3);
//     return YES;
// }
// @end

@implementation FirstClass
- (id)init {
    self = [super init];
    self.theSameProperty = @"The same property";
    self.uniqueProperty1 = @"FirstClass@uniqueProperty";
    return self;
}
+ (void)clazzMethod {
    NSLog(@"FirstClass +clazzMethod\n");
}
- (BOOL)hello {
    NSLog(@"FirstClass -hello %@ %@", self.theSameProperty, self.uniqueProperty1);
    return YES;
}
@end

// @implementation FirstClass_Subclass
// - (id)init {
//     self = [super init];
//     self.uniqueProperty2 = @"FirstClass_Subclass@uniqueProperty";
//     return self;
// }
// + (void)clazzMethod {
//     [super clazzMethod];
//     NSLog(@"FirstClass_Subclass +clazzMethod\n");
// }

// - (BOOL)hello {
//     [super hello];
//     NSLog(@"FirstClass_Subclass -hello: %@ %@\n",
//            self.theSameProperty, self.uniqueProperty2);
//     return YES;
// }
// @end

// @interface FooTest : XCTestCase
// @end

// @implementation FooTest
// - (void)testFoo {
//   NSLog(@"Success! Runtime sees the FooTest class!\n");
//   XCTAssert([[FirstClass_Subclass_Subclass new] hello]);
// }
// - (void)testFoo2 {
//   XCTAssert(NO);
// }

// @end
