///|
/// 重试档的判据本体：只在这两个问题上做决定，二者都是纯函数，离线钉死。
///
/// `replayable` 抄的是官方 `Api.Request.canRetry`（`Api.java:956-962`）：
/// 问的是"这次请求还发得出来吗"，不是"失败在哪个相位"。
/// `is_no_answer` 抄的是 `Retry.canRequestRetryAgain`（`Retry.java:27-41`）：
/// 异常没带 response ⇒ 可重试；服务端回过话 ⇒ 一律算最终读数。

///|
test "重试档 #0 可重放 = 无 body 或字节体，流式体不发第二遍" {
  assert_eq(replayable(@transport.RequestBody::Empty), true)
  assert_eq(replayable(@transport.RequestBody::Bytes(@utf8.encode("x"))), true)
  // 流式体那一档在 `retry_test.mbt` 里验：白盒看不到 for "test" 的依赖，造不出 Reader
}

///|
test "重试档 #1 只有「没拿到应答」才重发，参数档与已回话的不算" {
  assert_eq(is_no_answer(@transport.TransportError::Timeout), true)
  assert_eq(is_no_answer(@transport.TransportError::Network("stalled")), true)
  assert_eq(
    is_no_answer(@transport.TransportError::InvalidResponse("半句响应")),
    true,
  )
  // 请求本身不合法：重发一百次也是同一个错，不该被吞
  assert_eq(
    is_no_answer(@transport.TransportError::InvalidRequest("bad url")),
    false,
  )
}

///|
test "重试档 #2 传输失败映射到的错误档：只有参数档落 InvalidInput" {
  assert_eq(
    transport_failure(@transport.TransportError::Timeout).text(),
    "kodo network(-1): timeout",
  )
  assert_eq(
    transport_failure(@transport.TransportError::Network("stalled")).text(),
    "kodo network(-1): stalled",
  )
  assert_eq(
    transport_failure(@transport.TransportError::InvalidRequest("x")).text(),
    "kodo bad param(-4): x",
  )
  assert_eq(
    transport_failure(
      @transport.TransportError::InvalidResponse("half a reply"),
    ).text(),
    "kodo network(-1): half a reply",
  )
}
