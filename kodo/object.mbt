///|
/// 资源管理接口（rs）的对象族：`POST {rs}/{动作}/{encodedEntry}`，
/// 签名走 `Qiniu ` 那一族、content-type 是表单、body 为空（官方
/// `BucketManager.rsPost` `:1146-1150` 与 `post` `:1175-1177`）。

///|
/// `stat` 的读数。字段都做成可选：不同存储类型与桶配置回的字集不一样，
/// 缺字段不该把整次操作判失败。
///
/// `user_metadata` 是 `x-qn-meta` 那一份：2026-10-17 真桶现读，写侧走平铺字段
/// `x-qn-meta-case`，读侧回成**嵌套对象** `"x-qn-meta":{"case":"…"}`，两侧形状不同；
/// 没有这一族时回空表（不是"读失败"）。
pub(all) struct StatResult {
  fsize : Int64?
  hash : String?
  mime_type : String?
  put_time : Int64?
  user_metadata : Array[(String, String)]
  body : String
} derive(Eq)

///|
pub extend StatResult with Eq::{equal, not_equal}

///|
/// `x-qn-meta` 是一个**嵌套对象**（不是数组，也不是平铺键），所以走
/// `json_object_field` 切出那一段再逐对读。
pub fn stat_user_metadata(body : String) -> Array[(String, String)] {
  match @error.json_object_field(body, "x-qn-meta") {
    None => []
    Some(object) => @error.json_string_pairs(object)
  }
}

///|
/// 给一条 URL 加私有下载签名（官方那件挂在 `Auth` 上：`privateDownloadUrl`）。
/// 这里转到 Client 只是为了让上层不必另持一份 `Auth`——**域名由调用方给**，
/// 本包不猜也不造（`base_url` 就是 `域名/key` 或 `iovip/key`）。
pub fn Client::private_download_url(
  self : Client,
  base_url : String,
  expires~ : Int64 = 3600,
) -> String {
  self.auth.private_download_url(base_url, expires~)
}

///|
/// 对象在不在、多大。缺对象时 Kodo 直接用 **612** 应答，`send` 把它原样放进
/// `Service`，调用方经由 `is_not_found` 判（参照件 `QiniuKodoFileStorage:478`
/// 认的就是这个码）——这里不做任何"翻成 404 再翻回来"的搬运。
pub async fn Client::stat(
  self : Client,
  key : String,
) -> StatResult raise @error.KodoError {
  let path = "/stat/" + encoded_entry(self.bucket, Some(key))
  let response = self.rs_post(path)
  let text = read_text(response.body)
  StatResult::{
    fsize: @error.json_int_field(text, "fsize"),
    hash: @error.json_string_field(text, "hash"),
    mime_type: @error.json_string_field(text, "mimeType"),
    put_time: @error.json_int_field(text, "putTime"),
    user_metadata: stat_user_metadata(text),
    body: text,
  }
}

///|
/// 删对象。Kodo 对"本来就不存在"的删除回 612，参照件把它当失败返回 false，
/// 这里同档：`Bool`，不存在就是 `false`，其余错误照常 raise。
pub async fn Client::delete(
  self : Client,
  key : String,
) -> Bool raise @error.KodoError {
  let path = "/delete/" + encoded_entry(self.bucket, Some(key))
  let response = self.rs_post(path) catch {
    err =>
      match err {
        @error.KodoError::Service(s) =>
          if s.status == 612 {
            return false
          } else {
            raise err
          }
        _ => raise err
      }
  }
  response.status == 200
}
