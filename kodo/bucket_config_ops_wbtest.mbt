///|
test "cors rules json uses the official singular keys" {
  let rules = [
    CorsRule::new(["https://a.example"], ["GET", "PUT"]).with_extra(
      allowed_headers=["*"],
      exposed_headers=["x-reqid"],
      max_age=3600L,
    ),
    CorsRule::new(["*"], ["GET"]),
  ]
  assert_eq(
    cors_rules_json(rules),
    "[" +
    "{\"allowed_origin\":[\"https://a.example\"],\"allowed_method\":[\"GET\",\"PUT\"]," +
    "\"allowed_header\":[\"*\"],\"exposed_header\":[\"x-reqid\"],\"max_age\":3600}," +
    "{\"allowed_origin\":[\"*\"],\"allowed_method\":[\"GET\"]," +
    "\"allowed_header\":[],\"exposed_header\":[],\"max_age\":0}" +
    "]",
  )
}

///|
test "cors rules parse reads arrays and max_age" {
  let text = "[" +
    "{\"allowed_origin\":[\"https://a.example\"],\"allowed_method\":[\"GET\"]," +
    "\"allowed_header\":[\"x-token\"],\"exposed_header\":[],\"max_age\":600}," +
    "{\"allowed_origin\":[\"*\"],\"allowed_method\":[\"GET\",\"HEAD\"]," +
    "\"allowed_header\":[],\"exposed_header\":[\"etag\"],\"max_age\":0}" +
    "]"
  let rules = parse_cors_rules(text)
  assert_eq(rules.length(), 2)
  assert_eq(rules[0].allowed_origins, ["https://a.example"])
  assert_eq(rules[0].allowed_headers, ["x-token"])
  assert_eq(rules[0].max_age, 600L)
  assert_eq(rules[1].allowed_methods, ["GET", "HEAD"])
  assert_eq(rules[1].exposed_headers, ["etag"])
}

///|
test "lifecycle rule query keeps the official field order and encodes values" {
  let rule = LifecycleRule::{
    name: "expire_logs",
    prefix: "logs/2026 10",
    delete_after_days: 30L,
    to_line_after_days: 7L,
    to_archive_ir_after_days: 0L,
    to_archive_after_days: -1L,
    to_deep_archive_after_days: 90L,
  }
  assert_eq(
    lifecycle_rule_query(rule),
    "name=expire_logs&prefix=logs%2F2026+10&delete_after_days=30&to_line_after_days=7" +
    "&to_archive_ir_after_days=0&to_archive_after_days=-1&to_deep_archive_after_days=90",
  )
}

///|
test "bucket info parse keeps flat fields and refer lists" {
  let text = "{\"zone\":\"z0\",\"region\":\"z0\",\"private\":1,\"protected\":0," +
    "\"max_age\":31536000,\"no_index_page\":1,\"global\":false," +
    "\"anti_leech_mode\":1,\"no_refer\":false," +
    "\"refer_wl\":[\"*.a.example\",\"b.example\"],\"refer_bl\":[]}"
  let info = bucket_info_of(text)
  assert_eq(info.zone, Some("z0"))
  assert_eq(info.private_flag, Some(1L))
  assert_eq(info.max_age, Some(31536000L))
  assert_eq(info.global, Some(false))
  assert_eq(info.refer_white, ["*.a.example", "b.example"])
  assert_eq(info.refer_black.length(), 0)
}

///|
test "quota parse reads size and count" {
  let quota = bucket_quota_of("{\"size\":1073741824,\"count\":1000}")
  assert_eq(quota.size, Some(1073741824L))
  assert_eq(quota.count, Some(1000L))
}

///|
test "event rules parse keeps arrays and optional keys" {
  let text = "[" +
    "{\"name\":\"notify\",\"prefix\":\"img/\",\"suffix\":\".jpg\"," +
    "\"events\":[\"put\",\"delete\"],\"callback_urls\":[\"https://cb.example/hook\"]," +
    "\"access_key\":\"ak\",\"host\":\"cb.example\"}," +
    "{\"name\":\"minimal\",\"events\":[\"put\"],\"callback_urls\":[]}" +
    "]"
  let rules = parse_event_rules(text)
  assert_eq(rules.length(), 2)
  assert_eq(rules[0].events, ["put", "delete"])
  assert_eq(rules[0].callback_urls, ["https://cb.example/hook"])
  assert_eq(rules[0].host, "cb.example")
  assert_eq(rules[1].prefix, "")
  assert_eq(rules[1].access_key, "")
}
