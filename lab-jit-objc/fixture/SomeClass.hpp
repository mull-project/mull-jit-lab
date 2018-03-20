#include <Cocoa/Cocoa.h>
#include <CoreFoundation/CoreFoundation.h>

@interface FirstClass : NSObject
@property (nonatomic, strong) NSString *theSameProperty;
@property (nonatomic, strong) NSString *uniqueProperty1;
+ (void)clazzMethod;
- (BOOL)hello;
@end

@interface FirstClass_Subclass : FirstClass
@property (nonatomic, strong) NSString *uniqueProperty2;
+ (void)clazzMethod;
- (BOOL)hello;
@end

@interface FirstClass_Subclass_Subclass : FirstClass_Subclass
@property (nonatomic, strong) NSString *uniqueProperty3;
+ (void)clazzMethod;
- (BOOL)hello;
@end
