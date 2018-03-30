import XCTest

@objc(SwiftObjCClass)
public class SwiftObjCClass : XCTestCase {
  @objc
  public func testHello() {
    print("hello from Swift from SwiftObjCClass")
  }
}
