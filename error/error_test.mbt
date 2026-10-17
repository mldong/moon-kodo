///|
/// 错误模型的两族读数：伪码档与真 HTTP 档不许混（卡 §7-4）。
test "错误面 #1 伪码只给本地那四档" {
  assert_eq(@error.KodoError::BadParam("x").pseudo_code(), Some(-4))
  assert_eq(@error.KodoError::BadFile("x").pseudo_code(), Some(-3))
  assert_eq(@error.KodoError::Cancelled("x").pseudo_code(), Some(-2))
  assert_eq(@error.KodoError::Network("x").pseudo_code(), Some(-1))
  // Service 那一档的读数就是 status，没有伪码——把 -1 当 500 处理就是这么来的
  let service = @error.KodoError::Service(
    @error.service_error(599, "{\"error\":\"boom\"}", None),
  )
  assert_eq(service.pseudo_code(), None)
}

///|
test "错误面 #2 612 才是不存在" {
  let missing = @error.KodoError::Service(
    @error.service_error(612, "{\"error\":\"no such file\"}", None),
  )
  assert_eq(missing.is_not_found(), true)
  let wrong_key = @error.KodoError::Service(
    @error.service_error(612, "{\"error\":\"\"}", None),
  )
  // 状态码认 612 就够：官方参照件 `QiniuKodoFileStorage:478` 判的也是 `e.code()`
  assert_eq(wrong_key.is_not_found(), true)
  let server = @error.KodoError::Service(
    @error.service_error(599, "{\"error\":\"boom\"}", None),
  )
  assert_eq(server.is_not_found(), false)
  let local_err = @error.KodoError::BadParam("612 出现在文案里也不算")
  assert_eq(local_err.is_not_found(), false)
}

///|
test "错误面 #3 文案把两族分开写" {
  assert_eq(
    @error.KodoError::BadParam("empty key").text(),
    "kodo bad param(-4): empty key",
  )
  assert_eq(
    @error.KodoError::Service(
      @error.service_error(401, "{\"error\":\"bad token\"}", Some("hLcAAAA")),
    ).text(),
    "kodo service(401): bad token reqid=hLcAAAA",
  )
  assert_eq(
    @error.KodoError::Service(
      @error.service_error(401, "{\"error\":\"bad token\"}", None),
    ).text(),
    "kodo service(401): bad token",
  )
}

///|
test "错误面 #4 错误体解析：有 JSON 取字段，没 JSON 留原文" {
  let parsed = @error.service_error(404, "{\"error\":\"no such file\"}", None)
  assert_eq(parsed.status, 404)
  assert_eq(parsed.error, "no such file")
  assert_eq(parsed.req_id, None)

  let escaped = @error.service_error(
    400,
    "{\"error\":\"quote \\\" and back \\\\ slash\"}",
    None,
  )
  assert_eq(escaped.error, "quote \" and back \\ slash")

  let not_json = @error.service_error(500, "gateway blew up", None)
  assert_eq(not_json.error, "gateway blew up")

  let empty = @error.service_error(500, "   ", None)
  assert_eq(empty.error, "empty response body")

  // 超长原文截到 240 再打点，绝不能整段进日志
  let many = "x".repeat(400)
  let long = @error.service_error(500, many, None)
  assert_eq(long.error.length(), 243)
  assert_eq(long.error[240:243].to_owned(), "...")
  assert_eq(long.error[0:240].to_owned(), "x".repeat(240))
}
