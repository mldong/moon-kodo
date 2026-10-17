///|
/// 表单上传（`POST {upHost}/`，`Authorization: UpToken <令牌>`）。
/// 对标官方 `storage/FormUploader.java` 与 `storage/ApiUpload.java:41-48`：
/// 令牌走**请求头**，同时也写进 multipart 的 `token` 字段（官方两处都给，
/// `ApiUpload.java:46` 与 `FormUploader.java:208`），`crc32` 只在开着校验时带上。

///|
/// 一次表单上传的成功读数。Kodo 回 `{"key":...,"hash":...}`；令牌里配了 `returnBody`
/// 时字段集换成调用方自己的，所以 `body` 原样留着。
pub(all) struct FormUploadResult {
  key : String?
  hash : String?
  body : String
} derive(Eq)

///|
pub extend FormUploadResult with Eq::{equal, not_equal}

///|
/// 一次表单上传的部件：文本域 + 那段二进制。
pub(all) struct FormPart {
  fields : Array[(String, String)]
  file_name : String
  file_type : String
  data : Bytes
}

///|
/// multipart 边界。固定串会在用户内容恰好含它时把请求撕开，所以按**这次载荷**算摘要：
/// 要撞上，得让文件里正好出现这 32 位十六进制串。
pub fn form_boundary(data : Bytes, key : String) -> String {
  let digest = @digest.md5_of_bytes(data + @utf8.encode(key))
  "moonfs-kodo-" + @hex.encode(digest)
}

///|
/// 拼 multipart/form-data 请求体（离线可算，用例直接断言字节）。形状照 RFC 7578：
/// 每段用 `\r\n` 包一层，最后一个边界后跟 `--\r\n`。文本域的值**原样**写入，
/// 不做 URL 编码——表单上传的字段是 multipart 值，不是 query。
pub fn form_body(part : FormPart, boundary : String) -> Bytes {
  let dash = "--" + boundary
  let mut out = @utf8.encode("")
  for field in part.fields {
    let head = dash +
      "\r\nContent-Disposition: form-data; name=\"" +
      field.0 +
      "\"\r\n\r\n"
    out = out + @utf8.encode(head)
    out = out + @utf8.encode(field.1)
    out = out + @utf8.encode("\r\n")
  }
  let disposition = "Content-Disposition: form-data; name=\"file\"; filename=\""
  let head_one = dash +
    "\r\n" +
    disposition +
    part.file_name +
    "\"\r\nContent-Type: "
  let file_head = head_one + part.file_type + "\r\n\r\n"
  out = out + @utf8.encode(file_head)
  out = out + part.data
  out = out + @utf8.encode("\r\n")
  out = out + @utf8.encode(dash + "--\r\n")
  out
}

///|
/// 整份字节的 CRC32 的**十进制串**（官方 `Crc32.bytes(data)` 之后 `"" + crc32`）。
/// 基础件在 hutool 0.1.3（卡 §7-8），这里只做线格式。
pub fn crc32_decimal(data : Bytes) -> String {
  @hash.crc32_of_bytes(data).to_string()
}

///|
/// 默认 MIME：官方 `http/Client.java:25` 的 `DefaultMime`。
pub fn default_mime() -> String {
  "application/octet-stream"
}

///|
/// 表单上传的表头字段：`token` 在最前（官方 `buildParams` 的第一笔），其余按传入次序。
pub fn form_fields(
  token : String,
  rest : Array[(String, String)],
) -> Array[(String, String)] {
  [("token", token)] + rest
}

///|
/// 发一次表单上传。
async fn Client::upload_form(
  self : Client,
  token : String,
  part : FormPart,
) -> @transport.Response raise @error.KodoError {
  let fields = form_fields(token, part.fields)
  let boundary = form_boundary(part.data, self.bucket)
  let body = form_body(
    FormPart::{
      fields,
      file_name: part.file_name,
      file_type: part.file_type,
      data: part.data,
    },
    boundary,
  )
  let content_type = "multipart/form-data; boundary=" + boundary
  // 上传域名按区域表取；取不到就是配置错了，得在任何请求之前响
  let url = self.config.up_origin()
  let headers = [
    @transport.Header::{ name: "Authorization", value: "UpToken " + token, },
    @transport.Header::{ name: "Content-Type", value: content_type, },
  ]
  self.send(@transport.Request::{
    http_method: @transport.Method::Post,
    url,
    headers,
    body: @transport.RequestBody::Bytes(body),
  })
}

///|
/// 用户元数据的字段前缀。写侧是**平铺**的 `x-qn-meta-<名>` 表单字段，读侧 `stat`
/// 回成嵌套对象 `"x-qn-meta":{...}`（2026-10-17 真桶现读）——两侧形状不同，别照写侧猜读侧。
pub let meta_prefix : String = "x-qn-meta-"

///|
/// 把用户元数据折成表单字段。名字不做白名单也不转小写：服务端会拒非法名，
/// 拒了就响亮报出来，比在本包里悄悄改写好。
pub fn meta_form_fields(
  pairs : Array[(String, String)],
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in pairs {
    out.push((meta_prefix + pair.0, pair.1))
  }
  out
}

///|
/// 高层入口：把字节写到 `key` 上。`mime`/`filename` 不给时按官方兜底
/// （`DefaultMime` 与"文件名取 key"），`check_crc` 默认 false（照参照件）。
pub async fn Client::put_bytes(
  self : Client,
  key : String,
  data : Bytes,
  mime~ : String? = None,
  filename~ : String? = None,
  check_crc~ : Bool = false,
  expires~ : Int64 = 3600,
  extra_fields~ : Array[(String, String)] = [],
  meta~ : Array[(String, String)] = [],
) -> FormUploadResult raise @error.KodoError {
  if key.is_empty() {
    raise @error.BadParam("form upload needs a key")
  }
  let token = self.auth.upload_token(self.bucket, key=Some(key), expires~)
  let rest : Array[(String, String)] = [("key", key)]
  if check_crc {
    rest.push(("crc32", crc32_decimal(data)))
  }
  for item in extra_fields {
    rest.push(item)
  }
  for item in meta_form_fields(meta) {
    rest.push(item)
  }
  let response = self.upload_form(token, FormPart::{
    fields: rest,
    file_name: filename.unwrap_or(key),
    file_type: mime.unwrap_or(default_mime()),
    data,
  })
  let text = read_text(response.body)
  FormUploadResult::{
    key: @error.json_string_field(text, "key"),
    hash: @error.json_string_field(text, "hash"),
    body: text,
  }
}
