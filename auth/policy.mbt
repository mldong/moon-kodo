///|
/// 上传策略的一个值。官方 `StringMap.put(String, Object)` 靠运行时类型决定 JSON 里
/// 是数字还是字符串，JSON 类型错了服务端就按缺省处理——所以这里把它做成三种显式档。
pub(all) enum PolicyValue {
  Text(String)
  Count(Int64)
  Flag(Bool)
}

///|
pub(all) struct PolicyField {
  key : String
  value : PolicyValue
}

///|
/// 上传策略。字段顺序是**我们**定的（按传入次序，`scope`/`deadline` 拼在后面）：
/// 官方用 `StringMap`（HashMap）+ Gson，键序本身就不稳定，服务端是解析 JSON 而不是
/// 比对文本，所以顺序不参与有效性、只参与可复现性。
pub(all) struct UploadPolicy {
  fields : Array[PolicyField]
}

///|
pub fn UploadPolicy::new() -> UploadPolicy {
  UploadPolicy::{ fields: [], }
}

///|
/// 追加一项。同名键**不去重**（官方 `put` 是覆盖，这里让调用方自己负责——去重会藏住
/// 配置错误），但 `scope`/`deadline` 这两个保留键在 strict 档会被白名单外的分支拒掉。
pub fn UploadPolicy::put(
  self : UploadPolicy,
  key : String,
  value : PolicyValue,
) -> UploadPolicy {
  UploadPolicy::{ fields: self.fields + [PolicyField::{ key, value, }], }
}

///|
/// 官方 `Auth.policyFields` 那 26 项（`util/Auth.java:32-62`），逐项照抄。
fn policy_whitelist() -> Array[String] {
  [
    "callbackUrl", "callbackBody", "callbackHost", "callbackBodyType", "callbackFetchKey",
    "returnUrl", "returnBody", "endUser", "saveKey", "forceSaveKey", "insertOnly",
    "isPrefixalScope", "detectMime", "mimeLimit", "fsizeLimit", "fsizeMin", "trafficLimit",
    "persistentType", "persistentOps", "persistentNotifyUrl", "persistentPipeline",
    "persistentWorkflowTemplateID", "deleteAfterDays", "fileType",
  ]
}

///|
/// 官方 `deprecatedPolicyFields`：命中即抛，不是静默丢弃（`util/Auth.java:63-65,92-94`）。
fn deprecated_policy_fields() -> Array[String] {
  ["asyncOps"]
}

///|
/// `copyPolicy`：先拦废弃键，再按 strict 决定白名单外的键是否丢掉。
fn copy_policy(
  policy : UploadPolicy,
  strict : Bool,
) -> Array[PolicyField] raise @error.KodoError {
  let keep : Array[PolicyField] = []
  let allowed = policy_whitelist()
  for field in policy.fields {
    if deprecated_policy_fields().contains(field.key) {
      raise @error.BadParam(field.key + " is deprecated!")
    }
    if !strict || allowed.contains(field.key) {
      keep.push(field)
    }
  }
  keep
}

///|
/// 策略 → JSON 文本。只覆盖协议需要的三种标量，不做通用序列化器。
fn upload_policy_json(
  policy : UploadPolicy,
  scope : String,
  deadline : Int64,
  strict : Bool,
) -> String raise @error.KodoError {
  let parts : Array[String] = []
  for field in copy_policy(policy, strict) {
    let encoded = match field.value {
      Text(text) => @error.json_quote(text)
      Count(n) => n.to_string()
      Flag(b) => b.to_string()
    }
    parts.push(@error.json_quote(field.key) + ":" + encoded)
  }
  parts.push(@error.json_quote("scope") + ":" + @error.json_quote(scope))
  parts.push(@error.json_quote("deadline") + ":" + deadline.to_string())
  "{" + parts.join(",") + "}"
}

///|
/// scope：`bucket`，或给了 key 就是 `bucket:key`（官方 `uploadTokenWithDeadline`）。
fn upload_scope(bucket : String, key : String?) -> String {
  match key {
    None => bucket
    Some(name) => bucket + ":" + name
  }
}
