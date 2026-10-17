///|
/// 区域探测（卡 §4 D1 的 `auto_region`，§6 KD2）。
///
/// 形状照官方：`GET https://{uc}/v4/query?ak={ak}&bucket={bucket}`，**不带签名**
/// （`storage/ApiQueryRegion.java:78-93` 只往 query 里放这两个值），响应里 `hosts`
/// 是区域数组，默认取第 0 条（官方 `getDefaultRegion()` 就是 `getRegion(0)`）。
/// 三台 UC 主机按 `Region.uc_hosts` 的顺序回退（`uc.qiniuapi.com` →
/// `kodo-config.qiniuapi.com` → `uc.qbox.me`，官方 `Configuration.java:33`）。

///|
pub(all) struct UcGroup {
  domains : Array[String]?
  old : Array[String]?
} derive(@json.FromJson, @json.ToJson, Eq)

///|
pub(all) struct UcHostEntry {
  region : String
  up : UcGroup?
  io : UcGroup?
  rs : UcGroup?
  rsf : UcGroup?
  api : UcGroup?
} derive(@json.FromJson, @json.ToJson, Eq)

///|
pub(all) struct UcQueryResult {
  hosts : Array[UcHostEntry]
} derive(@json.FromJson, @json.ToJson, Eq)

///|
pub extend UcGroup with @json.FromJson::{from_json}

///|
pub extend UcGroup with @json.ToJson::{to_json}

///|
pub extend UcGroup with Eq::{equal, not_equal}

///|
pub extend UcHostEntry with @json.FromJson::{from_json}

///|
pub extend UcHostEntry with @json.ToJson::{to_json}

///|
pub extend UcHostEntry with Eq::{equal, not_equal}

///|
pub extend UcQueryResult with @json.FromJson::{from_json}

///|
pub extend UcQueryResult with @json.ToJson::{to_json}

///|
pub extend UcQueryResult with Eq::{equal, not_equal}

///|
/// 探测结果：折好的 Region、命中哪台 uc 主机、以及响应给的 ttl（官方靠 ttl 决定
/// 多久重新探测；KD2 要的读数就是这三样）。
/// ttl 从响应原文里用 `@error.json_int_field` 读：derive 的 FromJson 读不进 JSON 数字
/// （见本文件末与用例"区域探测 #0"）。
pub(all) struct RegionProbe {
  region : @config.Region
  uc_host : String
  ttl : Int64?
}

///|
/// 一台主机的探测结果。失败原因必须带着走——吞掉就分不出"这台不通"与"探测没跑"。
pub(all) enum ProbeOutcome {
  /// 解析出的结构 + **响应原文**：数字字段走自写扫描器读，不从 derive 的结构里取
  /// 第二条是**响应原文**：数字字段由 `@error.json_int_field` 从原文读
  Found(UcQueryResult, String)
  Refused(String)
}

///|
/// `domains` 优先，其次官方的 `old` 那组（旧配置里常见的 `*.qbox.me`）。
fn group_hosts(group : UcGroup?) -> Array[String] {
  let empty : Array[String] = []
  match group {
    None => empty
    Some(g) => {
      let direct = match g.domains {
        None => empty
        Some(list) => list
      }
      if direct.length() > 0 {
        direct
      } else {
        match g.old {
          None => empty
          Some(list) => list
        }
      }
    }
  }
}

///|
/// 取这一组里的第一台；一组都没有就用兜底名（兜底名来自"按区域号推"那张表）。
fn group_host(group : UcGroup?, fallback : String) -> String {
  let candidates = group_hosts(group)
  if candidates.length() > 0 {
    candidates[0]
  } else {
    fallback
  }
}

///|
/// 把 `hosts[0]` 折成 Region。探测没给的每一项都回落到"按区域号推"的名字
/// （与官方 `createWithRegionId` 一致），不是随便挑一台。
pub fn region_from_probe(
  entry : UcHostEntry,
  uc_hosts : Array[String],
) -> @config.Region {
  let guessed = match @config.Region::with_region_id(entry.region) {
    None => abort("region id from probe is unusable: " + entry.region)
    Some(region) => region
  }
  let up_hosts = group_hosts(entry.up)
  let src = if up_hosts.is_empty() { guessed.src_up_hosts } else { up_hosts }
  let acc = if up_hosts.is_empty() { guessed.acc_up_hosts } else { up_hosts }
  @config.Region::{
    region_id: entry.region,
    src_up_hosts: src,
    acc_up_hosts: acc,
    iovip_host: group_host(entry.io, guessed.iovip_host),
    rs_host: group_host(entry.rs, guessed.rs_host),
    rsf_host: group_host(entry.rsf, guessed.rsf_host),
    api_host: group_host(entry.api, guessed.api_host),
    uc_hosts,
  }
}

///|
/// 解析 UC 响应。拆出来单独可测——离线的形状判据不必联网。
pub fn parse_uc_result(text : String) -> UcQueryResult raise @error.KodoError {
  let value = @json.parse(text) catch {
    _ => raise @error.BadParam("region query body is not json")
  }
  let parsed : UcQueryResult = @json.from_json(value) catch {
    _ => raise @error.BadParam("region query shape unreadable")
  }
  parsed
}

///|
/// 试一台 UC 主机。连不上是"这台不通"（`Refused` 带读数），传输层抛出来的那一档
/// 转成 `KodoError` 报出去——两种失败在判据里不是一回事。
async fn try_one_uc(
  transport : &@transport.Transport,
  host : String,
  access_key : String,
  bucket : String,
) -> ProbeOutcome raise @error.KodoError {
  let url = "https://" +
    host +
    "/v4/query?ak=" +
    access_key +
    "&bucket=" +
    bucket
  let response = transport.send(@transport.Request::{
    http_method: @transport.Method::Get,
    url,
    headers: [],
    body: @transport.RequestBody::Empty,
  }) catch {
    err => raise @error.Network(transport_text(err))
  }
  if response.status < 200 || response.status >= 300 {
    let code = response.status.to_string()
    let body = read_text(response.body)
    return ProbeOutcome::Refused("status " + code + " body " + trim_body(body))
  }
  let text = read_text(response.body)
  ProbeOutcome::Found(parse_uc_result(text), text)
}

///|
/// 挨个试 UC 主机，第一个带回非空 `hosts` 的就用；全部失败时把**每一台**的读数
/// 一起报出去，免得只看到最后一句错误。
pub async fn query_region(
  transport : &@transport.Transport,
  access_key : String,
  bucket : String,
  uc_hosts~ : Array[String]? = None,
) -> RegionProbe raise @error.KodoError {
  if access_key.is_empty() || bucket.is_empty() {
    raise @error.BadParam("region query needs both access key and bucket")
  }
  let hosts = match uc_hosts {
    None => @config.default_uc_hosts()
    Some(list) => list
  }
  let notes : Array[String] = []
  let mut chosen : RegionProbe? = None
  for host in hosts {
    if chosen is None {
      let outcome = try_one_uc(transport, host, access_key, bucket) catch {
        err => ProbeOutcome::Refused(err.text())
      }
      match outcome {
        ProbeOutcome::Refused(why) => notes.push(host + " -> " + why)
        ProbeOutcome::Found(result, raw) =>
          if result.hosts.length() == 0 {
            notes.push(host + " -> empty hosts array")
          } else {
            let entry = result.hosts[0]
            chosen = Some(RegionProbe::{
              region: region_from_probe(entry, hosts),
              uc_host: host,
              // 数字字段从原文里读：derive 的 FromJson 读不进 JSON 数字
              ttl: @error.json_int_field(raw, "ttl"),
            })
          }
      }
    }
  }
  match chosen {
    None =>
      raise @error.Network(
        "region query failed on every uc host: " + notes.join(" | "),
      )
    Some(probe) => probe
  }
}

///|
fn transport_text(err : @transport.TransportError) -> String {
  match err {
    @transport.TransportError::Network(detail) => "network: " + detail
    @transport.TransportError::Timeout => "timeout"
    @transport.TransportError::InvalidRequest(detail) =>
      "invalid request: " + detail
    @transport.TransportError::InvalidResponse(detail) =>
      "invalid response: " + detail
  }
}

///|
fn trim_body(text : String) -> String {
  if text.length() > 160 {
    text[0:160].to_owned() + "..."
  } else {
    text
  }
}
