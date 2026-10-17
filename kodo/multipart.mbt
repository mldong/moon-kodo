///|
/// 分块上传第二代（V2）。对标官方 `storage/ApiUploadV2*.java` 与
/// `ResumeUploadPerformerV2.java`，形状现读（2026-10-17）：
///
/// - init    `POST {up}/buckets/{bucket}/objects/{enc(key)}/uploads` → `uploadId` + `expireAt`
/// - part    `PUT  {同一串}/{uploadId}/{partNumber}` → `md5` + `etag`
/// - list    `GET  {…}/{uploadId}?max-parts=&part-number-marker=` → `parts[]` + `partNumberMarker`
/// - done    `POST {…}/{uploadId}`，body 是 `{"parts":[{"partNumber","etag"}], "fname", "mimeType",
///           "customVars", "metaData"}` → `key` + `hash`
/// - abort   `DELETE {…}/{uploadId}`
///
/// 鉴权一律 `Authorization: UpToken <令牌>`（`ApiUpload.java:41-48`），**不是** QBox/Qiniu 族。
/// `enc` 即 `ApiUtils.resumeV2EncodeKey`：不给 key 用 `~`，空 key 用空串（那一段会被
/// `addPathSegment` 丢掉），其余是 URL-safe Base64（带填充，见卡 §7-12）。

///|
/// 一次分块上传的会话：令牌只签一次就复用（官方 `UploadManager` 传的是一枚 `uptoken`），
/// `upload_id` 与 `expire_at` 来自 init 的回包。
pub(all) struct UploadSession {
  key : String
  token : String
  upload_id : String
  expire_at : Int64?
}

///|
pub(all) struct PartResult {
  part_number : Int32
  etag : String
  md5 : String?
  body : String
}

///|
/// 一个已上传分片的读数（list 回包里的元素，也是 complete 的入参）。
pub(all) struct PartInfo {
  part_number : Int32
  etag : String
  size : Int64?
  put_time : Int64?
}

///|
pub(all) struct PartPage {
  parts : Array[PartInfo]
  /// 0 表示没有更多分片（官方 `getPartNumberMarker` 的注释就这一句）
  next_marker : Int32?
  truncated : Bool
  body : String
}

///|
/// 分片号 1 ~ 10000（官方 `ApiUploadV2UploadPart.java:91-93`）。
pub let max_part_number : Int32 = 10000

///|
/// 块大小范围 1MB ~ 1GB（官方 `Configuration.resumableUploadAPIV2BlockSize`，
/// 默认 `Constants.BLOCK_SIZE` = 4MB）。
pub let min_block_size : Int32 = 1048576

///|
pub let max_block_size : Int32 = 1073741824

///|
pub let default_block_size : Int32 = 4194304

///|
/// `ApiUtils.resumeV2EncodeKey` 的三档。
pub fn v2_key_segment(key : String) -> String {
  if key.is_empty() {
    ""
  } else {
    @auth.urlsafe_b64(@utf8.encode(key))
  }
}

///|
/// 分片号必须在**任何请求发出之前**拒掉：越界的 partNumber 会被服务端覆盖成别的分片。
pub fn check_part_number(part_number : Int32) -> Unit raise @error.KodoError {
  if part_number < 1 || part_number > max_part_number {
    raise @error.BadParam(
      "part number must be within 1~" +
      max_part_number.to_string() +
      ", got " +
      part_number.to_string(),
    )
  }
}

///|
/// 除最后一片外，每片必须落在 1MB ~ 1GB。
pub fn check_block_size(
  size : Int32,
  last~ : Bool,
) -> Unit raise @error.KodoError {
  if last {
    return ()
  }
  if size < min_block_size || size > max_block_size {
    let want = min_block_size.to_string() + "~" + max_block_size.to_string()
    raise @error.BadParam(
      "every part but the last must be " +
      want +
      " bytes, got " +
      size.to_string(),
    )
  }
}

///|
/// 按块大小切偏移。
///
/// 这里**不写**"片数超 10000 就拒"那一档：入参是 `Int32`，而块大小最低 1MB，
/// 一个 `Int32` 能装下的总长最多切出 2048 片，那条判据永远走不到。写出来只是装饰，
/// 会把"服务端有这个上限"这件事假成"我们已经挡住了"。
pub fn split_blocks(
  total : Int32,
  block_size : Int32,
) -> Array[(Int32, Int32)] raise @error.KodoError {
  if block_size < min_block_size || block_size > max_block_size {
    let want = min_block_size.to_string() + "~" + max_block_size.to_string()
    raise @error.BadParam("block size must be " + want + " bytes")
  }
  if total == 0 {
    return [(0, 0)]
  }
  let parts : Array[(Int32, Int32)] = []
  let mut offset = 0
  while offset < total {
    let rest = total - offset
    let size = if rest > block_size { block_size } else { rest }
    parts.push((offset, size))
    offset = offset + size
  }
  parts
}

///|
/// complete 的请求体（纯函数，离线可断言）。
/// 键序是我们定的：`parts` 在最前，其余按官方 `buildBodyInfo` 的出现次序
/// （`fname` → `mimeType` → `customVars` → `metaData`，不给就不写）。
pub fn complete_body(
  parts : Array[PartInfo],
  filename~ : String? = None,
  mime_type~ : String? = None,
  custom_vars~ : Array[(String, String)] = [],
  meta~ : Array[(String, String)] = [],
) -> String {
  let items : Array[String] = []
  for part in parts {
    let number = part.part_number.to_string()
    let one = "{\"partNumber\":" +
      number +
      ",\"etag\":" +
      @error.json_quote(part.etag) +
      "}"
    items.push(one)
  }
  let mut body = "{\"parts\":[" + items.join(",") + "]}"
  body = body_with(body, "fname", filename)
  body = body_with(body, "mimeType", mime_type)
  let vars = pairs_object(custom_vars)
  if vars.length() > 2 {
    body = body[0:body.length() - 1].to_owned() +
      ",\"customVars\":" +
      vars +
      "}"
  }
  let metas = pairs_object(meta)
  if metas.length() > 2 {
    body = body[0:body.length() - 1].to_owned() + ",\"metaData\":" + metas + "}"
  }
  body
}

///|
fn body_with(body : String, field : String, value : String?) -> String {
  match value {
    None => body
    Some(text) => {
      let quoted = @error.json_quote(text)
      let head = body[0:body.length() - 1].to_owned()
      head + "," + @error.json_quote(field) + ":" + quoted + "}"
    }
  }
}

///|
fn pairs_object(pairs : Array[(String, String)]) -> String {
  let items : Array[String] = []
  for pair in pairs {
    items.push(@error.json_quote(pair.0) + ":" + @error.json_quote(pair.1))
  }
  if items.is_empty() {
    "{}"
  } else {
    "{" + items.join(",") + "}"
  }
}

///|
/// 一块内容的 md5（小写十六进制）：官方 `Md5.getFormattedText` 就是小写、不足两位补 0。
/// `check_crc` 开着时拿它与服务端回的 `md5` 比。
pub fn block_md5_hex(data : Bytes) -> String {
  @hex.encode(@digest.md5_of_bytes(data))
}

///|
/// 块摘要比对的判据本体：不等就抛，且抛在**合并之前**。文案照官方
/// `ResumeUploadPerformerV2.java:62-71`（`block's md5 is not match`），
/// 差的是我们把"服务端没回 md5"与"回了但不等"分成两条读数。
pub fn check_part_md5(
  part_number : Int32,
  server_md5 : String,
  want_md5 : String,
) -> Unit raise @error.KodoError {
  if server_md5 != want_md5 {
    let head = "block's md5 is not match at part " + part_number.to_string()
    let detail = head + ", server said " + server_md5 + ", expected " + want_md5
    raise @error.BadResponse(detail)
  }
}

///|
/// V2 各接口的 URL。`upload_id` 为空在 init 之外一律先拒（官方也是这个次序：
/// `uploadId is empty` 抛在使用任何请求之前）。
fn Client::v2_url(
  self : Client,
  key : String,
  upload_id~ : String? = None,
  part_number~ : Int32? = None,
) -> String raise @error.KodoError {
  let mut path = "/buckets/" +
    self.bucket +
    "/objects/" +
    v2_key_segment(key) +
    "/uploads"
  match upload_id {
    None => ()
    Some(id) => {
      if id.is_empty() {
        raise @error.BadParam("uploadId is empty")
      }
      path = path + "/" + id
    }
  }
  match part_number {
    None => ()
    Some(number) => {
      check_part_number(number)
      path = path + "/" + number.to_string()
    }
  }
  self.config.up_origin() + path
}

///|
/// 发一条 V2 请求：只有 `Authorization: UpToken`，带 body 时按官方那三档给
/// `application/octet-stream`（init/complete/list/abort 的 body 是 `null` 或 JSON，
/// 官方都走 `DefaultMime`）。
async fn Client::v2_send(
  self : Client,
  verb : @transport.Method,
  url : String,
  token : String,
  body~ : Bytes? = None,
) -> @transport.Response raise @error.KodoError {
  let headers : Array[@transport.Header] = [
    @transport.Header::{ name: "Authorization", value: "UpToken " + token, },
  ]
  // 带 body 的两档（part / complete）在官方都落到 `DefaultMime` = octet-stream；
  // init / list / abort 不带 body 也就不带 Content-Type。这一档差异同时进服务端解析，
  // 不能"统一带上"。
  let with_type = match body {
    None => headers
    Some(_) =>
      headers +
      [@transport.Header::{ name: "Content-Type", value: default_mime(), }]
  }
  let request_body = match body {
    None => @transport.RequestBody::Empty
    Some(data) => @transport.RequestBody::Bytes(data)
  }
  self.send(@transport.Request::{
    http_method: verb,
    url,
    headers: with_type,
    body: request_body,
  })
}

///|
/// init：拿 `uploadId` 与 `expireAt`。两者缺一都算失败（官方在 `isOK()` 之后立刻判空）。
pub async fn Client::begin_multipart(
  self : Client,
  key : String,
  expires~ : Int64 = 3600,
) -> UploadSession raise @error.KodoError {
  if key.is_empty() {
    raise @error.BadParam("multipart upload needs a key")
  }
  let token = self.auth.upload_token(self.bucket, key=Some(key), expires~)
  let url = self.v2_url(key)
  let response = self.v2_send(@transport.Method::Post, url, token)
  let text = read_text(response.body)
  let upload_id = match @error.json_string_field(text, "uploadId") {
    None =>
      raise @error.BadResponse("init replied no uploadId: " + clip_text(text))
    Some(id) => id
  }
  UploadSession::{
    key,
    token,
    upload_id,
    expire_at: @error.json_int_field(text, "expireAt"),
  }
}

///|
/// 续用一个已存在的 `uploadId` 造会话：令牌**每次现签**（参照件
/// `QiniuKodoFileStorage` 就是每步上传前签一枚，会话本身不带凭据），所以调用方
/// 只要把 `upload_id` 带回来就能接着传——端口上 `FileInfo.upload_id` 就是为这个留的。
pub fn Client::resume_multipart(
  self : Client,
  key : String,
  upload_id : String,
  expires~ : Int64 = 3600,
) -> UploadSession raise @error.KodoError {
  if key.is_empty() {
    raise @error.BadParam("multipart session needs a key")
  }
  if upload_id.is_empty() {
    raise @error.BadParam("uploadId is empty")
  }
  UploadSession::{
    key,
    token: self.auth.upload_token(self.bucket, key=Some(key), expires~),
    upload_id,
    expire_at: None,
  }
}

///|
/// 传一片。`check_crc` 开着时（默认关，照参照）拿服务端回的 `md5` 与本地比，
/// 不等就在**合并之前**抛——这正是 KD3b 要钉的那一档。
pub async fn Client::upload_part(
  self : Client,
  session : UploadSession,
  part_number : Int32,
  data : Bytes,
  check_crc~ : Bool = false,
  expect_md5~ : String? = None,
) -> PartResult raise @error.KodoError {
  check_part_number(part_number)
  let url = self.v2_url(
    session.key,
    upload_id=Some(session.upload_id),
    part_number=Some(part_number),
  )
  let response = self.v2_send(
    @transport.Method::Put,
    url,
    session.token,
    body=Some(data),
  )
  let text = read_text(response.body)
  let md5 = @error.json_string_field(text, "md5")
  if check_crc {
    match md5 {
      None =>
        raise @error.BadResponse("part reply has no md5: " + clip_text(text))
      Some(server) => {
        // 比对基准：调用方给的期望摘要优先（续传/复核场景带来的是**上一次的**值），
        // 没给就是本地对这份 data 算出来的
        let want = expect_md5.unwrap_or(block_md5_hex(data))
        check_part_md5(part_number, server, want)
      }
    }
  }
  let etag = match @error.json_string_field(text, "etag") {
    None =>
      raise @error.BadResponse("part reply has no etag: " + clip_text(text))
    Some(tag) => tag
  }
  PartResult::{ part_number, etag, md5, body: text, }
}

///|
/// 列举已上传的分片（续传与"分片号乱序传入按号合并"都要用它核对）。
pub async fn Client::list_parts(
  self : Client,
  session : UploadSession,
  part_number_marker~ : Int32? = None,
  max_parts~ : Int32? = None,
) -> PartPage raise @error.KodoError {
  let mut url = self.v2_url(session.key, upload_id=Some(session.upload_id))
  let mut joined = ""
  match max_parts {
    None => ()
    Some(n) => joined = joined + "&max-parts=" + n.to_string()
  }
  match part_number_marker {
    None => ()
    Some(m) => joined = joined + "&part-number-marker=" + m.to_string()
  }
  if !joined.is_empty() {
    url = url + "?" + joined[1:joined.length()].to_owned()
  }
  let response = self.v2_send(@transport.Method::Get, url, session.token)
  let text = read_text(response.body)
  let parts : Array[PartInfo] = []
  for item in @error.json_objects(text, "parts") {
    let number = match @error.json_int_field(item, "partNumber") {
      None =>
        raise @error.BadResponse(
          "part row without partNumber: " + clip_text(item),
        )
      Some(n) => n.to_int()
    }
    let etag = match @error.json_string_field(item, "etag") {
      None =>
        raise @error.BadResponse("part row without etag: " + clip_text(item))
      Some(tag) => tag
    }
    parts.push(PartInfo::{
      part_number: number,
      etag,
      size: @error.json_int_field(item, "size"),
      put_time: @error.json_int_field(item, "putTime"),
    })
  }
  PartPage::{
    parts,
    next_marker: match @error.json_int_field(text, "partNumberMarker") {
      None => None
      Some(n) => Some(n.to_int())
    },
    truncated: @error.json_bool_field(text, "truncated").unwrap_or(false),
    body: text,
  }
}

///|
/// 合并。`parts` 按分片号排好再发（服务端按数组次序拼，官方 `PartInfo` 也要求升序）。
pub async fn Client::complete_multipart(
  self : Client,
  session : UploadSession,
  parts : Array[PartInfo],
  mime_type~ : String? = None,
  filename~ : String? = None,
  custom_vars~ : Array[(String, String)] = [],
  meta~ : Array[(String, String)] = [],
) -> FormUploadResult raise @error.KodoError {
  if parts.is_empty() {
    raise @error.BadParam("complete needs at least one part")
  }
  let ordered = sort_parts(parts)
  let body = complete_body(ordered, filename~, mime_type~, custom_vars~, meta~)
  let url = self.v2_url(session.key, upload_id=Some(session.upload_id))
  let response = self.v2_send(
    @transport.Method::Post,
    url,
    session.token,
    body=Some(@utf8.encode(body)),
  )
  let text = read_text(response.body)
  FormUploadResult::{
    key: @error.json_string_field(text, "key"),
    hash: @error.json_string_field(text, "hash"),
    body: text,
  }
}

///|
/// 放弃：丢掉已传的分片，不留最终对象。
pub async fn Client::abort_multipart(
  self : Client,
  session : UploadSession,
) -> Unit raise @error.KodoError {
  let url = self.v2_url(session.key, upload_id=Some(session.upload_id))
  let _ = self.v2_send(@transport.Method::Delete, url, session.token)
}

///|
/// 分片号升序。这里**不能**用 core 的排序：`Compare for Int` 可用，但字符串比较器
/// 会踩"先比长度"的坑，所以只按整数键排（片号是整数）。
pub fn sort_parts(parts : Array[PartInfo]) -> Array[PartInfo] {
  parts.sort_by((a, b) => a.part_number - b.part_number)
  parts
}

///|
/// 高层入口：整份字节按 `block_size` 切开，init → 逐片 PUT → complete。
/// 任一片失败都不合并（`upload_part` 直接抛），已传分片由调用方 `abort_multipart` 处理。
pub async fn Client::put_bytes_multipart(
  self : Client,
  key : String,
  data : Bytes,
  block_size~ : Int32 = default_block_size,
  check_crc~ : Bool = false,
  mime_type~ : String? = None,
  expires~ : Int64 = 3600,
) -> FormUploadResult raise @error.KodoError {
  let session = self.begin_multipart(key, expires~)
  let ranges = split_blocks(data.length(), block_size)
  let parts : Array[PartInfo] = []
  for index in 0..<ranges.length() {
    let range = ranges[index]
    check_block_size(range.1, last=index + 1 == ranges.length())
    let view = data[range.0:range.0 + range.1]
    let slice = view.to_owned()
    let one = self.upload_part(session, index + 1, slice, check_crc~)
    parts.push(PartInfo::{
      part_number: one.part_number,
      etag: one.etag,
      size: Some(range.1.to_int64()),
      put_time: None,
    })
  }
  self.complete_multipart(session, parts, mime_type~)
}

///|
fn clip_text(text : String) -> String {
  if text.length() > 200 {
    text[0:200].to_owned() + "..."
  } else {
    text
  }
}
