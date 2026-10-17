///|
/// Kodo 的签名族。对标官方 `com.qiniu.util.Auth`，逐字算法见阶段 D 卡 §7-10。
///
/// 字段刻意**不加** `pub(all)`：`secret_key` 一旦能被外面读到，`derive(Show)`/日志/
/// 错误串里迟早漏出去。构造只走 `Auth::new`，读只走 `access_key`。
pub struct Auth {
  access_key : String
  secret_key : String
}

///|
/// 官方 `Auth.create`：两把键任一为空就地拒（Java 抛 `IllegalArgumentException`，
/// 这里映射成伪码 -4 那一档）。
pub fn Auth::new(
  access_key : String,
  secret_key : String,
) -> Auth raise @error.KodoError {
  if access_key.is_empty() {
    raise @error.BadParam("access key is empty")
  }
  if secret_key.is_empty() {
    raise @error.BadParam("secret key is empty")
  }
  Auth::{ access_key, secret_key, }
}

///|
/// 公开的那半把键：错误文案与 reqid 记账要带它，签名本身不需要往外露。
pub fn Auth::access_key(self : Auth) -> String {
  self.access_key
}

///|
/// URL-safe Base64，**填充要留着**：官方 `UrlSafeBase64.encodeToString` 用的 flag 是
/// `URL_SAFE | NO_WRAP`，而 `util/Base64.java:594` 写的是 `do_padding = (flags &
/// NO_PADDING) == 0`——NO_WRAP 只关换行。2026-10-17 真桶实测：同一份上传策略，
/// 带填充的令牌回 200，剥掉填充的回 401 `BadToken`。
pub fn urlsafe_b64(data : Bytes) -> String {
  @codec.b64_encode_url(data)
}

///|
/// 官方 `UrlSafeBase64.decode`。签名串里带 `-`/`_`，标准表解不出来。
///
/// **补齐填充再解**：官方解码器把末尾 `=` 当可选（`util/Base64.java:83`），而 hutool 的
/// `b64_decode_url` 是严格档，长度不是 4 的倍数就判 `BadPadding`（现读
/// `codec/codec.mbt:748`）。别家 SDK 生成的令牌有可能是无填充那档（Java 自己也有
/// `NO_PADDING` 这个 flag），所以这里先补平再交给严格解码器——校验仍然全在。
pub fn urlsafe_b64_decode(text : String) -> Bytes raise @error.KodoError {
  let missing = (4 - text.length() % 4) % 4
  let mut filled = text
  for _ in 0..<missing {
    filled = filled + "="
  }
  @codec.b64_decode_url(filled) catch {
    err =>
      raise @error.BadParam("not a url-safe base64 string: " + codec_text(err))
  }
}

///|
/// `CodecError` 没有现成的文案口，逐臂给读数。**不回显输入**：那一串可能就是令牌，
/// 令牌进日志等于把策略明文与签名一起摊开。
fn codec_text(err : @codec.CodecError) -> String {
  match err {
    @codec.CodecError::IllegalChar(_, at) => "illegal char at " + at.to_string()
    @codec.CodecError::BadPadding(_, at) => "bad padding at " + at.to_string()
    @codec.CodecError::RadixOutOfRange(value, bound) =>
      "radix " + value.to_string() + " out of " + bound.to_string()
    @codec.CodecError::ValueOverflow(_) => "value overflow"
    @codec.CodecError::ChecksumMismatch => "checksum mismatch"
    @codec.CodecError::BadUtf8(_) => "not valid utf-8 after decoding"
    @codec.CodecError::ShiftUnderflow(at) => "shift underflow " + at.to_string()
  }
}

///|
/// `sign(data)` ＝ `accessKey + ":" + urlsafe_b64(hmac_sha1(secretKey, data))`。
/// 键与数据都是字节：官方 `StringUtils.utf8Bytes`，非 ASCII 的 secret 也能一致。
pub fn Auth::sign_bytes(self : Auth, data : Bytes) -> String {
  let digest = @digest.hmac_sha1_of_bytes(@utf8.encode(self.secret_key), data)
  self.access_key + ":" + urlsafe_b64(digest)
}

///|
/// `sign(String)` 那一档：先按 UTF-8 取字节再签。
pub fn Auth::sign(self : Auth, data : String) -> String {
  self.sign_bytes(@utf8.encode(data))
}

///|
/// `signWithData(data)`：**先对编码后的串签，再把编码串本身拼在后面**。
/// 次序反了就是一个合法形状、非法内容的签名——上传令牌与策略类接口全靠这条。
pub fn Auth::sign_with_data_bytes(self : Auth, data : Bytes) -> String {
  let encoded = urlsafe_b64(data)
  self.sign(encoded) + ":" + encoded
}

///|
/// `signWithData(String)`。
pub fn Auth::sign_with_data(self : Auth, data : String) -> String {
  self.sign_with_data_bytes(@utf8.encode(data))
}

///|
/// 表单 MIME 常量，照官方 `http/Client.java:27` 的 `FormMime`。
pub fn form_mime() -> String {
  "application/x-www-form-urlencoded"
}

///|
/// QBox 请求签名的**待签串**：未解码路径 + (`?` + 原始查询，非空时) + `\n`
/// + (表单 body，仅当 content-type 是 `application/x-www-form-urlencoded` 且 body 在)。
/// 拆出来是为了用例能直接断言"签的到底是这几个字节"，而不是只看一个不可读的摘要。
fn qbox_signing_string(
  url : String,
  body : Bytes?,
  content_type : String?,
) -> Bytes raise @error.KodoError {
  let (path, query) = raw_path_query(url)
  let mut data = @utf8.encode(path)
  // 官方这里判的是 `query != null && query.length() != 0`：空查询不喂 `?`
  match query {
    None => ()
    Some(text) => if !text.is_empty() { data = data + @utf8.encode("?" + text) }
  }
  data = data + @utf8.encode("\n")
  match (body, content_type) {
    (Some(payload), Some(kind)) =>
      if ascii_lower(kind) == form_mime() {
        data = data + payload
      }
    _ => ()
  }
  data
}

///|
/// `signRequest(url, body, contentType)`：`accessKey:digest`。
pub fn Auth::sign_request(
  self : Auth,
  url : String,
  body~ : Bytes? = None,
  content_type~ : String? = None,
) -> String raise @error.KodoError {
  self.sign_bytes(qbox_signing_string(url, body, content_type))
}

///|
/// `authorization(url, body, contentType)`：`QBox ` 前缀的那一条请求头。
pub fn Auth::qbox_authorization(
  self : Auth,
  url : String,
  body~ : Bytes? = None,
  content_type~ : String? = None,
) -> @transport.Header raise @error.KodoError {
  let digest = self.sign_request(url, body~, content_type~)
  @transport.Header::{ name: "Authorization", value: "QBox " + digest, }
}
