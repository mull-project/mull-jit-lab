import XCTest
import SwiftTestCase

@objc(BinarySearchTestWrong)
public class BinarySearchTestWrong: SwiftTestCase {
  @objc open func methodOfStanWrong() {
    print("methodOfStanWrong()>")
    //raise(SIGINT)
  }

  @objc override open func setUp() {
    //print("setUp() before calling super")

    //super.setUp()

    //print("setUp() before calling methodOfStanWrong")
    //raise(SIGINT)

    methodOfStanWrong()
    methodOfStanWrong()
    //print("setUp() after calling methodOfStanWrong")
  }

  @objc func testFooBarWip() {
    print("testFooBarWip()")

    XCTAssert(true)
  }
}
