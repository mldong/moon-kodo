///|
test "domain list parses a JSON string array" {
  let body = "[\"cdn.example.com\",\"https://img.example.com\"]"
  let names = @error.json_array_strings(body)
  assert_eq(names.length(), 2)
  assert_eq(names[0], "cdn.example.com")
}
