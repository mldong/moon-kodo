///|
/// 一次 Kodo 调用需要的环境：区域端点表、走不走 HTTPS、两个超时。
/// 超时值取官方 `common/Constants.java` 的默认（连接 10s、读 30s），单位在这里就换成
/// 毫秒，免得每层调用方各自换算一次。
pub(all) struct Config {
  region : Region
  use_https : Bool
  connect_timeout_ms : Int32
  read_timeout_ms : Int32
}

///|
pub fn Config::new(
  region : Region,
  use_https~ : Bool = true,
  connect_timeout_ms~ : Int32 = 10000,
  read_timeout_ms~ : Int32 = 30000,
) -> Config {
  Config::{ region, use_https, connect_timeout_ms, read_timeout_ms, }
}

///|
pub fn Config::with_region_id(
  region_id : String,
  use_https~ : Bool = true,
  connect_timeout_ms~ : Int32 = 10000,
  read_timeout_ms~ : Int32 = 30000,
) -> Config? {
  match Region::with_region_id(region_id) {
    None => None
    Some(region) =>
      Some(
        Config::new(region, use_https~, connect_timeout_ms~, read_timeout_ms~),
      )
  }
}

///|
pub fn Config::scheme(self : Config) -> String {
  if self.use_https {
    "https"
  } else {
    "http"
  }
}

///|
/// UC 管理的 origin。官方 `BucketManager` 的桶管理接口走 `configHelper.ucHost()`，
/// 探测表的第一台就是它；列表为空属于配置错误，在任何请求之前拒。
pub fn Config::uc_origin(self : Config) -> String raise @error.KodoError {
  if self.region.uc_hosts.is_empty() {
    raise @error.BadParam("region has no UC host")
  }
  self.scheme() + "://" + self.region.uc_hosts[0]
}

///|
/// 上传主机。默认走加速组（官方表单/分块上传的常用档），源站留着给内网场景显式点名。
/// 空表在**使用任何请求之前**就拒掉——区域表是配出来的，配错了要立刻听见。
pub fn Config::up_host(
  self : Config,
  accelerate~ : Bool = true,
) -> String raise @error.KodoError {
  let hosts = if accelerate {
    self.region.acc_up_hosts
  } else {
    self.region.src_up_hosts
  }
  if hosts.is_empty() {
    raise @error.BadParam(
      "region " +
      self.region.region_id +
      " has no " +
      (if accelerate { "accelerated" } else { "source-station" }) +
      " upload host",
    )
  } else {
    hosts[0]
  }
}

///|
/// 上传接口的 origin（scheme + 主机），D2 的请求构造从这里起头。
pub fn Config::up_origin(
  self : Config,
  accelerate~ : Bool = true,
) -> String raise @error.KodoError {
  self.scheme() + "://" + self.up_host(accelerate~)
}

///|
/// 资源管理（rs）的 origin。
pub fn Config::rs_origin(self : Config) -> String {
  self.scheme() + "://" + self.region.rs_host
}

///|
/// 列举（rsf）走的是另一台主机，不能拿 rs 顶——官方 `listV1` 用的是
/// `configHelper.rsfHost(...)`（`BucketManager.java:219-224`）。
pub fn Config::rsf_origin(self : Config) -> String {
  self.scheme() + "://" + self.region.rsf_host
}

///|
/// 取回（iovip，私有 URL 的下载域名之外的兜底）。
pub fn Config::iovip_origin(self : Config) -> String {
  self.scheme() + "://" + self.region.iovip_host
}
