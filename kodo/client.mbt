///|
/// Kodo 客户端的骨架：注入的传输、签名件、区域配置与桶名。
///
/// 与 `moon-s3` 同一立场——库本身不认识任何具体 HTTP 实现，只认 `transport` 端口，
/// 换 HTTP 底座改的是 `mldong/moon-hutool` 的 `http` 包，不是这里。
pub struct Client {
  transport : &@transport.Transport
  auth : @auth.Auth
  config : @config.Config
  bucket : String
}

///|
pub fn Client::new(
  transport : &@transport.Transport,
  auth : @auth.Auth,
  config : @config.Config,
  bucket : String,
) -> Client raise @error.KodoError {
  if bucket.is_empty() {
    raise @error.BadParam("kodo client needs a bucket name")
  }
  Client::{ transport, auth, config, bucket, }
}

///|
pub fn Client::bucket(self : Client) -> String {
  self.bucket
}

///|
/// `BucketManager.encodedEntry`：`urlsafe_b64(bucket + ":" + key)`；不给 key 就只编桶名。
/// 资源管理接口（rs）的路径段用的就是这个串，不是明文 key。
pub fn encoded_entry(bucket : String, key : String?) -> String {
  let text = match key {
    None => bucket
    Some(name) => bucket + ":" + name
  }
  @auth.urlsafe_b64(@utf8.encode(text))
}

///|
/// 资源管理服务（rs）的 origin。按桶所在区域现取，不写死主机名（卡 §3-2）。
fn Client::rs_origin(self : Client) -> String {
  self.config.rs_origin()
}

///|
/// rs 系接口统一是 **POST + 表单 content-type + 空 body**（官方 `BucketManager.post`
/// `:1175-1177`），签名走 `Qiniu ` 那一族；空 body 不进签名串。
async fn Client::rs_post(
  self : Client,
  path : String,
) -> @transport.Response raise @error.KodoError {
  let url = self.rs_origin() + path
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
/// 能不能重放。官方 `Api.Request.canRetry`（`Api.java:956-962`）问的不是"失败发生在哪个相位"，
/// 而是"这次请求还发得出来吗"：没 body 一定能，有 body 要看 `canReset()`——
/// 字节体能复位，流式体 `canReset` 返回 false、`reset` 直接抛 unrecoverable（`Api.java:1102-1108`）。
///
/// 本包目前不往流里发体（表单与分块都是字节体），所以 `Stream` 那一档是给以后的流式上传
/// 留的栅栏，不是现在就会走到的分支。
pub fn replayable(body : @transport.RequestBody) -> Bool {
  match body {
    @transport.RequestBody::Empty => true
    @transport.RequestBody::Bytes(_) => true
    @transport.RequestBody::Stream(_, _) => false
  }
}

///|
/// 只有"没拿到应答"这一类才重发（官方 `Retry.canRequestRetryAgain` `Retry.java:27-41`：
/// 异常不带 response 且非 unrecoverable ⇒ 可重试）。服务端已经回过话的，一律算最终读数，
/// 不靠重试去改一次已经发生的操作。
fn is_no_answer(error : @transport.TransportError) -> Bool {
  match error {
    @transport.TransportError::Network(_) => true
    @transport.TransportError::Timeout => true
    @transport.TransportError::InvalidResponse(_) => true
    @transport.TransportError::InvalidRequest(_) => false
  }
}

///|
/// 传输失败落进哪一臂是伪码的事，文案本身先过 `redact_query`：这是传输层文案交给调用方的
/// **第二个**出口（第一个是 `region_probe.mbt` 的 `transport_text`），而预签名/私有下载 URL
/// 的 query 就是凭据本体——只隐去一处等于另一处照旧外流。理由与隐去形状见那一条注释。
fn transport_failure(error : @transport.TransportError) -> @error.KodoError {
  match error {
    @transport.TransportError::Network(detail) =>
      @error.Network(redact_query(detail))
    @transport.TransportError::Timeout => @error.Network("timeout")
    @transport.TransportError::InvalidRequest(detail) =>
      @error.BadParam(redact_query(detail))
    @transport.TransportError::InvalidResponse(detail) =>
      @error.Network(redact_query(detail))
  }
}

///|
/// 重试档照官方默认：同域名额外 1 次（`singleHostRetryMax`，`Api.java:272`）、
/// 间隔 200ms（`Retry.defaultInterval`，`Retry.java:67`）。
let retry_interval_ms : Int32 = 200

///|
/// 发一条请求并把状态码以外的读数准备好：非 2xx 一律先解成 `ServiceError`。
async fn Client::send(
  self : Client,
  request : @transport.Request,
) -> @transport.Response raise @error.KodoError {
  let may_replay = replayable(request.body)
  let response = self.transport.send(request) catch {
    err =>
      if may_replay && is_no_answer(err) {
        let note = "kodo send retried after no answer: " + transport_text(err)
        println(note)
        @async.sleep(retry_interval_ms)
        // 第二次再失败就原样抛：一次额外尝试是官方给的预算，不是"重试到绿"
        self.transport.send(request) catch {
          again => raise transport_failure(again)
        }
      } else {
        raise transport_failure(err)
      }
  }
  if response.status < 200 || response.status >= 300 {
    let body = read_text(response.body)
    let req_id = header_value(response.headers, "x-reqid")
    raise @error.Service(@error.service_error(response.status, body, req_id))
  }
  response
}

///|
/// 打开一条已经签好的 URL 取回内容（`download` 与 `presigned_url` 走的就是这条路）。
///
/// Kodo 没有"下载"这个 API——参照件也是"签一条 URL 再打开它"，所以这里只发一条无凭据的
/// GET，重试档与上面同一套（无 body ⇒ 可重放）。
pub async fn Client::open_url(
  self : Client,
  url : String,
) -> @transport.Response raise @error.KodoError {
  self.send(@transport.Request::{
    http_method: @transport.Method::Get,
    url,
    headers: [],
    body: @transport.RequestBody::Empty,
  })
}

///|
/// 响应头取值：大小写无关、同名取最后一次。
fn header_value(headers : Array[@transport.Header], name : String) -> String? {
  let want = @auth.ascii_lower(name)
  let mut found : String? = None
  for h in headers {
    if @auth.ascii_lower(h.name) == want {
      found = Some(h.value)
    }
  }
  found
}

///|
async fn read_text(
  body : &@transport.ResponseBody,
) -> String raise @error.KodoError {
  let bytes = read_all(body)
  @utf8.decode_lossy(bytes)
}

///|
async fn read_all(
  body : &@transport.ResponseBody,
) -> Bytes raise @error.KodoError {
  let merged : Array[Byte] = []
  let mut reading = true
  while reading {
    let chunk = body.read(65536) catch {
      err => raise @error.Network(transport_text(err))
    }
    match chunk {
      Some(data) => merged.append(data.to_array())
      None => reading = false
    }
  }
  Bytes::from_array(merged)
}
