///|
/// 资源与列举族的离线判据：路径串、查询串、编码档与回包读口。
/// 期望值由独立第二实现算出（工装 `d3_vectors.py`：URL-safe Base64 用 python
/// `base64.urlsafe_b64encode`，查询串用**手抄的 Java `URLEncoder` 规则**而不是
/// `quote_plus`——两者在 `~` 与 `*` 上正好相反），列举回包形状取自 2026-10-17 真桶现读。

///|
test "资源族 #0 form_encode 照 Java URLEncoder：保留集、空格、~ 与 * 两档" {
  assert_eq(form_encode("moonfs-kodo-1/"), "moonfs-kodo-1%2F")
  assert_eq(form_encode("/index.html"), "%2Findex.html")
  assert_eq(form_encode("a b"), "a+b")
  assert_eq(form_encode("中文"), "%E4%B8%AD%E6%96%87")
  // Java 编 `~` 但留 `*`：这两档是它与常识相反的地方，必须钉住
  assert_eq(form_encode("a~b"), "a%7Eb")
  assert_eq(form_encode("a*b"), "a*b")
  assert_eq(form_encode("a_b.c-d~e*f"), "a_b.c-d%7Ee*f")
  assert_eq(form_encode("+="), "%2B%3D")
  assert_eq(form_encode("100%"), "100%25")
  assert_eq(form_encode(""), "")
}

///|
test "资源族 #1 force 段是 true/false，不是 1/0" {
  assert_eq(bool_segment(false), "false")
  assert_eq(bool_segment(true), "true")
}

///|
test "资源族 #2 copy / move 路径：entry 段与 force 档" {
  assert_eq(
    copy_path(
      "blog", "moonfs-kodo-1/a.txt", "blog", "moonfs-kodo-1/b.txt", false,
    ),
    "/copy/YmxvZzptb29uZnMta29kby0xL2EudHh0/YmxvZzptb29uZnMta29kby0xL2IudHh0/force/false",
  )
  assert_eq(
    move_path(
      "blog", "moonfs-kodo-1/a.txt", "blog", "moonfs-kodo-1/b.txt", true,
    ),
    "/move/YmxvZzptb29uZnMta29kby0xL2EudHh0/YmxvZzptb29uZnMta29kby0xL2IudHh0/force/true",
  )
  // 跨桶那一档：目标桶名进 entry，不改主机
  assert_eq(
    copy_path("blog", "a.txt", "other", "b.txt", false),
    "/copy/YmxvZzphLnR4dA==/b3RoZXI6Yi50eHQ=/force/false",
  )
}

///|
test "资源族 #3 chgm 与 fetch：mime 与 url 都走 URL-safe Base64" {
  assert_eq(
    change_mime_path("blog", "moonfs-kodo-1/a.txt", "text/plain"),
    "/chgm/YmxvZzptb29uZnMta29kby0xL2EudHh0/mime/dGV4dC9wbGFpbg==",
  )
  assert_eq(
    change_mime_path("blog", "a.txt", "application/xx+yy"),
    "/chgm/YmxvZzphLnR4dA==/mime/YXBwbGljYXRpb24veHgreXk=",
  )
  assert_eq(
    fetch_path(
      "blog", "moonfs-kodo-1/fetched.html", "https://mldong.com/index.html",
    ),
    "/fetch/aHR0cHM6Ly9tbGRvbmcuY29tL2luZGV4Lmh0bWw=/to/YmxvZzptb29uZnMta29kby0xL2ZldGNoZWQuaHRtbA==",
  )
}

///|
test "资源族 #4 查询串：空值不写键、limit 只在正数时写、次序照官方" {
  assert_eq(list_query("blog"), "bucket=blog")
  assert_eq(list_query("blog", limit=100), "bucket=blog&limit=100")
  assert_eq(list_query("blog", prefix=Some("p/")), "bucket=blog&prefix=p%2F")
  // 空串与不给同档（官方 `putNotEmpty`）
  assert_eq(
    list_query("blog", marker=Some(""), prefix=Some(""), delimiter=Some("")),
    "bucket=blog",
  )
  assert_eq(
    list_query("blog", prefix=Some("p/"), limit=-5),
    "bucket=blog&prefix=p%2F",
  )
  assert_eq(
    list_query(
      "blog",
      marker=Some("eyJjIjowfQ=="),
      prefix=Some("moonfs-kodo-1/"),
      delimiter=Some("/"),
      limit=2,
    ),
    "bucket=blog&marker=eyJjIjowfQ%3D%3D&prefix=moonfs-kodo-1%2F&delimiter=%2F&limit=2",
  )
  assert_eq(
    list_query("blog", prefix=Some("moonfs-kodo-1/中文"), delimiter=Some("/")),
    "bucket=blog&prefix=moonfs-kodo-1%2F%E4%B8%AD%E6%96%87&delimiter=%2F",
  )
}

///|
test "资源族 #5 字符串数组读口：commonPrefixes 的三档" {
  assert_eq(
    @error.json_string_array(
      "{\"commonPrefixes\":[\"a/\",\"b/\"]}", "commonPrefixes",
    ),
    ["a/", "b/"],
  )
  assert_eq(
    @error.json_string_array("{\"commonPrefixes\":[]}", "commonPrefixes"),
    [],
  )
  assert_eq(@error.json_string_array("{\"items\":[]}", "commonPrefixes"), [])
  // 串内的转义与 `]`：`["a\"b","c]d"]` 只有两条，右括号不算收尾
  assert_eq(
    @error.json_string_array(
      "{\"commonPrefixes\":[\"a\\\"b\",\"c]d\"]}", "commonPrefixes",
    ),
    ["a\"b", "c]d"],
  )
}

///|
/// 真桶现读的那一份（改名与裁剪自 2026-10-17 `GET {rsf}/list?bucket=&limit=2&delimiter=/`）：
/// `putTime` 是 17 位微秒、`marker` 带 `=`、`is_eof` 缺键。
fn listing_sample() -> String {
  "{\"items\":[{\"key\":\"moonfs-kodo-sample/1.png\",\"hash\":\"FlGZi-fJTzYrntQzTtUWjiSZnh5T\",\"fsize\":6481,\"mimeType\":\"image/png\",\"putTime\":15233563304026743,\"type\":0,\"status\":0,\"md5\":\"200e149dd6f7486373622ae302805ff4\"}],\"commonPrefixes\":[\"moonfs-kodo-sample/inner/\"],\"marker\":\"eyJjIjowLCJrIjoiMTEucG5nIn0=\"}"
}

///|
test "资源族 #6 列举回包：items 逐条读、17 位 putTime 走 Int64、is_eof 缺键当 false" {
  let text = listing_sample()
  let rows = @error.json_objects(text, "items")
  assert_eq(rows.length(), 1)
  assert_eq(
    @error.json_string_field(rows[0], "key"),
    Some("moonfs-kodo-sample/1.png"),
  )
  assert_eq(@error.json_int_field(rows[0], "fsize"), Some(6481L))
  assert_eq(@error.json_int_field(rows[0], "putTime"), Some(15233563304026743L))
  assert_eq(
    @error.json_string_field(rows[0], "md5"),
    Some("200e149dd6f7486373622ae302805ff4"),
  )
  assert_eq(@error.json_string_array(text, "commonPrefixes"), [
    "moonfs-kodo-sample/inner/",
  ])
  assert_eq(
    @error.json_string_field(text, "marker"),
    Some("eyJjIjowLCJrIjoiMTEucG5nIn0="),
  )
  // 缺键＝没到底，不是"读不到就当结束"
  assert_eq(@error.json_bool_field(text, "is_eof"), None)
  assert_eq(@error.json_bool_field("{\"is_eof\":true}", "is_eof"), Some(true))
  // 顶层没有 key 这一档，只有 item 里有：整份 body 上读 "key" 读到的是第一条的
  assert_eq(
    @error.json_string_field(text, "key"),
    Some("moonfs-kodo-sample/1.png"),
  )
}
