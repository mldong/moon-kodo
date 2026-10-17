///|
/// Kodo 的错误形状。官方 `QiniuException` 把两件事塞进同一个 `code()`：真 HTTP
/// 状态码，和四个**本地伪码**（`-1` 网络断、`-2` 取消、`-3` 非法文件、`-4` 非法参数，
/// `common/QiniuException.java`）。混在一个整数里就会出"把 `-1` 当 500 处理"这种错，
/// 所以这里分两族：`Service` 只装真 HTTP 读数，本地拒掉的走其它臂，伪码由
/// `pseudo_code` 现给。
pub(all) struct ServiceError {
  status : Int32
  /// 响应体里的 `error` 字段；读不出原文时是体的一段截断
  error : String
  /// `X-Reqid`，报障时要的那串
  req_id : String?
} derive(Eq)

///|
pub(all) suberror KodoError {
  BadParam(String)
  BadFile(String)
  Cancelled(String)
  Network(String)
  Service(ServiceError)
  /// 2xx 但回包缺必需字段（`uploadId` / `etag` / `md5`）。官方没有这一档——它包成
  /// `QiniuException(Exception)`，`code()` 落到 `-1`，与"网络断"同数。我们单列一档：
  /// 把"服务端答了但没答全"混进网络错误，会把重试策略带偏。
  BadResponse(String)
} derive(Eq)

///|
/// 官方伪码；`Service` 那一档**没有**伪码，它的读数就是 `status`。
pub fn KodoError::pseudo_code(self : KodoError) -> Int32? {
  match self {
    BadParam(_) => Some(-4)
    BadFile(_) => Some(-3)
    Cancelled(_) => Some(-2)
    Network(_) => Some(-1)
    Service(_) => None
    BadResponse(_) => None
  }
}

///|
/// 612 是 Kodo 表示"对象不存在"的真 HTTP 状态码。参照件 `QiniuKodoFileStorage`
/// 在 `stat` 的异常里就是认这一个数（`:478`），适配层的 `NotFound` 映射要经由它。
pub fn KodoError::is_not_found(self : KodoError) -> Bool {
  match self {
    Service(s) => s.status == 612
    _ => false
  }
}

///|
/// 给适配层与日志用的文案：伪码档与真 HTTP 码分开写，读出数的人一眼能分
/// "本地就没让过" 与 "服务端拒了"。
pub fn KodoError::text(self : KodoError) -> String {
  match self {
    BadParam(m) => "kodo bad param(-4): " + m
    BadResponse(m) => "kodo bad response: " + m
    BadFile(m) => "kodo bad file(-3): " + m
    Cancelled(m) => "kodo cancelled(-2): " + m
    Network(m) => "kodo network(-1): " + m
    Service(s) => {
      let head = "kodo service(" + s.status.to_string() + "): " + s.error
      match s.req_id {
        Some(id) => head + " reqid=" + id
        None => head
      }
    }
  }
}

///|
/// 解析一具 Kodo 错误响应。`body` 形如 `{"error":"..."}`；体读不出或没那个字段时，
/// 拿原文截断当 `error`，**不许**把"解析失败"当成"没有错误内容"。
pub fn service_error(
  status : Int32,
  body : String,
  req_id : String?,
) -> ServiceError {
  let text = body.trim().to_owned()
  let truncated = text.length() > 240
  let cut = text[0:if truncated { 240 } else { text.length() }].to_owned()
  let fallback = if text.is_empty() {
    "empty response body"
  } else if truncated {
    cut + "..."
  } else {
    cut
  }
  let error = match json_string_field(text, "error") {
    None => fallback
    Some(value) => value
  }
  ServiceError::{ status, error, req_id, }
}
