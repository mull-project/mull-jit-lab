
pub fn sum(a: i32, b: i32) -> i32 {
  return a + b;
}

#[test]
fn foo_test_sum() {
  assert!(sum(3, 4) == 7);
}

