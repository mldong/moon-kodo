///|
test "batch paths carry encoded entries and force suffix" {
  let entry = encoded_entry("bucket", Some("a/b.txt"))
  assert_eq(
    batch_op_path("bucket", BatchOp::Delete("a/b.txt")),
    "delete/" + entry,
  )
  assert_eq(batch_op_path("bucket", BatchOp::Stat("a/b.txt")), "stat/" + entry)
  let copy = BatchCopy::{
    from_bucket: None,
    from_key: "a/b.txt",
    to_bucket: None,
    to_key: "c/d.txt",
    force: true,
  }
  assert_eq(
    batch_op_path("bucket", BatchOp::Copy(copy)),
    "copy/" +
    entry +
    "/" +
    encoded_entry("bucket", Some("c/d.txt")) +
    "/force/true",
  )
}

///|
test "batch body joins ops with the official op= form" {
  let body = batch_body("bucket", [BatchOp::Delete("a"), BatchOp::Stat("b")])
  assert_eq(
    body,
    "op=delete/" +
    encoded_entry("bucket", Some("a")) +
    "&op=stat/" +
    encoded_entry("bucket", Some("b")),
  )
}

///|
test "batch result parses code and per-item error" {
  let body = "[{\"code\":200,\"data\":{\"fsize\":3,\"hash\":\"h\"}},{\"code\":612,\"data\":{\"error\":\"no such file\"}}]"
  let result = parse_batch_result(body)
  assert_eq(result.items.length(), 2)
  assert_eq(result.items[0].code, Some(200L))
  assert_eq(result.items[0].error, None)
  assert_eq(result.items[1].code, Some(612L))
  assert_eq(result.items[1].error, Some("no such file"))
  assert_eq(result.body, body)
}
