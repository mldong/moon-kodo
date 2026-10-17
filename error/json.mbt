///|
/// 最小 JSON 读口。只用三件：字符串字段、整数字段、对象数组切片。
///
/// 为什么不用 `derive(@json.FromJson)`：2026-10-17 实测该 derive **读不进 JSON 数字**
/// （结构里一放 `ttl : Int64?`，整份响应就报形状不可读），而 Kodo 的回包里数字字段
/// 恰恰是主体（`fsize`/`putTime`/`expireAt`/`partNumber`）。未声明的多余键它倒是忽略，
/// 所以混合方案最省：结构只管字符串，数字一律走这里的扫描器。

///|
/// 取一个字符串字段。扫到第一个**未被反斜杠保护**的 `"` 为止，
/// 所以 `{"error":"a \" b"}` 读出的是 `a " b` 而不是半句。
pub fn json_string_field(body : String, field : String) -> String? {
  match json_value_at(body, field) {
    None => None
    Some(rest) =>
      match scan_quoted(rest) {
        None => None
        Some(raw) => Some(json_unescape(raw))
      }
  }
}

///|
/// 取一个整数字段（负数照收）。不是数字（缺字段、写成串、越界前的残串）给 `None`。
pub fn json_int_field(body : String, field : String) -> Int64? {
  match json_value_at(body, field) {
    None => None
    Some(rest) => scan_digits(rest)
  }
}

///|
/// 取一个对象数组：`key` 指向的 `[ ... ]` 里的每个顶层 `{...}` 原文。
/// 用于 `parts` 这一族——每个元素再交给 `json_string_field` / `json_int_field` 逐字段读。
/// 元素里的嵌套对象与字符串里的花括号都按层跳过，不算错。
pub fn json_objects(body : String, key : String) -> Array[String] {
  let out : Array[String] = []
  let marker = "\"" + key + "\""
  let texts = body.to_array()
  match find_index_of(texts, marker) {
    None => out
    Some(at) => {
      // 先跳到 `[`
      let mut i = at + marker.length()
      let mut started = false
      while i < texts.length() && !started {
        if texts[i] == '[' {
          started = true
        } else if texts[i] == ':' || texts[i] == ' ' || texts[i] == '\t' {
          i = i + 1
        } else if texts[i].is_whitespace() {
          i = i + 1
        } else {
          // `:` 之后直接是数字或别的形状：这一档我们不需要
          i = texts.length()
        }
      }
      if started {
        collect_objects(texts, i + 1, out)
      }
      out
    }
  }
}

///|
/// 取一个**字符串**数组：`key` 指向的 `[ "a", "b" ]`。列举回包的
/// `commonPrefixes` 就走这一档（对象数组那一族走 `json_objects`）。
/// 串里的转义照 `json_unescape` 解；`]` 只在串外才算收尾。
pub fn json_string_array(body : String, key : String) -> Array[String] {
  let out : Array[String] = []
  let texts = body.to_array()
  let label = "\"" + key + "\""
  match find_index_of(texts, label) {
    None => out
    Some(at) => {
      let mut i = at + label.length()
      let mut started = false
      while i < texts.length() && !started {
        if texts[i] == '[' {
          started = true
        } else if texts[i] == ':' || texts[i].is_whitespace() {
          i = i + 1
        } else {
          i = texts.length()
        }
      }
      if started {
        i = i + 1
        let mut in_string = false
        let mut escaped = false
        let mut from = i
        while i < texts.length() {
          let ch = texts[i]
          if in_string {
            if escaped {
              escaped = false
            } else if ch == '\\' {
              escaped = true
            } else if ch == '"' {
              out.push(json_unescape(slice_chars(texts, from, i)))
              in_string = false
            }
          } else if ch == '"' {
            in_string = true
            from = i + 1
          } else if ch == ']' {
            i = texts.length()
          }
          i = i + 1
        }
      }
      out
    }
  }
}

///|
fn collect_objects(
  chars : Array[Char],
  start : Int32,
  out : Array[String],
) -> Unit {
  let mut i = start
  let mut depth = 0
  let mut object_start : Int32? = None
  let mut in_string = false
  let mut escaped = false
  while i < chars.length() {
    let ch = chars[i]
    if in_string {
      // 串内的花括号不算层：`{"a":"}{"}` 只有一个对象
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        in_string = false
      }
    } else if ch == '"' {
      in_string = true
    } else if ch == '{' {
      depth = depth + 1
      if depth == 1 {
        object_start = Some(i)
      }
    } else if ch == '}' {
      depth = depth - 1
      if depth == 0 {
        match object_start {
          None => ()
          Some(from) => {
            out.push(slice_chars(chars, from, i + 1))
            object_start = None
          }
        }
      }
    } else if ch == ']' && depth == 0 {
      i = chars.length()
    }
    i = i + 1
  }
}

///|
fn slice_chars(chars : Array[Char], from : Int32, to : Int32) -> String {
  let mut text = ""
  let mut i = from
  while i < to && i < chars.length() {
    text = text + chars[i].to_string()
    i = i + 1
  }
  text
}

///|
fn find_index_of(chars : Array[Char], needle : String) -> Int32? {
  let target = needle.to_array()
  if target.length() == 0 || chars.length() < target.length() {
    None
  } else {
    let mut i = 0
    let mut found : Int32? = None
    while i + target.length() <= chars.length() && found is None {
      let mut j = 0
      while j < target.length() && chars[i + j] == target[j] {
        j = j + 1
      }
      if j == target.length() {
        found = Some(i)
      } else {
        i = i + 1
      }
    }
    found
  }
}

///|
/// 定位到 `"field"` 之后冒号右侧第一个非空白字符处。
fn json_value_at(body : String, field : String) -> String? {
  let texts = body.to_array()
  let marker = "\"" + field + "\""
  match find_index_of(texts, marker) {
    None => None
    Some(at) => {
      let after = slice_chars(texts, at + marker.length(), texts.length())
      match after.find(":") {
        None => None
        Some(colon) => {
          let rest = after[colon + 1:after.length()].trim_start().to_owned()
          if rest.is_empty() {
            None
          } else {
            Some(rest)
          }
        }
      }
    }
  }
}

///|
fn scan_quoted(rest : String) -> String? {
  if !rest.has_prefix("\"") {
    None
  } else {
    let open = rest[1:rest.length()].to_owned()
    let chars = open.to_array()
    let mut i = 0
    let mut escaped = false
    while i < chars.length() {
      let ch = chars[i]
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        return Some(slice_chars(chars, 0, i))
      }
      i = i + 1
    }
    None
  }
}

///|
fn scan_digits(text : String) -> Int64? {
  let chars = text.to_array()
  let mut i = 0
  let mut negative = false
  if chars.length() > 0 && chars[0] == '-' {
    negative = true
    i = 1
  }
  let mut value = 0L
  let mut seen = false
  while i < chars.length() {
    let code = chars[i].to_int()
    if code >= 48 && code <= 57 {
      value = value * 10L + (code - 48).to_int64()
      seen = true
      i = i + 1
    } else {
      i = chars.length()
    }
  }
  if !seen {
    None
  } else if negative {
    Some(0L - value)
  } else {
    Some(value)
  }
}

///|
/// 只解回包里会出现的这几个转义（顺序承重：`\\` 先解会把 `\"` 拆坏，故反斜杠最后）。
fn json_unescape(text : String) -> String {
  let mut out = ""
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch != '\\' {
      out = out + ch.to_string()
      i = i + 1
    } else {
      match chars[i + 1] {
        'n' => {
          out = out + "\n"
          i = i + 2
        }
        't' => {
          out = out + "\t"
          i = i + 2
        }
        'r' => {
          out = out + "\r"
          i = i + 2
        }
        'b' => {
          out = out + "\\b"
          i = i + 2
        }
        'f' => {
          out = out + "\\f"
          i = i + 2
        }
        '"' => {
          out = out + "\""
          i = i + 2
        }
        '\\' => {
          out = out + "\\"
          i = i + 2
        }
        '/' => {
          out = out + "/"
          i = i + 2
        }
        _ => {
          // 不认的转义原样留着（含结尾落单的 `\`），不假装解出来了
          out = out + ch.to_string()
          i = i + 1
        }
      }
    }
  }
  out
}

///|
/// 最小 JSON 字符串转义：引号、反斜杠与控制字符。Kodo 的 `saveKey`/`returnBody` 里
/// 会出现 `\n` 与引号，不转义就签坏；分块 complete 的 body 也走同一份写法。
pub fn json_quote(text : String) -> String {
  let mut out = "\""
  for ch in text {
    let code = ch.to_int()
    if ch == '"' {
      out = out + "\\\""
    } else if ch == '\\' {
      out = out + "\\\\"
    } else if code == 8 {
      out = out + "\\b"
    } else if code == 9 {
      out = out + "\\t"
    } else if code == 10 {
      out = out + "\\n"
    } else if code == 12 {
      out = out + "\\f"
    } else if code == 13 {
      out = out + "\\r"
    } else if code < 32 {
      out = out + "\\u00" + two_hex(code)
    } else {
      out = out + ch.to_string()
    }
  }
  out + "\""
}

///|
/// 一个 0..255 的码点写成两个十六进制字符（JSON 的 `\u00XX` 那一段）。
/// 用查表而不是位运算：本工具链上 `String[i]` 交出的是 UTF-16 码元（`UInt16`），
/// 码元再变回字符要绕路，短表逐字符存成 `Array[Char]` 最好核。
fn two_hex(value : Int32) -> String {
  let digits : Array[Char] = []
  for ch in "0123456789abcdef" {
    digits.push(ch)
  }
  digits[value / 16].to_string() + digits[value % 16].to_string()
}

///|
/// 列出一个对象里的**字符串**键值对（顶层，深度 1）。给 `x-qn-meta` 这一族用：
/// 2026-10-17 真桶现读，`stat` 把用户元数据回成 `"x-qn-meta":{"case":"qiniu"}` 这样的
/// **嵌套对象**，不是 `x-qn-meta-case` 那种平铺键——写侧是平铺字段，读侧是嵌套对象。
/// 只收字符串值；数字/布尔/嵌套一律跳过（不猜它们的写法，也不冒充读到了）。
pub fn json_string_pairs(object : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  // 数组不是一张键值表：`["x","y"]` 混进来会被读成一对一对的假键值，直接不收
  if !object.trim().has_prefix("{") {
    out
  } else {
    json_pairs_in(object, out)
  }
}

///|
fn json_pairs_in(
  object : String,
  out : Array[(String, String)],
) -> Array[(String, String)] {
  let texts = object.to_array()
  let mut depth = 0
  let mut i = 0
  let mut pending : String? = None
  while i < texts.length() {
    let ch = texts[i]
    if ch == '"' {
      // 一次读完整个串并停在收尾引号**之后**：靠外层再 +1 会跳到下一个字符上，
      // 键与值就会错一格
      let read = read_string_pair(texts, i)
      let text = read.0
      i = read.1
      if depth == 1 {
        match pending {
          None => pending = Some(text)
          Some(name) => {
            out.push((name, text))
            pending = None
          }
        }
      }
    } else {
      if ch == '{' || ch == '[' {
        depth = depth + 1
      } else if ch == '}' || ch == ']' {
        depth = depth - 1
        pending = None
      } else if ch == ',' {
        // 一段结束：没配上值的半个键不留在状态里（`{"a":1,"b":"c"}` 里的 `a` 不该抢走 `b`）
        pending = None
      }
      i = i + 1
    }
  }
  out
}

///|
/// 从 `at`（指向开引号）读一个 JSON 串：返回内容与收尾引号**之后**的下标。
/// 内容里的转义交给 `json_unescape`，所以扫描只认反斜杠吃掉下一个字符。
fn read_string_pair(chars : Array[Char], at : Int32) -> (String, Int32) {
  let mut i = at + 1
  let mut escaped = false
  while i < chars.length() {
    let ch = chars[i]
    if escaped {
      escaped = false
    } else if ch == '\\' {
      escaped = true
    } else if ch == '"' {
      return (json_unescape(slice_chars(chars, at + 1, i)), i + 1)
    }
    i = i + 1
  }
  // 串没闭合：读到尾，不把半句冒充成完整值
  ("", chars.length())
}

///|
/// 取一个**对象**字段：`key` 指向的 `{...}` 原文（含花括号）。
/// `json_objects` 管的是 `"key":[{..},{..}]` 那一族，嵌套对象是另一档——
/// `x-qn-meta` 走这一档。键不存在、值不是对象、或对象没闭合都给 `None`。
pub fn json_object_field(body : String, key : String) -> String? {
  let texts = body.to_array()
  let label = "\"" + key + "\""
  match find_index_of(texts, label) {
    None => None
    Some(at) => {
      let mut i = at + label.length()
      let mut ready = false
      while i < texts.length() && !ready {
        let ch = texts[i]
        if ch == '{' {
          ready = true
        } else if ch == ':' || ch.is_whitespace() {
          i = i + 1
        } else {
          i = texts.length()
        }
      }
      if !ready {
        None
      } else {
        let mut depth = 0
        let mut in_string = false
        let mut escaped = false
        let mut end = i
        while end < texts.length() {
          let ch = texts[end]
          if in_string {
            if escaped {
              escaped = false
            } else if ch == '\\' {
              escaped = true
            } else if ch == '"' {
              in_string = false
            }
          } else if ch == '"' {
            in_string = true
          } else if ch == '{' {
            depth = depth + 1
          } else if ch == '}' {
            depth = depth - 1
            if depth == 0 {
              return Some(slice_chars(texts, i, end + 1))
            }
          }
          end = end + 1
        }
        None
      }
    }
  }
}

///|
/// 取一个布尔字段（`truncated` 这一族）。写成串或数字的都不算（`None`），
/// 免得把"读到别的形状"当成"读到 false"。
pub fn json_bool_field(body : String, field : String) -> Bool? {
  match json_value_at(body, field) {
    None => None
    Some(rest) =>
      if rest.has_prefix("true") {
        Some(true)
      } else if rest.has_prefix("false") {
        Some(false)
      } else {
        None
      }
  }
}
