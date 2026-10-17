///|
/// 拆出一个绝对 URL 的**未解码**路径与查询串。
///
/// 这里刻意不借用 core 的 `Uri`：签名喂的是 `getRawPath()` / `getRawQuery()` 那两份
/// 原文，先解析再重拼会把 `%2F` 之类的转义抹平，签名就对不上了。
///
/// - 返回 `(raw_path, query)`：`None` 表示 URL 里根本没有 `?`，`Some("")` 表示有 `?`
///   但查询为空——这两档在两个签名族里的处理**不一样**（QBox 跳过空查询，Qiniu 照喂），
///   所以不能合并成一个空串。
fn raw_path_query(url : String) -> (String, String?) raise @error.KodoError {
  match url.find("://") {
    None =>
      raise @error.BadParam(
        "url carries no scheme, so there is no authority to sign against: " +
        url,
      )
    Some(at) => {
      let rest = url[at + 3:url.length()].to_owned()
      // 没有路径段时官方给的是空串（`URI.create("https://host").getRawPath()` 是 `""`），
      // 补一个 `/` 就签错了字节
      let tail = match rest.find("/") {
        None => ""
        Some(slash) => rest[slash:rest.length()].to_owned()
      }
      match tail.find("?") {
        None => (tail, None)
        Some(q) =>
          (tail[0:q].to_owned(), Some(tail[q + 1:tail.length()].to_owned()))
      }
    }
  }
}

///|
/// URL 的 authority 段，拆成（不带端口的主机名, 端口）。`Qiniu` 签名的 `Host:` 行要用，
/// 官方读 `uri.getHost()` 与 `uri.getPort()`，端口缺省（`-1`）时不拼，这里用 `None` 表示。
fn host_port(url : String) -> (String, Int32?) raise @error.KodoError {
  match url.find("://") {
    None => raise @error.BadParam("url carries no scheme: " + url)
    Some(at) => {
      let rest = url[at + 3:url.length()].to_owned()
      let authority = match rest.find("/") {
        None => rest
        Some(slash) => rest[0:slash].to_owned()
      }
      // 只有末尾那一段可能是端口：IPv6 字面量里的冒号不当端口（本 SDK 不签那种主机名）
      match last_colon(authority) {
        None => (authority, None)
        Some(colon) => {
          let tail = authority[colon + 1:authority.length()].to_owned()
          // 端口位上不是纯数字（`http://host:name/x`）就当没有端口，与 Java
          // `URI.getPort()` 返回 -1 同档
          let port = @string.parse_int(tail) catch { _ => -1 }
          if port > 0 {
            (authority[0:colon].to_owned(), Some(port))
          } else {
            (authority, None)
          }
        }
      }
    }
  }
}

///|
/// `%XX` 还原。`Qiniu` 那一族的签名路径用的是**解码后**的 `uri.getPath()`，而查询串
/// 仍是 raw——这个混搭是官方的形状，照搬并在用例里钉住，不是我们的选择。
/// 逐字节还原，所以 `%E4%B8%AD` 这种一段多字节的转义能拼回原字符。
/// 非法转义（`%zz`、结尾落单的 `%`）原样保留，与 Java `URI` 一致。
fn percent_decode(text : String) -> String {
  let source = @utf8.encode(text)
  let out : Array[Byte] = []
  let mut i = 0
  while i < source.length() {
    let b = source[i]
    if b.to_int() == 0x25 && i + 2 < source.length() {
      let pair = @utf8.decode_lossy(source[i + 1:i + 3])
      match parse_hex_byte(pair) {
        None => {
          out.push(b)
          i = i + 1
        }
        Some(value) => {
          out.push(value)
          i = i + 3
        }
      }
    } else {
      out.push(b)
      i = i + 1
    }
  }
  @utf8.decode_lossy(Bytes::from_array(out))
}

///|
/// 两个十六进制字符 → 一个字节。大小写都收；有非十六进制字符就判 None（`parse_int` 抛，
/// 这里把抛转成 `None`，因为调用方要的是"这不是转义"，不是"这里崩了"）。
fn parse_hex_byte(pair : String) -> Byte? {
  if pair.length() != 2 {
    None
  } else {
    let value = @string.parse_int(pair, base=16) catch { _ => -1 }
    if value >= 0 && value <= 255 {
      Some(value.to_byte())
    } else {
      None
    }
  }
}

///|
/// authority 里最后一个 `:` 的位置。本工具链的 `String` 没有 `rfind`，这里按字节扫；
/// 只在纯 ASCII 的 authority 上给读数（含非 ASCII 时字符下标与字节下标会分叉，
/// 而那种主机名 Java 的 `URI` 自己也解不出来，判"没有端口"最稳）。
fn last_colon(authority : String) -> Int32? {
  let bytes = @utf8.encode(authority)
  if bytes.length() != authority.length() {
    None
  } else {
    let mut found : Int32? = None
    for i in 0..<bytes.length() {
      if bytes[i].to_int() == 0x3A {
        found = Some(i)
      }
    }
    found
  }
}
