///|
// Kodo 探针（阶段 D 卡 §3 承重前提 1 的四步 + §6 KD2 的区域探测读数）。
//
// 顺序：先用真凭据跑一次**区域探测**（`GET {uc}/v4/query`），拿探测回来的主机建
// Config——卡 §3-2 要的就是"以探测结果为准并打读数"，不是把某台主机名写死；
// 然后签令牌 → 表单写真桶 → `stat` 读回 → `delete` 删净，最后再 `stat` 一次听"不存在"。
//
// 读数全部来自环境：`KODO_AK` / `KODO_SK` / `KODO_BUCKET`。凭据只从环境读，
// 不进任何一行输出；写入只落在本轮自命名前缀 `moonfs-kodo-<时间戳>/` 下，
// 对象一枚、几十字节，桶内其余对象一律不碰；不建桶也不删桶（owner 拍板）。
//
// 这四步跑的是**要发布的代码**（`auth` 签令牌、`kodo` 发请求），不是另写一套探针。

///|
struct KodoLive {
  ak : String
  sk : String
  bucket : String
}

///|
fn env_of(name : String) -> String {
  @env.get_env_var(name).unwrap_or("")
}

///|
/// 缺任何一项都整段跳过；跳过必须响亮。
fn read_kodo_live() -> KodoLive? {
  let names : Array[String] = ["KODO_AK", "KODO_SK", "KODO_BUCKET"]
  let missing : Array[String] = []
  for name in names {
    if env_of(name).is_empty() {
      missing.push(name)
    }
  }
  if missing.length() > 0 {
    println("SKIP live Kodo probe, environment not supplied")
    println("missing: " + missing.join(", "))
    println(
      "SKIP IS NOT A PASS: the native Kodo link was not measured by this run.",
    )
    None
  } else {
    Some(KodoLive::{
      ak: env_of("KODO_AK"),
      sk: env_of("KODO_SK"),
      bucket: env_of("KODO_BUCKET"),
    })
  }
}

///|
/// 探针写的对象只有这一份文本，尺寸与内容都由它定义。
fn probe_text() -> String {
  "hello from moon-kodo probe (stage D, premise 1)"
}

///|
/// `stat` 的一行读数（成功档）。被拒的那档由调用方就地接成同一个 `String` 再断言——
/// `expr catch {}` 要求两臂同型，成功档若是 `StatResult` 就接不住；
/// `try { } catch { }` 的块式写法在这个工具链上会把 raise 类型留成未解析变量。
async fn stat_reading(
  client : @kodo.Client,
  key : String,
) -> String raise @error.KodoError {
  let row = client.stat(key)
  let size = row.fsize.unwrap_or(-1L).to_string()
  "fsize=" + size + " mime=" + row.mime_type.unwrap_or("<none>")
}

///|
/// 探针跑完的读数。断言一律留到用例块里做：`assert_eq` / `fail` 抛的是 `Error`，
/// 在声明 `raise @error.KodoError` 的函数里接不住。
struct ProbeReading {
  key : String
  echoed : String
  region : String
  up_origin : String
  rs_origin : String
  first_stat : String
  deleted : Bool
  gone_stat : String
}

///|
async fn run_probe(live : KodoLive) -> ProbeReading raise @error.KodoError {
  let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
  let auth = @auth.Auth::new(live.ak, live.sk)

  // KD2：区域探测。三台 uc 主机挨个试，这里打的是"探到哪台 uc、探回哪些主机"
  let probe = @kodo.query_region(transport, live.ak, live.bucket)
  let region = probe.region
  let ttl = probe.ttl.unwrap_or(-1L).to_string()
  println(
    "region=" + region.region_id + " via uc=" + probe.uc_host + " ttl=" + ttl,
  )
  println(
    "probed up=" + region.acc_up_hosts.join(",") + " rs=" + region.rs_host,
  )
  println("probed iovip=" + region.iovip_host + " rsf=" + region.rsf_host)

  let cfg = @config.Config::new(region, use_https=true)
  let client = @kodo.Client::new(transport, auth, cfg, live.bucket)

  // 自命名前缀：一天两轮也不撞车
  let stamp = @date.now_millis().to_string()
  let day = stamp[0:8].to_owned()
  let key = "moonfs-kodo-" + day + "/" + stamp + "-probe.txt"
  let payload = @utf8.encode(probe_text())

  let upload = client.put_bytes(key, payload)
  let echoed = upload.key.unwrap_or("<none>")
  let hash_length = upload.hash.unwrap_or("").length().to_string()
  println("upload echoed key=" + echoed)
  println("upload hash length=" + hash_length)

  let first = stat_reading(client, key)
  println("stat " + first)

  let deleted = client.delete(key)
  println("delete returned=" + deleted.to_string())

  // 删净不只看 delete 的那句布尔：再 stat 一次，要听到服务说"不存在"
  let gone = stat_reading(client, key) catch { err => "raised:" + err.text() }
  println("stat after delete=" + gone)
  ProbeReading::{
    key,
    echoed,
    region: region.region_id,
    up_origin: cfg.up_origin(accelerate=true),
    rs_origin: cfg.rs_origin(),
    first_stat: first,
    deleted,
    gone_stat: gone,
  }
}

///|
async test "探针：区域探测 → 令牌 → 表单写入 → stat 读回 → delete 删净" {
  match read_kodo_live() {
    None => ()
    Some(live) => {
      let payload = @utf8.encode(probe_text())
      let reading = run_probe(live) catch {
        err => fail("kodo probe: " + err.text())
      }
      // 探测真回到东西：区域号非空、两台主机都是带 scheme 的完整 origin
      assert_eq(reading.region.is_empty(), false)
      assert_eq(reading.up_origin.has_prefix("https://"), true)
      assert_eq(reading.up_origin.length() > 8, true)
      assert_eq(reading.rs_origin.has_prefix("https://"), true)
      assert_eq(reading.echoed, reading.key)
      let expected = "fsize=" + payload.length().to_string()
      assert_eq(reading.first_stat.has_prefix(expected), true)
      assert_eq(reading.deleted, true)
      assert_eq(reading.gone_stat.has_prefix("raised:kodo service(612)"), true)
    }
  }
}
