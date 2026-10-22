///|
/// 桶配置的写侧：防盗链、maxAge、私有属性、原图保护模式、首页、镜像回源、事件通知。
/// 路径逐条照官方 `BucketManager`（`qiniu/java-sdk@v7.19.0`，2026-10-22 现读）。
///
/// 这些写会改变桶对外的可见行为（`private` 一开就是整桶鉴权），本仓只落离线件：
/// 真桶验证要独立测试桶，绝不在配置桶上真写。

///|
/// `POST /referAntiLeech?bucket=&mode=&norefer=&pattern=&source_enabled=1`
/// （`BucketManager:796` 与 `BucketReferAntiLeech.asQueryString`）。
pub async fn Client::set_refer_anti_leech(
  self : Client,
  mode : Int32,
  pattern~ : String = "",
  allow_empty_referer~ : Bool = true,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_refer_anti_leech")
  if mode < 0 || mode > 2 {
    raise @error.BadParam(
      "referer mode must be 0, 1 or 2, got " + mode.to_string(),
    )
  }
  if mode != 0 && pattern.is_empty() {
    raise @error.BadParam("referer whitelist/blacklist mode needs a pattern")
  }
  let response = self.uc_post(
    "/referAntiLeech?bucket=" +
    form_encode(target) +
    "&mode=" +
    mode.to_string() +
    "&norefer=" +
    bool_int(allow_empty_referer) +
    "&pattern=" +
    form_encode(pattern) +
    "&source_enabled=1",
  )
  discard_body(response)
}

///|
/// `POST /maxAge?bucket=&maxAge=<n>`（`BucketManager:1051`）。0 或负数表示回到默认值。
pub async fn Client::set_bucket_max_age(
  self : Client,
  max_age : Int64,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_bucket_max_age")
  let response = self.uc_post(
    "/maxAge?bucket=" + form_encode(target) + "&maxAge=" + max_age.to_string(),
  )
  discard_body(response)
}

///|
/// `POST /private?bucket=&private=<0|1>`（`BucketManager:1068`）：0 公有、1 私有。
pub async fn Client::set_bucket_private(
  self : Client,
  private : Bool,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_bucket_private")
  let response = self.uc_post(
    "/private?bucket=" + form_encode(target) + "&private=" + bool_int(private),
  )
  discard_body(response)
}

///|
/// `POST /accessMode/<bucket>/mode/<0|1>`（`BucketManager:1034`）：原图保护模式开关。
pub async fn Client::set_bucket_access_style(
  self : Client,
  open : Bool,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_bucket_access_style")
  let response = self.uc_post(
    "/accessMode/" + form_encode(target) + "/mode/" + bool_int(open),
  )
  discard_body(response)
}

///|
/// `POST /noIndexPage?bucket=&noIndexPage=<0|1>`（`BucketManager:754`）：
/// 0 表示有首页（HAS），1 表示关闭（NO）；这里直接收"是否关闭"。
pub async fn Client::set_index_page(
  self : Client,
  no_index : Bool,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_index_page")
  let response = self.uc_post(
    "/noIndexPage?bucket=" +
    form_encode(target) +
    "&noIndexPage=" +
    bool_int(no_index),
  )
  discard_body(response)
}

///|
/// `POST /image/<bucket>/from/<urlsafe_b64(src)>[/host/<urlsafe_b64(host)>]`
/// （`BucketManager:692-718`；官方已标 `@Deprecated`）。
pub async fn Client::set_bucket_image(
  self : Client,
  source_site_url : String,
  host~ : String = "",
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "set_bucket_image")
  if source_site_url.is_empty() {
    raise @error.BadParam("set_bucket_image needs a source url")
  }
  let response = self.uc_post(image_path(target, source_site_url, host))
  discard_body(response)
}

///|
/// `POST /unimage/<bucket>`（`BucketManager:728`）。
pub async fn Client::unset_bucket_image(
  self : Client,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "unset_bucket_image")
  let response = self.uc_post("/unimage/" + form_encode(target))
  discard_body(response)
}

///|
/// `POST /events/add?bucket=&<rule>`（`BucketManager:899`）。
pub async fn Client::add_event_rule(
  self : Client,
  rule : EventRule,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "add_event_rule")
  check_event_rule(rule)
  let response = self.uc_post(
    "/events/add?bucket=" + form_encode(target) + "&" + event_rule_query(rule),
  )
  discard_body(response)
}

///|
/// `POST /events/update?bucket=&<rule>`（`BucketManager:933`）。
pub async fn Client::update_event_rule(
  self : Client,
  rule : EventRule,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "update_event_rule")
  check_event_rule(rule)
  let response = self.uc_post(
    "/events/update?bucket=" +
    form_encode(target) +
    "&" +
    event_rule_query(rule),
  )
  discard_body(response)
}

///|
/// `POST /events/delete?bucket=&name=`（`BucketManager:916`）。
pub async fn Client::delete_event_rule(
  self : Client,
  name : String,
  bucket~ : String? = None,
) -> Unit raise @error.KodoError {
  let target = require_bucket(self, bucket, "delete_event_rule")
  if name.is_empty() {
    raise @error.BadParam("delete_event_rule needs a rule name")
  }
  let response = self.uc_post(
    "/events/delete?bucket=" +
    form_encode(target) +
    "&name=" +
    form_encode(name),
  )
  discard_body(response)
}

///|
pub fn image_path(
  bucket : String,
  source_site_url : String,
  host : String,
) -> String {
  let mut path = "/image/" +
    form_encode(bucket) +
    "/from/" +
    @auth.urlsafe_b64(@utf8.encode(source_site_url))
  if !host.is_empty() {
    path = path + "/host/" + @auth.urlsafe_b64(@utf8.encode(host))
  }
  path
}

///|
/// 官方 `BucketEventRule.asQueryString`（`:210-237`）：`event` 与 `callbackURL` 都可重复。
pub fn event_rule_query(rule : EventRule) -> String {
  let parts : Array[String] = [
    "name=" + form_encode(rule.name),
    "prefix=" + form_encode(rule.prefix),
    "suffix=" + form_encode(rule.suffix),
  ]
  for event in rule.events {
    parts.push("event=" + form_encode(event))
  }
  for url in rule.callback_urls {
    parts.push("callbackURL=" + form_encode(url))
  }
  if !rule.access_key.is_empty() {
    parts.push("access_key=" + form_encode(rule.access_key))
  }
  if !rule.host.is_empty() {
    parts.push("host=" + form_encode(rule.host))
  }
  parts.join("&")
}

///|
fn check_event_rule(rule : EventRule) -> Unit raise @error.KodoError {
  if rule.name.is_empty() {
    raise @error.BadParam("event rule needs a name")
  }
  if rule.events.is_empty() {
    raise @error.BadParam("event rule needs at least one event")
  }
  if rule.callback_urls.is_empty() {
    raise @error.BadParam("event rule needs at least one callback url")
  }
}

///|
fn bool_int(value : Bool) -> String {
  if value {
    "1"
  } else {
    "0"
  }
}
