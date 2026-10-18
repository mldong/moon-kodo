///|
/// 错误文案这条纪律的用例：私有下载 URL 的 query 是凭据本体（`?e=<到期时刻>&token=<ak>:<签名>`），
/// UC 探测那条更把 `?ak=<access key>` 直接挂在串上；任何把它带进错误串的通道都要在出本库之前
/// 被隐去。传输层对 `InvalidRequest` 的几档文案是**原样嵌 url** 的（`url 缺 :// 分隔`、
/// `url 带 fragment`、`url 缺 authority`、`pathless query`），所以这一档不是假想敌。
/// 本包有两个出口：`transport_text` 与 `transport_failure`，两处都得看着——只测一处会留另一处裸奔。
/// 夹具里的键、签名、主机全是我们编出来的串，不对应任何真凭据。

///|
test "问号之后一律隐去：token 与探测串的 ak 不出现在错误串里" {
  let leaky = "url 缺 :// 分隔：https://placeholder-host.qiniucdn.example/k.txt?e=1893456000&token=AccessToken000000000000000000000000000:deadbeefdeadbeefdeadbeefdeadbeefdead"
  let folded = redact_query(leaky)
  assert_true(folded.find("token") is None)
  assert_true(folded.find("AccessToken") is None)
  assert_true(folded.find("e=1893456000") is None)
  assert_true(
    folded.has_prefix(
      "url 缺 :// 分隔：https://placeholder-host.qiniucdn.example/k.txt?<redacted>",
    ),
  )
  // UC 探测那条 URL 带的是 access key 本体，同一档判据。注意这一档的模板自己就写了个 `?`
  // （"无 / 直接触 ?"），第一个问号落在文案里，所以连主机一起没了——隐去更狠，读数也照实在这里钉住
  assert_eq(
    redact_query(
      "pathless query（无 / 直接触 ?）官方底座接不了：https://uc.qiniuapi.example/v4/query?ak=AccessToken000000000000000000000000000&bucket=placeholder",
    ),
    "pathless query（无 / 直接触 ?<redacted>",
  )
  // 隐去长在 redact_query 里没用——调用方读到的是两个出口的产物，两处都必须接上
  assert_true(
    transport_text(@transport.TransportError::InvalidRequest(leaky)).find(
      "AccessToken",
    )
    is None,
  )
  assert_true(
    transport_failure(@transport.TransportError::InvalidRequest(leaky))
    .text()
    .find("AccessToken")
    is None,
  )
}

///|
test "建连失败那一档本来只到源站，隐去这步不该动它一个字" {
  let detail = "建连失败（https://placeholder-host.qiniup.example）：TlsError"
  assert_eq(redact_query(detail), detail)
  assert_eq(
    transport_text(@transport.TransportError::Network(detail)),
    "network: " + detail,
  )
  assert_eq(
    transport_failure(@transport.TransportError::Network(detail)).text(),
    "kodo network(-1): " + detail,
  )
  assert_eq(transport_text(@transport.TransportError::Timeout), "timeout")
  assert_eq(
    transport_failure(@transport.TransportError::Timeout).text(),
    "kodo network(-1): timeout",
  )
}
