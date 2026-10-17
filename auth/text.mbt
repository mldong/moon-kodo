///|
/// ASCII 小写。core 只有 `Char::to_ascii_lowercase`，没有整串的（hutool 也只有
/// `lower_first`），而协议里做大小写无关比较的只有头名与 MIME 这两族短串。
/// 非 ASCII 字符原样留着——头名本来也不允许出现它们。
pub fn ascii_lower(text : String) -> String {
  let mut out = ""
  for ch in text {
    out = out + ch.to_ascii_lowercase().to_string()
  }
  out
}

///|
/// Go `textproto` 的 MIME 头名规范化（官方 `canonicalMIMEHeaderKey` 照它抄）：
/// 首字母与每个 `-` 之后的字母大写，其余小写；出现任何非 token 字符就**原样返回**。
fn canonical_mime_header_key(name : String) -> String {
  for b in @utf8.encode(name) {
    if !is_token_byte(b) {
      return name
    }
  }
  let mut out = ""
  let mut up = true
  for ch in name {
    let moved = if up {
      ch.to_ascii_uppercase()
    } else {
      ch.to_ascii_lowercase()
    }
    out = out + moved.to_string()
    up = ch == '-'
  }
  out
}

///|
/// 官方 `genTokenTable` 白名单的那批字符（`util/Auth.java:141-145`）：
/// `!#$%&'*+-.0-9A-Z^_`a-z|~`。表里**没有** `( ) < > @ , ; : [ ] ? / = 空格`，
/// 也当然没有非 ASCII——命中不了就是"非法头名字节"，规范化函数会原样返回整串。
fn is_token_byte(b : Byte) -> Bool {
  let code = b.to_int()
  if code < 33 || code > 126 {
    false
  } else {
    match code.to_char() {
      None => false
      Some(ch) => token_table().contains(ch)
    }
  }
}

///|
fn token_table() -> Array[Char] {
  let out : Array[Char] = []
  for
    ch in "!#$%&'*+-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ^_`abcdefghijklmnopqrstuvwxyz|~" {
    out.push(ch)
  }
  out
}
