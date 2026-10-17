///|
/// 区域探测的形状判据（离线）。样例是 2026-10-17 从 `uc.qiniuapi.com/v4/query` 真取回
/// 的响应**改名**而来：区域号与主机名换成不与真桶相撞的样例值，字段集与层级照真的那份
/// （`hosts` 与 `ttl` 在顶层；`io_src` / `s3` / `uc` 这些我们用不到的键也留着）。
/// 这份 JSON 里没有凭据，也不指向任何真桶。
fn uc_sample() -> String {
  "{\"hosts\":[{\"api\":{\"domains\":[\"api-sample.qiniu.com\"]},\"io\":{\"domains\":[\"iovip-sample.qbox.me\"]},\"io_src\":{\"domains\":[\"iosrc-sample.qiniuio.com\"]},\"region\":\"z9\",\"rs\":{\"domains\":[\"rs-sample.qbox.me\"]},\"rsf\":{\"domains\":[\"rsf-sample.qbox.me\"]},\"s3\":{\"domains\":[\"s3-sample.qiniucs.com\"],\"region_alias\":\"sample-south-1\"},\"ttl\":86400,\"uc\":{\"domains\":[\"uc-sample.qiniuapi.com\"]},\"up\":{\"domains\":[\"upload-sample.qiniup.com\",\"up-sample.qiniup.com\"],\"old\":[\"upload-sample.qbox.me\",\"up-sample.qbox.me\"]}}],\"ttl\":86400}"
}

///|
/// 两档同型才好断言：解析成功报条数，被拒报错误文案。
fn parse_text(text : String) -> String {
  let parsed = parse_uc_result(text) catch {
    err => return "refused:" + err.text()
  }
  "ok:" + parsed.hosts.length().to_string()
}

///|
/// 只为证明"derive 读不进 JSON 数字"这条形状事实而存在的结构：本包的
/// `UcHostEntry` 里没有任何数字字段，就是这个事实的结果。
struct NumberProbe {
  ttl : Int64?
} derive(@json.FromJson)

///|
pub extend NumberProbe with @json.FromJson::{from_json}

///|
/// 数字档的读数：成功报值，被拒报固定文案，非 JSON 再单独一档。
fn decode_number(text : String) -> String {
  let value = @json.parse(text) catch { _ => return "not-json" }
  let parsed : NumberProbe = @json.from_json(value) catch {
    _ => return "refused"
  }
  "ok:" + parsed.ttl.unwrap_or(-1L).to_string()
}

///|
test "区域探测 #0 数字档：derive 读不进 JSON 数字，未声明的多余键则忽略" {
  assert_eq(parse_text("{\"hosts\":[{\"region\":\"z9\"}]}"), "ok:1")
  // 2026-10-17 实测：结构里一声明数字字段，官方那份带 `"ttl":86400` 的响应就读不出来
  assert_eq(decode_number("{\"ttl\":86400}"), "refused")
  // 所以数值字段一律不靠 derive，从原文用自写扫描器读（本样例里第一个 `ttl` 是区域级的）
  assert_eq(@error.json_int_field("{\"ttl\":86400}", "ttl"), Some(86400L))
  assert_eq(@error.json_int_field(uc_sample(), "ttl"), Some(86400L))
  assert_eq(@error.json_int_field("{\"ttl\":\"x\"}", "ttl"), None)
  // 官方响应里那些我们不声明的键：derive 不拦
  assert_eq(
    parse_text("{\"hosts\":[{\"region\":\"z9\",\"uc_src\":1}]}"),
    "ok:1",
  )
  assert_eq(parse_text("{\"hosts\":[{\"region\":\"z9\"}],\"ttl\":1}"), "ok:1")
}

///|
test "区域探测 #1 认官方 v4 响应形状：区域号与三组主机" {
  let parsed = parse_uc_result(uc_sample()) catch {
    err => fail("parse: " + err.text())
  }
  assert_eq(parsed.hosts.length(), 1)
  let entry = parsed.hosts[0]
  assert_eq(entry.region, "z9")
  let region = region_from_probe(entry, @config.default_uc_hosts())
  assert_eq(region.region_id, "z9")
  // `up.domains` 两条都要带回来：加速与源站是同一组读数里的两档
  assert_eq(region.acc_up_hosts, [
    "upload-sample.qiniup.com", "up-sample.qiniup.com",
  ])
  assert_eq(region.rs_host, "rs-sample.qbox.me")
  assert_eq(region.rsf_host, "rsf-sample.qbox.me")
  assert_eq(region.iovip_host, "iovip-sample.qbox.me")
  assert_eq(region.api_host, "api-sample.qiniu.com")
  assert_eq(region.uc_hosts, @config.default_uc_hosts())
}

///|
test "区域探测 #2 缺项回落：只给区域号时其余按命名规则推" {
  let parsed = parse_uc_result("{\"hosts\":[{\"region\":\"z1\"}]}") catch {
    err => fail("parse: " + err.text())
  }
  let region = region_from_probe(parsed.hosts[0], @config.default_uc_hosts())
  assert_eq(region.acc_up_hosts, ["upload-z1.qiniup.com"])
  assert_eq(region.src_up_hosts, ["up-z1.qiniup.com"])
  assert_eq(region.rs_host, "rs-z1.qiniuapi.com")
}

///|
test "区域探测 #3 空 hosts 给读数，坏 JSON 响亮拒绝" {
  assert_eq(parse_text("{\"hosts\":[]}"), "ok:0")
  assert_eq(
    parse_text("not json at all"),
    "refused:kodo bad param(-4): region query body is not json",
  )
}
