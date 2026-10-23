///|
/// 异步抓取与 CDN 预取。路径照官方 `BucketManager`（2026-10-22 现读）：
/// - `asynFetch`：`POST {api_host}/sisyphus/fetch`，JSON 体带上 url/bucket/key，
///   签名走 `Qiniu` 且 body 入签（`qiniu.mbt` 的 JSON 分支）
/// - `checkAsynFetchid`：`GET {api_host}/sisyphus/fetch?id=<id>`
/// - `prefetch`：`POST {iovip}/prefetch/<entry>`，`Qiniu` 签名
/// 三件都会触发服务端真实动作（抓取/预热），只落离线件，真桶要显式开关再跑。
pub(all) struct AsyncFetchResult {
  id : String?
  body : String
}

///|
pub async fn Client::async_fetch(
  self : Client,
  url : String,
  key : String,
  bucket~ : String? = None,
  md5~ : String = "",
  etag~ : String = "",
) -> AsyncFetchResult raise @error.KodoError {
  let target = bucket.unwrap_or(self.bucket)
  if target.is_empty() {
    raise @error.BadParam("async_fetch needs a bucket")
  }
  if url.is_empty() {
    raise @error.BadParam("async_fetch needs a source url")
  }
  let body = async_fetch_body(url, target, key, md5~, etag~)
  let endpoint = self.config.scheme() +
    "://" +
    self.config.region.api_host +
    "/sisyphus/fetch"
  let payload = @utf8.encode(body)
  let headers = self.auth.qiniu_authorization(
    endpoint,
    "POST",
    body=Some(payload),
    headers=[
      @transport.Header::{ name: "Content-Type", value: "application/json", },
    ],
  )
  let response = self.send(@transport.Request::{
    http_method: @transport.Method::Post,
    url: endpoint,
    headers,
    body: @transport.RequestBody::Bytes(payload),
  })
  let text = read_text(response.body)
  AsyncFetchResult::{ id: @error.json_string_field(text, "id"), body: text, }
}

///|
/// 查一次异步抓取的结果；`id` 来自 [Client::async_fetch] 的返回。
pub async fn Client::check_async_fetch(
  self : Client,
  id : String,
) -> String raise @error.KodoError {
  if id.is_empty() {
    raise @error.BadParam("check_async_fetch needs an id")
  }
  let endpoint = self.config.scheme() +
    "://" +
    self.config.region.api_host +
    "/sisyphus/fetch?id=" +
    form_encode(id)
  let headers = self.auth.qiniu_authorization(endpoint, "GET")
  let response = self.send(@transport.Request::{
    http_method: @transport.Method::Get,
    url: endpoint,
    headers,
    body: @transport.RequestBody::Empty,
  })
  read_text(response.body)
}

///|
/// CDN 预取：`POST {iovip}/prefetch/<entry>`。预热有成本，本仓只落离线件。
pub async fn Client::prefetch(
  self : Client,
  key : String,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = bucket.unwrap_or(self.bucket)
  if target.is_empty() {
    raise @error.BadParam("prefetch needs a bucket")
  }
  if key.is_empty() {
    raise @error.BadParam("prefetch needs a key")
  }
  let response = self.io_post(prefetch_path(target, key))
  discard_body(response)
}

///|
pub fn prefetch_path(bucket : String, key : String) -> String {
  "/prefetch/" + encoded_entry(bucket, Some(key))
}

///|
pub fn async_fetch_body(
  url : String,
  bucket : String,
  key : String,
  md5~ : String = "",
  etag~ : String = "",
) -> String {
  let fields : Array[String] = [
    "\"url\":" + @error.json_quote(url),
    "\"bucket\":" + @error.json_quote(bucket),
    "\"key\":" + @error.json_quote(key),
  ]
  if !md5.is_empty() {
    fields.push("\"md5\":" + @error.json_quote(md5))
  }
  if !etag.is_empty() {
    fields.push("\"etag\":" + @error.json_quote(etag))
  }
  "{" + fields.join(",") + "}"
}
