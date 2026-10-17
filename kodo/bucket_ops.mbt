///|
/// 资源管理族的其余四件＋列举。路径逐条照官方 `BucketManager`（行号是 2026-10-17 现读）：
///
/// - copy  `/copy/{entry}/{entry}/force/{bool}`（`:479-484`）
/// - move  `/move/{entry}/{entry}/force/{bool}`（`:517-522`）
/// - chgm  `/chgm/{entry}/mime/{urlsafe_b64(mime)}`（`:358-363`）
/// - fetch `/fetch/{urlsafe_b64(url)}/to/{entry}`，主机换成交付侧那台（`:571-579` 走 `ioPost`）
/// - list  `GET {rsf}/list?bucket=&marker=&prefix=&delimiter=&limit=`（`:202-224`）
///
/// 签名一律 `Qiniu ` 那一族：rs 系是 POST＋表单 content-type＋空 body，列举是 GET＋无 body。

///|
/// Java `URLEncoder.encode(s, "utf-8")` 的等价写法：保留 `A-Za-z0-9 . - _ *`，空格成 `+`，
/// 其余按 UTF-8 逐字节写 `%XX`（十六进制**大写**）。这一档必须照 Java 而不是照
/// `percent-encoding` 常识——两者在 `~`（Java 编码）与 `*`（Java 保留）上正好相反，
/// 而官方 `StringMap.formString()` 用的就是 `URLEncoder`。
pub fn form_encode(text : String) -> String {
  let mut out = ""
  for ch in text {
    let code = ch.to_int()
    if form_unreserved(code) {
      out = out + ch.to_string()
    } else if code == 32 {
      out = out + "+"
    } else {
      for byte in @utf8.encode(ch.to_string()).to_array() {
        out = out + form_pct(byte.to_int())
      }
    }
  }
  out
}

///|
fn form_unreserved(code : Int32) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 45 ||
  code == 46 ||
  code == 42 ||
  code == 95
}

///|
fn form_pct(code : Int32) -> String {
  let digits : Array[Char] = []
  for ch in "0123456789ABCDEF" {
    digits.push(ch)
  }
  "%" + digits[code / 16].to_string() + digits[code % 16].to_string()
}

///|
/// Java `Boolean.toString()` 的形状：`true` / `false`，不是 `1` / `0`。
/// 官方把 force 直接拼进路径，写错这一档服务端会当非法参数。
pub fn bool_segment(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
pub fn copy_path(
  from_bucket : String,
  from_key : String,
  to_bucket : String,
  to_key : String,
  force : Bool,
) -> String {
  "/copy/" +
  encoded_entry(from_bucket, Some(from_key)) +
  "/" +
  encoded_entry(to_bucket, Some(to_key)) +
  "/force/" +
  bool_segment(force)
}

///|
pub fn move_path(
  from_bucket : String,
  from_key : String,
  to_bucket : String,
  to_key : String,
  force : Bool,
) -> String {
  "/move/" +
  encoded_entry(from_bucket, Some(from_key)) +
  "/" +
  encoded_entry(to_bucket, Some(to_key)) +
  "/force/" +
  bool_segment(force)
}

///|
/// `changeMime`：mime 走 URL-safe Base64（带填充），不是百分号编码。
pub fn change_mime_path(bucket : String, key : String, mime : String) -> String {
  "/chgm/" +
  encoded_entry(bucket, Some(key)) +
  "/mime/" +
  @auth.urlsafe_b64(@utf8.encode(mime))
}

///|
/// `fetch`：待抓的 URL 整体做一次 URL-safe Base64，落到 `to/{entry}`。
pub fn fetch_path(bucket : String, key : String, url : String) -> String {
  "/fetch/" +
  @auth.urlsafe_b64(@utf8.encode(url)) +
  "/to/" +
  encoded_entry(bucket, Some(key))
}

///|
/// 列举的查询串。次序与缺省档都照官方 `listQuery`：`bucket` 必带，
/// `marker` / `prefix` / `delimiter` **空就不写这个键**，`limit` 只在 >0 时写。
pub fn list_query(
  bucket : String,
  marker~ : String? = None,
  prefix~ : String? = None,
  delimiter~ : String? = None,
  limit~ : Int32 = 0,
) -> String {
  let parts : Array[String] = ["bucket=" + form_encode(bucket)]
  append_query_part(parts, "marker", marker)
  append_query_part(parts, "prefix", prefix)
  append_query_part(parts, "delimiter", delimiter)
  if limit > 0 {
    parts.push("limit=" + limit.to_string())
  }
  parts.join("&")
}

///|
fn append_query_part(
  parts : Array[String],
  name : String,
  value : String?,
) -> Unit {
  match value {
    None => ()
    Some(text) =>
      if !text.is_empty() {
        parts.push(name + "=" + form_encode(text))
      }
  }
}

///|
/// 一条已列出的对象。字段全做成可选：不同存储类型/桶配置回的字集不一样。
/// 键名取自 2026-10-17 真桶现读的 `/list` 响应：`key` `hash` `fsize` `mimeType`
/// `putTime`（17 位微秒）`md5` `type` `status`。
pub(all) struct FileInfo {
  key : String
  hash : String?
  fsize : Int64?
  mime_type : String?
  put_time : Int64?
  md5 : String?
} derive(Eq)

///|
pub extend FileInfo with Eq::{equal, not_equal}

///|
/// 一页列举。`is_eof` 那一档官方是**缺键即 false**（`FileListing` 的 boolean 字段），
/// 这里同档：读不到就是没到底。`marker` 缺键表示没有下一页。
pub(all) struct FileListing {
  items : Array[FileInfo]
  common_prefixes : Array[String]
  marker : String?
  is_eof : Bool
  body : String
}

///|
/// `FetchRet` 的读数：抓回来的对象落在哪个 key、多大、摘要与 mime。
pub(all) struct FetchResult {
  key : String?
  hash : String?
  fsize : Int64?
  mime_type : String?
  body : String
}

///|
/// 交付侧（io）主机的 POST：官方 `fetch` 走 `ioPost`，除主机之外与 rs 同形
/// （表单 content-type、空 body、`Qiniu ` 签名）。
async fn Client::io_post(
  self : Client,
  path : String,
) -> @transport.Response raise @error.KodoError {
  let url = self.config.iovip_origin() + path
  let headers = self.auth.qiniu_authorization(url, "POST", body=None, headers=[
    @transport.Header::{ name: "Content-Type", value: @auth.form_mime(), },
  ])
  self.send(@transport.Request::{
    http_method: @transport.Method::Post,
    url,
    headers,
    body: @transport.RequestBody::Empty,
  })
}

///|
/// 列举主机（rsf）的 GET。查询串一旦拼定就整串进签名，所以这里不再改动它。
async fn Client::rsf_get(
  self : Client,
  query : String,
) -> @transport.Response raise @error.KodoError {
  let url = self.config.rsf_origin() + "/list?" + query
  let headers = self.auth.qiniu_authorization(url, "GET", body=None, headers=[])
  self.send(@transport.Request::{
    http_method: @transport.Method::Get,
    url,
    headers,
    body: @transport.RequestBody::Empty,
  })
}

///|
/// 复制。`force=false` 时目标位已有同名对象，Kodo 回 **614**（`file exists`），
/// 这一档原样抛给调用方，不当"不存在"吞掉。
pub async fn Client::copy(
  self : Client,
  from_key : String,
  to_key : String,
  from_bucket~ : String? = None,
  to_bucket~ : String? = None,
  force~ : Bool = false,
) -> Unit raise @error.KodoError {
  let path = copy_path(
    from_bucket.unwrap_or(self.bucket),
    from_key,
    to_bucket.unwrap_or(self.bucket),
    to_key,
    force,
  )
  let _ = self.rs_post(path)
}

///|
/// 移动＝复制成功后删源，服务端一步做完，所以"move 之后源消失"要真读两边。
///
/// 官方那件叫 `move`，本工具链把 `move` 留作关键字，所以这里落 `move_object`
/// （与门面的 `move_object` 入口同名，少一层翻译）。
pub async fn Client::move_object(
  self : Client,
  from_key : String,
  to_key : String,
  from_bucket~ : String? = None,
  to_bucket~ : String? = None,
  force~ : Bool = false,
) -> Unit raise @error.KodoError {
  let path = move_path(
    from_bucket.unwrap_or(self.bucket),
    from_key,
    to_bucket.unwrap_or(self.bucket),
    to_key,
    force,
  )
  let _ = self.rs_post(path)
}

///|
pub async fn Client::change_mime(
  self : Client,
  key : String,
  mime : String,
) -> Unit raise @error.KodoError {
  let path = change_mime_path(self.bucket, key, mime)
  let _ = self.rs_post(path)
}

///|
/// 让服务端去抓一个公网 URL 并存成本桶的 key。抓不回东西不算我们的错：
/// 服务端怎么回（含 4xx）都原样抛。
pub async fn Client::fetch(
  self : Client,
  url : String,
  key : String,
) -> FetchResult raise @error.KodoError {
  if url.is_empty() {
    raise @error.BadParam("fetch needs a source url")
  }
  let path = fetch_path(self.bucket, key, url)
  let response = self.io_post(path)
  let text = read_text(response.body)
  FetchResult::{
    key: @error.json_string_field(text, "key"),
    hash: @error.json_string_field(text, "hash"),
    fsize: @error.json_int_field(text, "fsize"),
    mime_type: @error.json_string_field(text, "mimeType"),
    body: text,
  }
}

///|
/// 单层列举（v1 那档：`/v2/list` 官方已 `@Deprecated`，`BucketManager.java:262-268`）。
/// 带 `delimiter` 时嵌套键折进 `common_prefixes`，`items` 只留单层——
/// KD4 要的就是这一档不混。
pub async fn Client::list_files(
  self : Client,
  prefix~ : String? = None,
  marker~ : String? = None,
  delimiter~ : String? = None,
  limit~ : Int32? = None,
) -> FileListing raise @error.KodoError {
  let query = list_query(
    self.bucket,
    marker~,
    prefix~,
    delimiter~,
    limit=limit.unwrap_or(0),
  )
  let response = self.rsf_get(query)
  let text = read_text(response.body)
  let items : Array[FileInfo] = []
  for row in @error.json_objects(text, "items") {
    let key = match @error.json_string_field(row, "key") {
      None => raise @error.BadResponse("listing row without key: " + row)
      Some(name) => name
    }
    items.push(FileInfo::{
      key,
      hash: @error.json_string_field(row, "hash"),
      fsize: @error.json_int_field(row, "fsize"),
      mime_type: @error.json_string_field(row, "mimeType"),
      put_time: @error.json_int_field(row, "putTime"),
      md5: @error.json_string_field(row, "md5"),
    })
  }
  FileListing::{
    items,
    common_prefixes: @error.json_string_array(text, "commonPrefixes"),
    marker: @error.json_string_field(text, "marker"),
    is_eof: @error.json_bool_field(text, "is_eof").unwrap_or(false),
    body: text,
  }
}
