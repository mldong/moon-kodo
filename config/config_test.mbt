///|
/// 区域表与配置：主机名照官方 `storage/Region.java` 与 `storage/Configuration.java`
/// 现读，不是猜的；`z0` 那一支的手写例外也照搬（卡 §4 D1）。
fn kd_region(id : String) -> @config.Region {
  match @config.Region::with_region_id(id) {
    None => abort("region " + id + " must resolve")
    Some(region) => region
  }
}

///|
fn kd_config(id : String, use_https : Bool) -> @config.Config {
  match @config.Config::with_region_id(id, use_https~) {
    None => abort("config for " + id + " must build")
    Some(cfg) => cfg
  }
}

///|
test "区域 #1 z0 是手写的，其余按命名规则推" {
  let z0 = kd_region("z0")
  assert_eq(z0.region_id, "z0")
  assert_eq(z0.src_up_hosts, ["up.qiniup.com"])
  assert_eq(z0.acc_up_hosts, ["upload.qiniup.com"])
  assert_eq(z0.iovip_host, "iovip.qbox.me")
  assert_eq(z0.rs_host, "rs.qbox.me")
  assert_eq(z0.rsf_host, "rsf.qbox.me")
  assert_eq(z0.api_host, "api.qiniuapi.com")
  // 非 z0 全部走同一条规则：换区域号只改主机名的中段，不改形状
  let z1 = kd_region("z1")
  assert_eq(z1.src_up_hosts, ["up-z1.qiniup.com"])
  assert_eq(z1.acc_up_hosts, ["upload-z1.qiniup.com"])
  assert_eq(z1.iovip_host, "iovip-z1.qiniuio.com")
  assert_eq(z1.rs_host, "rs-z1.qiniuapi.com")
  assert_eq(z1.rsf_host, "rsf-z1.qiniuapi.com")
  assert_eq(z1.api_host, "api-z1.qiniuapi.com")
  let east2 = kd_region("cn-east-2")
  assert_eq(east2.iovip_host, "iovip-cn-east-2.qiniuio.com")
  assert_eq(east2.rs_host, "rs-cn-east-2.qiniuapi.com")
}

///|
test "区域 #2 空区域号解不出来，UC 表按官方那三台" {
  match @config.Region::with_region_id("") {
    None => ()
    Some(region) => fail("空区域号不该解得出：" + region.region_id)
  }
  assert_eq(@config.default_uc_hosts(), [
    "uc.qiniuapi.com", "kodo-config.qiniuapi.com", "uc.qbox.me",
  ])
}

///|
test "配置 #1 默认值与官方 Constants 对齐" {
  let cfg = kd_config("z0", true)
  assert_eq(cfg.scheme(), "https")
  assert_eq(cfg.connect_timeout_ms, 10000)
  assert_eq(cfg.read_timeout_ms, 30000)
  assert_eq(kd_up_origin(cfg, true), "https://upload.qiniup.com")
  assert_eq(kd_up_origin(cfg, false), "https://up.qiniup.com")
  assert_eq(cfg.rs_origin(), "https://rs.qbox.me")
  assert_eq(cfg.iovip_origin(), "https://iovip.qbox.me")
  // 走 http 的那一档：只换 scheme，签名里 Host 不带端口
  let plain = kd_config("na0", false)
  assert_eq(plain.scheme(), "http")
  assert_eq(kd_up_origin(plain, true), "http://upload-na0.qiniup.com")
}

///|
/// `up_origin` 会 raise，断言前先接住。
fn kd_up_origin(cfg : @config.Config, accelerate : Bool) -> String {
  cfg.up_origin(accelerate~) catch {
    err => abort(err.text())
  }
}

///|
/// 空主机表要在**使用任何请求之前**报回来。
fn kd_up_host_text(accelerate : Bool) -> String {
  let region = @config.Region::{
    region_id: "nowhere",
    src_up_hosts: [],
    acc_up_hosts: [],
    iovip_host: "iovip.example.invalid",
    rs_host: "rs.example.invalid",
    rsf_host: "rsf.example.invalid",
    api_host: "api.example.invalid",
    uc_hosts: @config.default_uc_hosts(),
  }
  let host = @config.Config::new(region).up_host(accelerate~) catch {
    err => return "raised:" + err.text()
  }
  "ok:" + host
}

///|
test "配置 #2 区域表配空了就地拒，不带着空主机往下走" {
  assert_eq(
    kd_up_host_text(true),
    "raised:kodo bad param(-4): region nowhere has no accelerated upload host",
  )
  assert_eq(
    kd_up_host_text(false),
    "raised:kodo bad param(-4): region nowhere has no source-station upload host",
  )
}
