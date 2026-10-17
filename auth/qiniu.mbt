///|
/// 时间戳签名那一档的开关。官方 `qiniuAuthorization` 会经 `DefaultHeader` 注入
/// `X-Qiniu-Date`（除非环境里设了 `DISABLE_QINIU_TIMESTAMP_SIGNATURE`），而这个头因为
/// 带 `X-Qiniu-` 前缀，**是要进签名的**。用例不许依赖墙上时钟，所以把时刻做成参数。
pub(all) enum TimestampSign {
  /// 用这个毫秒读数生成 `X-Qiniu-Date`
  On(Int64)
  /// 官方那个 DISABLE 环境变量档：不带时间戳头
  Off
}

///|
/// `X-Qiniu-Date` 的形状：UTC 的 `yyyyMMdd'T'HHmmss'Z'`（官方 `DefaultHeader.xQiniuDate`）。
/// hutool 的 UTC RFC3339 去掉分隔符就是它，与 S3 那把 `x-amz-date` 同一套写法。
fn qiniu_date_utc(epoch_millis : Int64) -> String {
  let wall = @date.DateTime::from_epoch_millis(epoch_millis, 0)
  let whole_second = wall.to_epoch_millis(0) - wall.milli.to_int64()
  let iso = @date.to_rfc3339(whole_second, 0)
  let flat = iso.replace_all(old="-", new="")
  flat.replace_all(old=":", new="")
}

///|
/// `signQiniuAuthorization` 的待签串，拆出来是为了能让用例直接断言"喂进去的到底是哪几行"。
///
/// 三处形状差异必须照官方，别顺手统一：
/// - 路径喂**解码后**的 `uri.getPath()`，查询喂**原始**的 `uri.getRawQuery()`；
/// - 查询只要 `?` 出现过就喂（空查询也喂一个 `?`），这与 QBox 那族"空查询不喂"相反；
/// - `Host` 用不带端口的主机名，端口只在 `> 0` 时拼上。
fn qiniu_signing_string(
  url : String,
  verb : String,
  body : Bytes?,
  headers : Array[@transport.Header],
) -> String raise @error.KodoError {
  let verb = if verb.is_empty() { "GET" } else { verb }
  let (raw_path, raw_query) = raw_path_query(url)
  let (host, port) = host_port(url)
  let buf = StringBuilder()
  buf.write_string(verb + " " + percent_decode(raw_path))
  match raw_query {
    None => ()
    Some(query) => {
      buf.write_string("?")
      buf.write_string(query)
    }
  }
  buf.write_string("\nHost: ")
  buf.write_string(host)
  match port {
    None => ()
    Some(value) =>
      if value > 0 {
        buf.write_string(":")
        buf.write_string(value.to_string())
      }
  }
  let content_type = header_value(headers, "content-type")
  match content_type {
    None => ()
    Some(kind) => {
      buf.write_string("\nContent-Type: ")
      buf.write_string(kind)
    }
  }
  for line in signed_x_qiniu_headers(headers) {
    buf.write_string("\n")
    buf.write_string(line.name)
    buf.write_string(": ")
    buf.write_string(line.value)
  }
  buf.write_string("\n\n")
  // body 只在"非空 + 有 content-type + 不是 octet-stream"时进签名（官方 `:453-456`）
  match (body, content_type) {
    (Some(payload), Some(kind)) =>
      if !kind.is_empty() &&
        kind != "application/octet-stream" &&
        payload.length() > 0 {
        buf.write_string(@utf8.decode_lossy(payload))
      }
    _ => ()
  }
  buf.to_string()
}

///|
/// `signQiniuAuthorization`：`accessKey:digest`。
pub fn Auth::sign_qiniu_request(
  self : Auth,
  url : String,
  verb : String,
  body~ : Bytes? = None,
  headers~ : Array[@transport.Header] = [],
) -> String raise @error.KodoError {
  self.sign_bytes(@utf8.encode(qiniu_signing_string(url, verb, body, headers)))
}

///|
/// `qiniuAuthorization`：在调用方给的头之后追加 `Authorization: Qiniu ak:digest`，
/// 并按官方默认带上 `X-Qiniu-Date`（`TimestampSign::Off` 就是环境里关掉时间戳签名那一档）。
/// 返回的数组里**不含**官方的 `User-Agent`：那是传输层的自我介绍，与签名无关，
/// 由上层适配器决定。
pub fn Auth::qiniu_authorization(
  self : Auth,
  url : String,
  verb : String,
  body~ : Bytes? = None,
  headers~ : Array[@transport.Header] = [],
  timestamp~ : TimestampSign? = None,
) -> Array[@transport.Header] raise @error.KodoError {
  let moment = timestamp.unwrap_or(TimestampSign::On(@date.now_millis()))
  let signed = match moment {
    Off => headers
    On(millis) =>
      headers +
      [
        @transport.Header::{
          name: "X-Qiniu-Date",
          value: qiniu_date_utc(millis),
        },
      ]
  }
  let digest = self.sign_qiniu_request(url, verb, body~, headers=signed)
  signed +
  [@transport.Header::{ name: "Authorization", value: "Qiniu " + digest, }]
}

///|
/// 取头的值：大小写无关、同名取最后一次（官方走 okhttp 的 `Headers.get`，同一条规则）。
fn header_value(headers : Array[@transport.Header], name : String) -> String? {
  let mut found : String? = None
  let want = ascii_lower(name)
  for h in headers {
    if ascii_lower(h.name) == want {
      found = Some(h.value)
    }
  }
  found
}

///|
/// 参与签名的 `X-Qiniu-` 头：名字长度必须**大于**前缀（官方 `:468` 判的是 `>`，
/// 光一条 `X-Qiniu-` 不算），同名只留最后一次，名字过一遍 MIME 规范化，
/// 最后按 (名字, 值) 升序。
fn signed_x_qiniu_headers(
  headers : Array[@transport.Header],
) -> Array[@transport.Header] {
  let prefix_length = "X-Qiniu-".length()
  // (小写名, 值)：先收一遍是为了让 okhttp 的 `set` 语义（后者覆盖）落在同一槽位上
  let slots : Array[(String, String)] = []
  for h in headers {
    let lower = ascii_lower(h.name)
    if h.name.length() > prefix_length && lower.has_prefix("x-qiniu-") {
      match slots.search_by(slot => slot.0 == lower) {
        Some(i) => slots[i] = (lower, h.value)
        None => slots.push((lower, h.value))
      }
    }
  }
  let picked : Array[@transport.Header] = []
  for slot in slots {
    picked.push(@transport.Header::{
      name: canonical_mime_header_key(slot.0),
      value: slot.1,
    })
  }
  sort_headers(picked)
}

///|
/// 按 (名字, 值) 升序。官方用 `String.compareTo`（UTF-16 码元序），头名与值都是
/// ASCII token 字符，这里按字节序比——对 ASCII 两者同序。
/// 不能用 core 的 `String.compare` 或 `Bytes` 的 `Compare`：两者都先比长度再比内容
/// （MoonBit 写作语法第 143 条），这里要的是 `lexical_compare`。
fn sort_headers(headers : Array[@transport.Header]) -> Array[@transport.Header] {
  headers.sort_by((a, b) => {
    let by_name = @utf8.encode(a.name).lexical_compare(@utf8.encode(b.name))
    if by_name == 0 {
      @utf8.encode(a.value).lexical_compare(@utf8.encode(b.value))
    } else {
      by_name
    }
  })
  headers
}
