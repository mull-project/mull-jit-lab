
import XCTest

//import XCTest

func testee(a: Int, b: Int) -> Int { 
  //print("Sife effect function that we hope to be removed by RemoveVoidCall")

  return a + b;
}

class Hello: XCTestCase {
  func testFoo() {
    print("Hello world")

    print("before successful assert")

    XCTAssertEqual(testee(a: 2, b: 2), 4)
    print("after successful assert")
    print("before failing assert")
    XCTAssertEqual(testee(a: 2, b: 2), 5)
    print("after failing assert")
  }
  func say() {
    print("Say: Hello world")
  }
}

Hello().say()

print("before running XCTest")

let defaultSuite = XCTestSuite.default()
defaultSuite.run()

print("after running XCTest")

