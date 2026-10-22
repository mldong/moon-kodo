///|
/// 桶绑定域名列表：`GET {uc}/v2/domains?tbl=<bucket>`，QBox 签名。
/// 绑定域名本身官方建议控制台完成，SDK 只读列表。
pub(all) struct BucketDomains {
  names : Array[String]
  body : String
}

///|
pub async fn Client::domains(
  self : Client,
  bucket~ : String? = None,
) -> BucketDomains raise @error.KodoError {
  let target = bucket.unwrap_or(self.bucket)
  if target.is_empty() {
    raise @error.BadParam("domains needs a bucket name")
  }
  let response = self.uc_get("/v2/domains?tbl=" + target)
  let text = read_text(response.body)
  BucketDomains::{ names: @error.json_array_strings(text), body: text, }
}

///|
async fn Client::uc_get(
  self : Client,
  path : String,
) -> @transport.Response raise @error.KodoError {
  let url = self.config.uc_origin() + path
  let headers = [self.auth.qbox_authorization(url)]
  self.send(@transport.Request::{
    http_method: @transport.Method::Get,
    url,
    headers,
    body: @transport.RequestBody::Empty,
  })
}
