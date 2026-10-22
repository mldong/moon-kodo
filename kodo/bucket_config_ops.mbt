///|
/// 桶配置族：查询空间信息、CORS、生命周期、配额、事件通知。
/// 路径与查询参数逐条照官方 `BucketManager`（`qiniu/java-sdk@v7.19.0`，2026-10-22 现读）：
///
/// - 空间信息 `/v2/bucketInfo?bucket=`（`:778-786`）
/// - 生命周期 `/rules/add|update|delete|get?bucket=`（`:814-890`）
/// - 事件通知 `/events/add|update|delete|get?bucket=`（`:899-976`）
/// - CORS `/corsRules/set/{bucket}` 与 `/corsRules/get/{bucket}`（`:984-1022`）
/// - 配额 `/setbucketquota/{bucket}/size/{size}/count/{count}`、`/getbucketquota/{bucket}`（`:1099-1121`）
///
/// 全部走 UC 主机与 `QBox` 签名。写侧只落离线件：改共享测试桶的配置会改别人读到的行为，
/// 真桶验证要等独立测试桶那一档（见交接件待拍第 9 条）。

///|
/// `GET /v2/bucketInfo` 的读数。字段按官方 `BucketInfo` 的 JSON 名读，
/// 缺键一律回 `None`/空数组（不拿 0 冒充"读到 0"）。
pub(all) struct BucketInfo {
  body : String
  zone : String?
  region : String?
  private_flag : Int64?
  protected_flag : Int64?
  max_age : Int64?
  no_index_page : Int64?
  global : Bool?
  anti_leech_mode : Int64?
  no_refer : Bool?
  refer_white : Array[String]
  refer_black : Array[String]
}

///|
/// 一条 CORS 规则。JSON 键是单数（`allowed_origin`），读写在 [CorsRule] 里统一成复数。
pub(all) struct CorsRule {
  allowed_origins : Array[String]
  allowed_methods : Array[String]
  allowed_headers : Array[String]
  exposed_headers : Array[String]
  max_age : Int64
}

///|
/// 官方构造器只强制 origin 与 method 两项，其余三项有默认值。
pub fn CorsRule::new(
  allowed_origins : Array[String],
  allowed_methods : Array[String],
) -> CorsRule {
  CorsRule::{
    allowed_origins,
    allowed_methods,
    allowed_headers: [],
    exposed_headers: [],
    max_age: 0L,
  }
}

///|
pub fn CorsRule::with_extra(
  self : CorsRule,
  allowed_headers~ : Array[String] = [],
  exposed_headers~ : Array[String] = [],
  max_age~ : Int64 = 0L,
) -> CorsRule {
  CorsRule::{
    allowed_origins: self.allowed_origins,
    allowed_methods: self.allowed_methods,
    allowed_headers,
    exposed_headers,
    max_age,
  }
}

///|
pub(all) struct CorsRules {
  rules : Array[CorsRule]
  body : String
}

///|
/// 一条生命周期规则。五个天数字段与官方同名（`0` 不转/不删，负数表示"立即"）。
pub(all) struct LifecycleRule {
  name : String
  prefix : String
  delete_after_days : Int64
  to_line_after_days : Int64
  to_archive_ir_after_days : Int64
  to_archive_after_days : Int64
  to_deep_archive_after_days : Int64
}

///|
pub fn LifecycleRule::new(
  name : String,
  prefix~ : String = "",
) -> LifecycleRule {
  LifecycleRule::{
    name,
    prefix,
    delete_after_days: 0L,
    to_line_after_days: 0L,
    to_archive_ir_after_days: 0L,
    to_archive_after_days: 0L,
    to_deep_archive_after_days: 0L,
  }
}

///|
pub(all) struct LifecycleRules {
  rules : Array[LifecycleRule]
  body : String
}

///|
pub(all) struct BucketQuota {
  size : Int64?
  count : Int64?
  body : String
}

///|
/// 一条事件通知规则。官方字段名照 `BucketEventRule`（`events` / `callback_urls`）。
pub(all) struct EventRule {
  name : String
  prefix : String
  suffix : String
  events : Array[String]
  callback_urls : Array[String]
  access_key : String
  host : String
}

///|
pub(all) struct EventRules {
  rules : Array[EventRule]
  body : String
}

///|
/// `POST {uc}/v2/bucketInfo?bucket=<bucket>`。
pub async fn Client::bucket_info(
  self : Client,
  bucket~ : String? = None,
) -> BucketInfo raise @error.KodoError {
  let target = require_bucket(self, bucket, "bucket_info")
  let response = self.uc_post("/v2/bucketInfo?bucket=" + form_encode(target))
  let text = read_text(response.body)
  bucket_info_of(text)
}

///|
/// `POST {uc}/corsRules/get/<bucket>`：未配置时回 `null`，这里落成空数组。
pub async fn Client::cors_rules(
  self : Client,
  bucket~ : String? = None,
) -> CorsRules raise @error.KodoError {
  let target = require_bucket(self, bucket, "cors_rules")
  let response = self.uc_post("/corsRules/get/" + form_encode(target))
  let text = read_text(response.body)
  CorsRules::{ rules: parse_cors_rules(text), body: text, }
}

///|
/// `POST {uc}/corsRules/set/<bucket>`，JSON 体是规则数组。
/// 官方上限 10 条；origin/method 缺一条服务端也会拒，两者都在发之前拦。
pub async fn Client::set_cors_rules(
  self : Client,
  rules : Array[CorsRule],
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_cors_rules")
  if rules.length() > 10 {
    raise @error.BadParam(
      "at most 10 CORS rules are allowed, got " + rules.length().to_string(),
    )
  }
  for rule in rules {
    if rule.allowed_origins.length() == 0 {
      raise @error.BadParam("a CORS rule needs at least one allowed origin")
    }
    if rule.allowed_methods.length() == 0 {
      raise @error.BadParam("a CORS rule needs at least one allowed method")
    }
  }
  let response = self.uc_post_json(
    "/corsRules/set/" + form_encode(target),
    cors_rules_json(rules),
  )
  discard_body(response)
}

///|
/// `POST {uc}/rules/get?bucket=`：未配置时回 `null`，这里落成空数组。
pub async fn Client::lifecycle_rules(
  self : Client,
  bucket~ : String? = None,
) -> LifecycleRules raise @error.KodoError {
  let target = require_bucket(self, bucket, "lifecycle_rules")
  let response = self.uc_post("/rules/get?bucket=" + form_encode(target))
  let text = read_text(response.body)
  LifecycleRules::{ rules: parse_lifecycle_rules(text), body: text, }
}

///|
/// `POST {uc}/rules/add?bucket=&<rule query>`。
pub async fn Client::add_lifecycle_rule(
  self : Client,
  rule : LifecycleRule,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "add_lifecycle_rule")
  let response = self.uc_post(
    "/rules/add?bucket=" +
    form_encode(target) +
    "&" +
    lifecycle_rule_query(rule),
  )
  discard_body(response)
}

///|
/// `POST {uc}/rules/update?bucket=&<rule query>`：按 name 改，name 不存在服务端拒。
pub async fn Client::update_lifecycle_rule(
  self : Client,
  rule : LifecycleRule,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "update_lifecycle_rule")
  let response = self.uc_post(
    "/rules/update?bucket=" +
    form_encode(target) +
    "&" +
    lifecycle_rule_query(rule),
  )
  discard_body(response)
}

///|
/// `POST {uc}/rules/delete?bucket=&name=`。
pub async fn Client::delete_lifecycle_rule(
  self : Client,
  name : String,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "delete_lifecycle_rule")
  if name.is_empty() {
    raise @error.BadParam("delete_lifecycle_rule needs a rule name")
  }
  let response = self.uc_post(
    "/rules/delete?bucket=" + form_encode(target) + "&name=" + form_encode(name),
  )
  discard_body(response)
}

///|
/// `POST {uc}/getbucketquota/<bucket>`：配额未设时官方回 `size`/`count` 为 0。
pub async fn Client::bucket_quota(
  self : Client,
  bucket~ : String? = None,
) -> BucketQuota raise @error.KodoError {
  let target = require_bucket(self, bucket, "bucket_quota")
  let response = self.uc_post("/getbucketquota/" + form_encode(target))
  let text = read_text(response.body)
  bucket_quota_of(text)
}

///|
/// `POST {uc}/setbucketquota/<bucket>/size/<size>/count/<count>`。
/// 官方语义：`0` 不更改当前配置，`-1` 取消限额。
pub async fn Client::set_bucket_quota(
  self : Client,
  size : Int64,
  count : Int64,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_bucket_quota")
  let response = self.uc_post(
    "/setbucketquota/" +
    form_encode(target) +
    "/size/" +
    size.to_string() +
    "/count/" +
    count.to_string(),
  )
  discard_body(response)
}

///|
/// `POST {uc}/events/get?bucket=`：未配置时回 `null`，这里落成空数组。
/// 写侧（add/update/delete）与官方三个入口对齐留到下一批：事件规则字段多，
/// 先把读侧与结构立住。
pub async fn Client::event_rules(
  self : Client,
  bucket~ : String? = None,
) -> EventRules raise @error.KodoError {
  let target = require_bucket(self, bucket, "event_rules")
  let response = self.uc_post("/events/get?bucket=" + form_encode(target))
  let text = read_text(response.body)
  EventRules::{ rules: parse_event_rules(text), body: text, }
}

///|
fn require_bucket(
  client : Client,
  bucket : String?,
  op : String,
) -> String raise @error.KodoError {
  let target = bucket.unwrap_or(client.bucket)
  if target.is_empty() {
    raise @error.BadParam(op + " needs a bucket name")
  }
  target
}

///|
fn bucket_info_of(text : String) -> BucketInfo {
  BucketInfo::{
    body: text,
    zone: @error.json_string_field(text, "zone"),
    region: @error.json_string_field(text, "region"),
    private_flag: @error.json_int_field(text, "private"),
    protected_flag: @error.json_int_field(text, "protected"),
    max_age: @error.json_int_field(text, "max_age"),
    no_index_page: @error.json_int_field(text, "no_index_page"),
    global: @error.json_bool_field(text, "global"),
    anti_leech_mode: @error.json_int_field(text, "anti_leech_mode"),
    no_refer: @error.json_bool_field(text, "no_refer"),
    refer_white: @error.json_string_array(text, "refer_wl"),
    refer_black: @error.json_string_array(text, "refer_bl"),
  }
}

///|
fn bucket_quota_of(text : String) -> BucketQuota {
  BucketQuota::{
    size: @error.json_int_field(text, "size"),
    count: @error.json_int_field(text, "count"),
    body: text,
  }
}

///|
/// 规则数组的 JSON。键名照官方 `CorsRule` 的 `@SerializedName`（单数）。
pub fn cors_rules_json(rules : Array[CorsRule]) -> String {
  let rows : Array[String] = []
  for rule in rules {
    rows.push(
      "{" +
      "\"allowed_origin\":" +
      json_string_list(rule.allowed_origins) +
      ",\"allowed_method\":" +
      json_string_list(rule.allowed_methods) +
      ",\"allowed_header\":" +
      json_string_list(rule.allowed_headers) +
      ",\"exposed_header\":" +
      json_string_list(rule.exposed_headers) +
      ",\"max_age\":" +
      rule.max_age.to_string() +
      "}",
    )
  }
  "[" + rows.join(",") + "]"
}

///|
fn json_string_list(items : Array[String]) -> String {
  let quoted : Array[String] = []
  for item in items {
    quoted.push(@error.json_quote(item))
  }
  "[" + quoted.join(",") + "]"
}

///|
/// 官方的规则查询串（`:230-240`）。值走 `form_encode`：前缀里带 `/`、空格或非 ASCII 时
/// 不编码会拼出装不下的 URL；签名与发出用的是同一串，不会分叉。
pub fn lifecycle_rule_query(rule : LifecycleRule) -> String {
  "name=" +
  form_encode(rule.name) +
  "&prefix=" +
  form_encode(rule.prefix) +
  "&delete_after_days=" +
  rule.delete_after_days.to_string() +
  "&to_line_after_days=" +
  rule.to_line_after_days.to_string() +
  "&to_archive_ir_after_days=" +
  rule.to_archive_ir_after_days.to_string() +
  "&to_archive_after_days=" +
  rule.to_archive_after_days.to_string() +
  "&to_deep_archive_after_days=" +
  rule.to_deep_archive_after_days.to_string()
}

///|
fn parse_cors_rules(text : String) -> Array[CorsRule] {
  let out : Array[CorsRule] = []
  for row in @error.json_array_objects(text) {
    out.push(CorsRule::{
      allowed_origins: @error.json_string_array(row, "allowed_origin"),
      allowed_methods: @error.json_string_array(row, "allowed_method"),
      allowed_headers: @error.json_string_array(row, "allowed_header"),
      exposed_headers: @error.json_string_array(row, "exposed_header"),
      max_age: @error.json_int_field(row, "max_age").unwrap_or(0L),
    })
  }
  out
}

///|
fn parse_lifecycle_rules(text : String) -> Array[LifecycleRule] {
  let out : Array[LifecycleRule] = []
  for row in @error.json_array_objects(text) {
    out.push(LifecycleRule::{
      name: @error.json_string_field(row, "name").unwrap_or(""),
      prefix: @error.json_string_field(row, "prefix").unwrap_or(""),
      delete_after_days: @error.json_int_field(row, "delete_after_days").unwrap_or(
        0L,
      ),
      to_line_after_days: @error.json_int_field(row, "to_line_after_days").unwrap_or(
        0L,
      ),
      to_archive_ir_after_days: @error.json_int_field(
        row, "to_archive_ir_after_days",
      ).unwrap_or(0L),
      to_archive_after_days: @error.json_int_field(row, "to_archive_after_days").unwrap_or(
        0L,
      ),
      to_deep_archive_after_days: @error.json_int_field(
        row, "to_deep_archive_after_days",
      ).unwrap_or(0L),
    })
  }
  out
}

///|
fn parse_event_rules(text : String) -> Array[EventRule] {
  let out : Array[EventRule] = []
  for row in @error.json_array_objects(text) {
    out.push(EventRule::{
      name: @error.json_string_field(row, "name").unwrap_or(""),
      prefix: @error.json_string_field(row, "prefix").unwrap_or(""),
      suffix: @error.json_string_field(row, "suffix").unwrap_or(""),
      events: @error.json_string_array(row, "events"),
      callback_urls: @error.json_string_array(row, "callback_urls"),
      access_key: @error.json_string_field(row, "access_key").unwrap_or(""),
      host: @error.json_string_field(row, "host").unwrap_or(""),
    })
  }
  out
}

///|
/// UC 的 JSON body POST。QBox 签名只把 body 计入待签串的那一档是
/// `application/x-www-form-urlencoded`（见 `auth/auth.mbt` 的 `qbox_signing_string`），
/// 所以这里传 JSON 体只为完整性，签名与 `Content-Type` 两头仍走同一份字节。
async fn Client::uc_post_json(
  self : Client,
  path : String,
  body : String,
) -> @transport.Response raise @error.KodoError {
  let url = self.config.uc_origin() + path
  let payload = @utf8.encode(body)
  let headers = [
    self.auth.qbox_authorization(
      url,
      body=Some(payload),
      content_type=Some("application/json"),
    ),
    @transport.Header::{ name: "Content-Type", value: "application/json", },
  ]
  self.send(@transport.Request::{
    http_method: @transport.Method::Post,
    url,
    headers,
    body: @transport.RequestBody::Bytes(payload),
  })
}
