import XCTest
import SwiftTestCase

@objc(BinarySearchTest)
public class BinarySearchTest: SwiftTestCase {
  @objc open func methodOfStan() {
    print("methodOfStan()>")
    //raise(SIGINT)
  }

  @objc override open func setUp() {
    //print("setUp() before calling super")

    //super.setUp()

    //print("setUp() before calling methodOfStan")
    //raise(SIGINT)

    methodOfStan()

    //print("setUp() after calling methodOfStan")
  }

  @objc func testFooBarWip() {
    XCTAssert(true)
  }
}
