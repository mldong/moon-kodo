///|
/// Kodo 批量操作：`POST /batch`，表单体是 `op=<op1>&op=<op2>...`。
/// 路径与响应形状照官方 Java SDK `BucketManager.batch` / `BatchOperations`
/// （2026-10-22 现读）：每个响应项是 `{code, data:{fsize,hash,mimeType,putTime,error}}`。

///|
pub(all) struct BatchCopy {
  from_bucket : String?
  from_key : String
  to_bucket : String?
  to_key : String
  force : Bool
}

///|
pub(all) struct BatchMove {
  from_bucket : String?
  from_key : String
  to_bucket : String?
  to_key : String
  force : Bool
}

///|
/// 一条批量指令。单桶操作默认落在 `Client` 的桶上；copy/move 可另给源/目标桶。
pub(all) enum BatchOp {
  Delete(String)
  Stat(String)
  Copy(BatchCopy)
  Move(BatchMove)
  ChangeMime(String, String)
  ChangeType(String, StorageType)
  ChangeStatus(String, ObjectStatus)
  DeleteAfterDays(String, Int32)
  RestoreArchive(String, Int32)
}

///|
pub(all) struct BatchItem {
  code : Int64?
  error : String?
  body : String
}

///|
pub(all) struct BatchResult {
  items : Array[BatchItem]
  body : String
}

///|
/// 批量执行。官方单次上限 1000 条，本地先拒；响应逐项返回，不把某一项失败吞成整体成功。
pub async fn Client::batch(
  self : Client,
  ops : Array[BatchOp],
) -> BatchResult raise @error.KodoError {
  if ops.is_empty() {
    raise @error.BadParam("batch needs at least one op")
  }
  if ops.length() > 1000 {
    raise @error.BadParam(
      "batch accepts at most 1000 ops, got " + ops.length().to_string(),
    )
  }
  let body_text = batch_body(self.bucket, ops)
  let body = @utf8.encode(body_text.view())
  let response = self.batch_post(body)
  let text = read_text(response.body)
  parse_batch_result(text)
}

///|
fn batch_body(bucket : String, ops : Array[BatchOp]) -> String {
  let paths : Array[String] = []
  for op in ops {
    paths.push(batch_op_path(bucket, op))
  }
  "op=" + paths.join("&op=")
}

///|
fn batch_op_path(bucket : String, op : BatchOp) -> String {
  match op {
    Delete(key) => "delete/" + encoded_entry(bucket, Some(key))
    Stat(key) => "stat/" + encoded_entry(bucket, Some(key))
    Copy(spec) =>
      "copy/" +
      encoded_entry(spec.from_bucket.unwrap_or(bucket), Some(spec.from_key)) +
      "/" +
      encoded_entry(spec.to_bucket.unwrap_or(bucket), Some(spec.to_key)) +
      force_suffix(spec.force)
    Move(spec) =>
      "move/" +
      encoded_entry(spec.from_bucket.unwrap_or(bucket), Some(spec.from_key)) +
      "/" +
      encoded_entry(spec.to_bucket.unwrap_or(bucket), Some(spec.to_key)) +
      force_suffix(spec.force)
    ChangeMime(key, mime) =>
      "chgm/" +
      encoded_entry(bucket, Some(key)) +
      "/mime/" +
      @auth.urlsafe_b64(@utf8.encode(mime.view()))
    ChangeType(key, storage_type) =>
      "chtype/" +
      encoded_entry(bucket, Some(key)) +
      "/type/" +
      storage_type.code().to_string()
    ChangeStatus(key, status) =>
      "chstatus/" +
      encoded_entry(bucket, Some(key)) +
      "/status/" +
      status.code().to_string()
    DeleteAfterDays(key, days) =>
      "deleteAfterDays/" +
      encoded_entry(bucket, Some(key)) +
      "/" +
      days.to_string()
    RestoreArchive(key, freeze_after_days) =>
      "restoreAr/" +
      encoded_entry(bucket, Some(key)) +
      "/freezeAfterDays/" +
      freeze_after_days.to_string()
  }
}

///|
fn force_suffix(force : Bool) -> String {
  if force {
    "/force/true"
  } else {
    ""
  }
}

///|
async fn Client::batch_post(
  self : Client,
  body : Bytes,
) -> @transport.Response raise @error.KodoError {
  let url = self.rs_origin() + "/batch"
  let headers = self.auth.qiniu_authorization(url, "POST", body=Some(body), headers=[
    @transport.Header::{ name: "Content-Type", value: @auth.form_mime(), },
  ])
  self.send(@transport.Request::{
    http_method: @transport.Method::Post,
    url,
    headers,
    body: @transport.RequestBody::Bytes(body),
  })
}

///|
fn parse_batch_result(body : String) -> BatchResult {
  let items : Array[BatchItem] = []
  for object in @error.json_array_objects(body) {
    let data = @error.json_object_field(object, "data")
    let error = match data {
      Some(value) => @error.json_string_field(value, "error")
      None => None
    }
    items.push(BatchItem::{
      code: @error.json_int_field(object, "code"),
      error,
      body: object,
    })
  }
  BatchResult::{ items, body, }
}
