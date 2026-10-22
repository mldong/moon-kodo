///|
/// 桶管理三件：`buckets` / `mkbucketv3` / `drop`。官方 `BucketManager` 这三个都走
/// UC 主机与 `QBox` 签名（`post(url, null, ucInterceptors())`），不是 rs 域的 `Qiniu` 签名。
pub(all) struct BucketList {
  names : Array[String]
  body : String
}

///|
pub async fn Client::buckets(
  self : Client,
) -> BucketList raise @error.KodoError {
  let response = self.uc_post("/buckets")
  let text = read_text(response.body)
  BucketList::{ names: @error.json_array_strings(text), body: text, }
}

///|
pub async fn Client::create_bucket(
  self : Client,
  bucket_name : String,
  region_id : String,
) -> Unit raise @error.KodoError {
  if bucket_name.is_empty() || region_id.is_empty() {
    raise @error.BadParam("create_bucket needs bucket name and region id")
  }
  let response = self.uc_post(create_bucket_path(bucket_name, region_id))
  discard_body(response)
}

///|
pub async fn Client::delete_bucket(
  self : Client,
  bucket_name : String,
) -> Unit raise @error.KodoError {
  if bucket_name.is_empty() {
    raise @error.BadParam("delete_bucket needs a bucket name")
  }
  let response = self.uc_post("/drop/" + bucket_name)
  discard_body(response)
}

///|
fn create_bucket_path(bucket_name : String, region_id : String) -> String {
  "/mkbucketv3/" + bucket_name + "/region/" + region_id
}

///|
async fn Client::uc_post(
  self : Client,
  path : String,
) -> @transport.Response raise @error.KodoError {
  let url = self.config.uc_origin() + path
  let headers = [self.auth.qbox_authorization(url)]
  self.send(@transport.Request::{
    http_method: @transport.Method::Post,
    url,
    headers,
    body: @transport.RequestBody::Empty,
  })
}

///|
async fn discard_body(
  response : @transport.Response,
) -> Unit raise @error.KodoError {
  let _ = read_text(response.body)
  response.body.close()
}
