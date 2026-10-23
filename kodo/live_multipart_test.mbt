///|
// 真桶上的 V2 分块腿（阶段 D 卡 §4 D2 的剩余两格：分块第二代 + KD3b 的 `check_crc`）。
//
// 跑的是要发布的代码：`begin_multipart` → 逐片 `upload_part` → `list_parts` →
// `complete_multipart` → `stat` → `delete`，外加一条 `abort_multipart` 的收尾腿。
// 尺寸取 **1 MiB + 1 字节**（`min_block_size` 的下一格）：前一片满 1MB、末片 1 字节，
// 这是能同时压到"满片"与"末片不限长"两档的最小形状。
//
// 两块摘要基准来自独立第二实现（python `hashlib.md5`，工装 `multipart_vectors.py`），
// 不是拿本包的输出当标准：
// - 满片（16 字节表重复 65536 次）＝ `14d785daab3823736c981ca82a750c98`
// - 末片那 1 字节（`"0"`）＝ `cfcd208495d565ef66e7dff9f98764da`
//
// 写入只落本轮自命名前缀 `moonfs-kodo-<日期>/`，对象测后即删，桶内其余对象一律不碰；
// 不建桶也不删桶。凭据只从环境读，不进任何一行输出。

///|
fn mp_part1_md5() -> String {
  "14d785daab3823736c981ca82a750c98"
}

///|
fn mp_part2_md5() -> String {
  "cfcd208495d565ef66e7dff9f98764da"
}

///|
/// 1 MiB + 1 字节的确定性载荷。
fn mp_payload() -> Bytes {
  let seed = @utf8.encode("0123456789abcdef")
  let merged : Array[Byte] = []
  for _ in 0..<65537 {
    merged.append(seed.to_array())
  }
  Bytes::from_array(merged)[0:1048577].to_owned()
}

///|
/// 探测回来的区域建客户端（与表单探针同一姿势：不把主机名写死）。
async fn mp_client(live : KodoLive) -> @kodo.Client raise @error.KodoError {
  let transport : &@transport.Transport = @transport.AsyncHttpTransport::new()
  let auth = @auth.Auth::new(live.ak, live.sk)
  let probe = @kodo.query_region(transport, live.ak, live.bucket)
  println(
    "multipart region=" + probe.region.region_id + " via uc=" + probe.uc_host,
  )
  let cfg = @config.Config::new(probe.region, use_https=true)
  @kodo.Client::new(transport, auth, cfg, live.bucket)
}

///|
/// 一次 `stat` 成功档的读数。被拒那一档由调用方就地接成同一个 `String`——
/// 在本函数里 `catch` 会把 raise 类型撑成 `Error`，接回 `raise @error.KodoError` 的调用点就崩。
async fn mp_stat(
  client : @kodo.Client,
  key : String,
) -> String raise @error.KodoError {
  let row = client.stat(key)
  let size = row.fsize.unwrap_or(-1L).to_string()
  let mime = row.mime_type.unwrap_or("<none>")
  "fsize=" + size + " mime=" + mime
}

///|
/// 篡改档：拿一个错的期望摘要去核这一片。判据响不响由调用方读数——
/// 它响了就该是 `refused:`，没响就是 `accepted:`，两种形状都接成同一个 `String`。
async fn mp_tampered(
  client : @kodo.Client,
  session : @kodo.UploadSession,
  head : Bytes,
) -> String raise @error.KodoError {
  let wrong = "00000000000000000000000000000000"
  let accepted = client.upload_part(
    session,
    1,
    head,
    check_crc=true,
    expect_md5=Some(wrong),
  )
  "accepted: server md5=" + accepted.md5.unwrap_or("<none>")
}

///|
/// 分块主腿的读数。断言一律留到用例块里做：`assert_eq` / `fail` 抛的是 `Error`，
/// 在声明 `raise @error.KodoError` 的函数里接不住。
struct MpReading {
  key : String
  upload_id_length : Int32
  expire_at : String
  tampered : String
  part1_md5 : String
  part1_etag_length : Int32
  part2_md5 : String
  part2_etag_length : Int32
  listed : Int32
  listed_size1 : String
  listed_size2 : String
  listed_etag1 : String
  next_marker : String
  truncated : String
  complete_key : String
  complete_hash_length : Int32
  stat_after : String
  deleted : Bool
  gone_stat : String
}

///|
fn size_text(value : Int64?) -> String {
  value.unwrap_or(-1L).to_string()
}

///|
fn missing_part() -> @kodo.PartInfo {
  @kodo.PartInfo::{
    part_number: -1,
    etag: "<none>",
    size: None,
    put_time: None,
  }
}

///|
async fn run_multipart(live : KodoLive) -> MpReading raise @error.KodoError {
  let client = mp_client(live)
  let stamp = @date.now_millis().to_string()
  let day = stamp[0:8].to_owned()
  let key = "moonfs-kodo-" + day + "/" + stamp + "-multipart.bin"
  let payload = mp_payload()
  let head = payload[0:1048576].to_owned()
  let tail = payload[1048576:1048577].to_owned()

  let session = client.begin_multipart(key)
  // init 之后立刻 list：零片才算"会话里没有幽灵分片"
  let page_before = client.list_parts(session)
  let before_count = page_before.parts.length().to_string()
  println("list right after init: " + before_count + " parts")
  let tampered = mp_tampered(client, session, head) catch {
    err => "refused:" + err.text()
  }

  let one = client.upload_part(session, 1, head, check_crc=true)
  let two = client.upload_part(session, 2, tail, check_crc=true)
  let page = client.list_parts(session)
  let first = if page.parts.length() > 0 {
    page.parts[0]
  } else {
    missing_part()
  }
  let second = if page.parts.length() > 1 {
    page.parts[1]
  } else {
    missing_part()
  }

  // 乱序传入：先 2 后 1。合并前必须按片号排好，否则拼出来的对象是倒的。
  let shuffled = [
    @kodo.PartInfo::{
      part_number: 2,
      etag: two.etag,
      size: None,
      put_time: None,
    },
    @kodo.PartInfo::{
      part_number: 1,
      etag: one.etag,
      size: None,
      put_time: None,
    },
  ]
  let done = client.complete_multipart(
    session,
    shuffled,
    mime_type=Some("application/octet-stream"),
  )
  let after = mp_stat(client, key) catch { err => "raised:" + err.text() }
  let deleted = client.delete(key)
  let gone = mp_stat(client, key) catch { err => "raised:" + err.text() }

  MpReading::{
    key,
    upload_id_length: session.upload_id.length(),
    expire_at: size_text(session.expire_at),
    tampered,
    part1_md5: one.md5.unwrap_or("<none>"),
    part1_etag_length: one.etag.length(),
    part2_md5: two.md5.unwrap_or("<none>"),
    part2_etag_length: two.etag.length(),
    listed: page.parts.length(),
    listed_size1: size_text(first.size),
    listed_size2: size_text(second.size),
    listed_etag1: first.etag,
    next_marker: page.next_marker.unwrap_or(-1).to_string(),
    truncated: page.truncated.to_string(),
    complete_key: done.key.unwrap_or("<none>"),
    complete_hash_length: done.hash.unwrap_or("").length(),
    stat_after: after,
    deleted,
    gone_stat: gone,
  }
}

///|
async test "真桶 V2 分块：init → 篡改档响 → 两片 → list → 乱序合并 → stat → delete" {
  match read_kodo_live() {
    None => ()
    Some(live) => {
      let payload = mp_payload()
      // 工装先自证：尺寸错了就别去怪服务端
      assert_eq(payload.length(), 1048577)
      let reading = run_multipart(live) catch {
        err => fail("kodo multipart: " + err.text())
      }
      println("uploadId length=" + reading.upload_id_length.to_string())
      println("expireAt=" + reading.expire_at)
      println("tampered leg=" + reading.tampered)
      let etag_lengths = reading.part1_etag_length.to_string() +
        "/" +
        reading.part2_etag_length.to_string()
      println("part etag lengths=" + etag_lengths)
      println("list partNumberMarker=" + reading.next_marker)
      println(
        "complete hash length=" + reading.complete_hash_length.to_string(),
      )
      println("stat after complete=" + reading.stat_after)
      assert_eq(reading.upload_id_length > 0, true)
      assert_eq(reading.expire_at.has_prefix("-"), false)
      // 篡改档必须响，且响在合并之前
      assert_eq(reading.tampered.has_prefix("refused:kodo bad response"), true)
      assert_eq(
        reading.tampered.has_prefix(
          "refused:kodo bad response: block's md5 is not match at part 1",
        ),
        true,
      )
      // 服务端回的块摘要 == 独立实现的常数
      assert_eq(reading.part1_md5, mp_part1_md5())
      assert_eq(reading.part2_md5, mp_part2_md5())
      assert_eq(reading.part1_etag_length > 0, true)
      assert_eq(reading.part2_etag_length > 0, true)
      assert_eq(reading.listed, 2)
      assert_eq(reading.listed_size1, "1048576")
      assert_eq(reading.listed_size2, "1")
      assert_eq(reading.listed_etag1.is_empty(), false)
      assert_eq(reading.truncated, "false")
      assert_eq(reading.complete_key, reading.key)
      assert_eq(reading.complete_hash_length > 0, true)
      assert_eq(reading.stat_after.has_prefix("fsize=1048577"), true)
      assert_eq(reading.deleted, true)
      assert_eq(reading.gone_stat.has_prefix("raised:kodo service(612)"), true)
    }
  }
}

///|
/// 收尾腿：`abort` 之后既没有对象也不该留分片；高层入口 `put_bytes_multipart` 另建一枚。
async test "真桶 V2 分块：abort 丢掉会话，高层入口按块切两片并合回原尺寸" {
  match read_kodo_live() {
    None => ()
    Some(live) => {
      let client = mp_client(live) catch {
        err => fail("kodo multipart setup: " + err.text())
      }
      let stamp = @date.now_millis().to_string()
      let day = stamp[0:8].to_owned()

      // ① abort：传一片就放弃，对象绝不能出现
      let abort_key = "moonfs-kodo-" + day + "/" + stamp + "-abort.bin"
      let session = client.begin_multipart(abort_key) catch {
        err => fail("abort leg init: " + err.text())
      }
      let part = client.upload_part(
        session,
        1,
        mp_payload()[0:1048576].to_owned(),
      ) catch {
        err => fail("abort leg part: " + err.text())
      }
      println("abort leg part1 etag length=" + part.etag.length().to_string())
      client.abort_multipart(session) catch {
        err => fail("abort leg abort: " + err.text())
      }
      let after_abort = mp_stat(client, abort_key) catch {
        err => "raised:" + err.text()
      }
      println("stat after abort=" + after_abort)
      assert_eq(after_abort.has_prefix("raised:kodo service(612)"), true)

      // ② 高层入口：split_blocks 把 1MiB+1 切成两片，check_crc 全程开着
      let high_key = "moonfs-kodo-" + day + "/" + stamp + "-multipart-high.bin"
      let seen : Array[Int32] = []
      let done = client.put_bytes_multipart(
        high_key,
        mp_payload(),
        block_size=1048576,
        check_crc=true,
        progress=Some(fn(sent, _total) { seen.push(sent) }),
      ) catch {
        err => fail("put_bytes_multipart: " + err.text())
      }
      println("high-level echoed key=" + done.key.unwrap_or("<none>"))
      let stat_high = mp_stat(client, high_key) catch {
        err => "raised:" + err.text()
      }
      println("stat high-level=" + stat_high)
      assert_eq(done.key.unwrap_or("<none>"), high_key)
      assert_eq(stat_high.has_prefix("fsize=1048577"), true)
      let deleted = client.delete(high_key) catch {
        err => fail("high-level delete: " + err.text())
      }
      assert_eq(deleted, true)
      let gone_high = mp_stat(client, high_key) catch {
        err => "raised:" + err.text()
      }
      assert_eq(gone_high.has_prefix("raised:kodo service(612)"), true)
    }
  }
}

///|
async test "真桶·TransferManager：超阈值自动走分片" {
  match read_kodo_live() {
    None => res_skip()
    Some(live) => {
      let client = mp_client(live) catch {
        err => fail("tm setup: " + err.text())
      }
      let key = "moonfs-kodo-tm-" + @date.now_millis().to_string() + "/a.bin"
      let data = mp_payload()
      let manager = @kodo.TransferManager::new(
        client,
        live.bucket,
        block_size=1048576,
        threshold=1048576,
      )
      let outcome = try {
        let out = manager.upload(key, data) catch {
          err => fail("tm upload: " + err.text())
        }
        if out.key.unwrap_or("") != key {
          fail("tm key mismatch: " + out.key.unwrap_or("<none>"))
        }
        let info = client.stat(key) catch {
          err => fail("tm stat: " + err.text())
        }
        assert_eq(info.fsize, Some(data.length().to_int64()))
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      let _ = client.delete(key) catch {
        err => {
          println("tm cleanup: " + err.text())
          false
        }
      }
      println("kodo tm outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}

///|
async test "真桶·TransferManager 下载与跨桶搬运" {
  match read_kodo_live() {
    None => res_skip()
    Some(live) => {
      let client = mp_client(live) catch {
        err => fail("tm2 setup: " + err.text())
      }
      let tag = "moonfs-kodo-tm2-" + @date.now_millis().to_string()
      let src = tag + "/src.bin"
      let dst = tag + "/dst.bin"
      let data = @utf8.encode("kodo-transfer-manager-payload")
      let manager = @kodo.TransferManager::new(client, live.bucket)
      let outcome = try {
        let _ = client.put_bytes(src, data) catch {
          err => fail("tm2 seed: " + err.text())
        }
        // CI 里绑定的 CDN 域名常解析不到；只有显式给 KODO_DOMAIN 才跑下载腿。
        let domain = env_of("KODO_DOMAIN")
        if domain.is_empty() {
          println("kodo tm2 download skipped: KODO_DOMAIN not supplied")
        } else {
          let downloaded = manager.download(src, base_url=domain) catch {
            err => fail("tm2 download: " + err.text())
          }
          assert_eq(downloaded.length(), data.length())
        }
        manager.copy_to(src, live.bucket, dst) catch {
          err => fail("tm2 copy: " + err.text())
        }
        let info = client.stat(dst) catch {
          err => fail("tm2 stat: " + err.text())
        }
        assert_eq(info.fsize, Some(data.length().to_int64()))
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      for key in [src, dst] {
        let _ = client.delete(key) catch {
          err => {
            println("tm2 cleanup: " + err.text())
            false
          }
        }
      }
      println("kodo tm2 outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}
