///|
test "qetag matches official small and empty vectors" {
  assert_eq(qetag(@utf8.encode("hello".view())), "Fqr0xh3cxeii2r7eDztILNmuqUNN")
  assert_eq(qetag(Bytes::from_array([])), "Fg==")
}

///|
test "qetag splits at 4 MiB" {
  let data = Bytes::from_array(Array::make(4194305, b'a'))
  assert_eq(qetag(data), "lieGn00gWdbfwEIHaUpzu4drHeun")
}
