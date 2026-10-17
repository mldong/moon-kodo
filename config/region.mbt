///|
/// 一个区域的端点表。官方 `storage/Region.java` 的形状：上传分**源站**与**加速**两组，
/// 取回（iovip）、资源管理（rs）、列举（rsf）、处理（api）各一台，UC 探测是一组可回退的
/// 主机。名字与分组照官方，别自创第二套词汇。
pub(all) struct Region {
  region_id : String
  /// 源站直传主机（官方 `srcUpHosts`）
  src_up_hosts : Array[String]
  /// 加速上传主机（官方 `accUpHosts`）
  acc_up_hosts : Array[String]
  iovip_host : String
  rs_host : String
  rsf_host : String
  api_host : String
  uc_hosts : Array[String]
}

///|
/// 华东 z0 那台的表是手写的，其余区域按同一套命名规则推。这条分叉是官方的
/// （`Region.createWithRegionId` 里 `if (regionId.equals("z0"))` 那一支），照搬是为了
/// 让"我们和官方指到同一台主机"这件事可核对——不是懒得写表。
pub fn Region::with_region_id(region_id : String) -> Region? {
  if region_id.is_empty() {
    None
  } else if region_id == "z0" {
    Some(Region::{
      region_id: "z0",
      src_up_hosts: ["up.qiniup.com"],
      acc_up_hosts: ["upload.qiniup.com"],
      iovip_host: "iovip.qbox.me",
      rs_host: "rs.qbox.me",
      rsf_host: "rsf.qbox.me",
      api_host: "api.qiniuapi.com",
      uc_hosts: default_uc_hosts(),
    })
  } else {
    Some(Region::{
      region_id,
      src_up_hosts: ["up-" + region_id + ".qiniup.com"],
      acc_up_hosts: ["upload-" + region_id + ".qiniup.com"],
      iovip_host: "iovip-" + region_id + ".qiniuio.com",
      rs_host: "rs-" + region_id + ".qiniuapi.com",
      rsf_host: "rsf-" + region_id + ".qiniuapi.com",
      api_host: "api-" + region_id + ".qiniuapi.com",
      uc_hosts: default_uc_hosts(),
    })
  }
}

///|
/// UC 探测主机，照官方 `storage/Configuration.java:33` 的 `defaultUcHosts`
/// （`uc.qiniuapi.com` → `kodo-config.qiniuapi.com` → `uc.qbox.me`）。顺序有意义：
/// 探测按这个次序回退，旧资料里的 `uc.qbox.me` 单台现在是最后一台备份。
pub fn default_uc_hosts() -> Array[String] {
  ["uc.qiniuapi.com", "kodo-config.qiniuapi.com", "uc.qbox.me"]
}
