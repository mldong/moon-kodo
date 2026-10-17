///|
// 真桶上的对象族腿（阶段 D 卡 §4 D3 的剩余四件＋§6 KD4）。
//
// 判据本体：
// - `copy` 之后**源仍在**、目标同尺寸；
// - `move_object` 之后**目标在、源消失**（612）；
// - 缺源复制响亮报服务端那一档（不吞成"成功"）；
// - 目标位已有同名对象时 `force=false` 那一档要响，`force=true` 才覆盖；
// - `change_mime` 改完要能从 `stat` 读回新 mime。
//
// 写入只落本轮自命名前缀，对象个位数、每个几十字节，测完删净。凭据只从环境读、不打印。

///|
fn obj_text() -> String {
  "moon-kodo object family probe (stage D3)"
}

///|
async fn copy_text(
  client : @kodo.Client,
  from : String,
  to : String,
  force~ : Bool = false,
) -> String raise @error.KodoError {
  client.copy(from, to, force~)
  "ok"
}

///|
async fn move_text(
  client : @kodo.Client,
  from : String,
  to : String,
  force~ : Bool = false,
) -> String raise @error.KodoError {
  client.move_object(from, to, force~)
  "ok"
}

///|
async fn chgm_text(
  client : @kodo.Client,
  key : String,
  mime : String,
) -> String raise @error.KodoError {
  client.change_mime(key, mime)
  "ok"
}

///|
async test "真桶对象族：copy 源仍在 / move 源消失 / 缺源与占位各响一档 / chgm 读回新 mime" {
  match read_kodo_live() {
    None => ()
    Some(live) => {
      let client = mp_client(live) catch {
        err => fail("kodo object setup: " + err.text())
      }
      let stamp = @date.now_millis().to_string()
      let day = stamp[0:8].to_owned()
      let root = "moonfs-kodo-" + day + "/"
      let src = root + stamp + "-obj-src.txt"
      let dst = root + stamp + "-obj-dst.txt"
      let moved = root + stamp + "-obj-moved.txt"
      let payload = @utf8.encode(obj_text())

      let put = client.put_bytes(src, payload) catch {
        err => fail("object leg seed upload: " + err.text())
      }
      assert_eq(put.key.unwrap_or("<none>"), src)
      let src_size = "fsize=" + payload.length().to_string()

      let copied = copy_text(client, src, dst) catch {
        err => fail("copy: " + err.text())
      }
      println("copy=" + copied)
      let stat_src = mp_stat(client, src) catch {
        err => "raised:" + err.text()
      }
      let stat_dst = mp_stat(client, dst) catch {
        err => "raised:" + err.text()
      }
      println("stat src after copy=" + stat_src)
      println("stat dst after copy=" + stat_dst)
      // copy 不搬源：两边都在、尺寸一致
      assert_eq(stat_src.has_prefix(src_size), true)
      assert_eq(stat_dst.has_prefix(src_size), true)

      // 目标位已占：force=false 要响，force=true 才覆盖
      let occupied = copy_text(client, src, dst) catch {
        err => "refused:" + err.text()
      }
      println("copy force=false 撞同名=" + occupied)
      // 现读：目标位已有同名对象时 Kodo 回 614 `file exists`
      assert_eq(
        occupied.has_prefix("refused:kodo service(614): file exists"),
        true,
      )
      let forced = copy_text(client, src, dst, force=true) catch {
        err => "refused:" + err.text()
      }
      println("copy force=true=" + forced)
      assert_eq(forced, "ok")

      // 缺源复制：响亮，不吞
      let missing = copy_text(client, root + stamp + "-no-such-key.txt", dst) catch {
        err => "refused:" + err.text()
      }
      println("copy 缺源=" + missing)
      assert_eq(missing.has_prefix("refused:kodo service(612)"), true)

      let moved_ok = move_text(client, dst, moved) catch {
        err => fail("move: " + err.text())
      }
      println("move=" + moved_ok)
      let stat_gone = mp_stat(client, dst) catch {
        err => "raised:" + err.text()
      }
      let stat_moved = mp_stat(client, moved) catch {
        err => "raised:" + err.text()
      }
      println("stat 源（move 之后）=" + stat_gone)
      println("stat 目标（move 之后）=" + stat_moved)
      assert_eq(stat_gone.has_prefix("raised:kodo service(612)"), true)
      assert_eq(stat_moved.has_prefix(src_size), true)

      let want_mime = "application/x-moon-kodo-probe"
      let changed = chgm_text(client, moved, want_mime) catch {
        err => fail("change_mime: " + err.text())
      }
      println("chgm=" + changed)
      let after_mime = mp_stat(client, moved) catch {
        err => "raised:" + err.text()
      }
      println("stat after chgm=" + after_mime)
      assert_eq(after_mime.has_prefix(src_size + " mime=" + want_mime), true)

      let del_src = client.delete(src) catch {
        err => fail("delete src: " + err.text())
      }
      let del_moved = client.delete(moved) catch {
        err => fail("delete moved: " + err.text())
      }
      assert_eq(del_src, true)
      assert_eq(del_moved, true)
    }
  }
}

///|
async test "真桶列举：单层不混嵌套键、分页 marker；fetch 把公网小文件抓进桶" {
  match read_kodo_live() {
    None => ()
    Some(live) => {
      let client = mp_client(live) catch {
        err => fail("kodo list setup: " + err.text())
      }
      let stamp = @date.now_millis().to_string()
      let day = stamp[0:8].to_owned()
      let dir = "moonfs-kodo-" + day + "/" + stamp + "-list/"
      let flat = dir + "a.txt"
      let nested = dir + "inner/b.txt"
      let payload = @utf8.encode(obj_text())
      let _ = client.put_bytes(flat, payload) catch {
        err => fail("list seed flat: " + err.text())
      }
      let _ = client.put_bytes(nested, payload) catch {
        err => fail("list seed nested: " + err.text())
      }

      let all = client.list_files(prefix=Some(dir), limit=Some(10)) catch {
        err => fail("list all: " + err.text())
      }
      let keys : Array[String] = []
      for item in all.items {
        keys.push(item.key)
      }
      let flat_line = "不带 delimiter 列出=" +
        keys.join(",") +
        " 前缀组=" +
        all.common_prefixes.join(",") +
        " is_eof=" +
        all.is_eof.to_string()
      println(flat_line)
      // 不带分隔符：嵌套键也在 items 里（这一档正是"单层"判据的对照）
      assert_eq(all.items.length(), 2)

      let layered = client.list_files(
        prefix=Some(dir),
        delimiter=Some("/"),
        limit=Some(10),
      ) catch {
        err => fail("list layered: " + err.text())
      }
      let layer_keys : Array[String] = []
      for item in layered.items {
        layer_keys.push(item.key)
      }
      let layered_line = "带 delimiter=/ 列出=" +
        layer_keys.join(",") +
        " 前缀组=" +
        layered.common_prefixes.join(",")
      println(layered_line)
      assert_eq(layer_keys.join(","), flat)
      assert_eq(layered.common_prefixes.join(","), dir + "inner/")
      let first = layered.items[0]
      assert_eq(first.fsize, Some(payload.length().to_int64()))
      assert_eq(first.key, flat)
      // putTime 是 17 位微秒：读成 Int 会截，这里要拿到非零正数
      assert_eq(first.put_time.unwrap_or(0L) > 0L, true)

      let page = client.list_files(prefix=Some(dir), limit=Some(1)) catch {
        err => fail("list page: " + err.text())
      }
      let page_line = "分页第一页条数=" +
        page.items.length().to_string() +
        " marker 有无=" +
        (page.marker is Some(_)).to_string() +
        " is_eof=" +
        page.is_eof.to_string()
      println(page_line)
      assert_eq(page.items.length(), 1)
      let marker = page.marker.unwrap_or("")
      assert_eq(marker.is_empty(), false)
      let page2 = client.list_files(
        prefix=Some(dir),
        marker=Some(marker),
        limit=Some(1),
      ) catch {
        err => fail("list page2: " + err.text())
      }
      println("第二页条数=" + page2.items.length().to_string())
      assert_eq(page2.items.length(), 1)
      assert_eq(page2.items[0].key != page.items[0].key, true)

      // fetch：抓自家官网的 favicon（1137 字节，公网可达，2026-10-17 现读 200）
      let fetched_key = "moonfs-kodo-" + day + "/" + stamp + "-fetched.ico"
      let got = client.fetch("https://mldong.com/favicon.ico", fetched_key) catch {
        err => fail("fetch: " + err.text())
      }
      let fetched_line = "fetch echoed key=" +
        got.key.unwrap_or("<none>") +
        " fsize=" +
        got.fsize.unwrap_or(-1L).to_string() +
        " mime=" +
        got.mime_type.unwrap_or("<none>")
      println(fetched_line)
      assert_eq(got.key.unwrap_or("<none>"), fetched_key)
      assert_eq(got.fsize.unwrap_or(-1L) > 0L, true)
      let fetched_stat = mp_stat(client, fetched_key) catch {
        err => "raised:" + err.text()
      }
      println("stat 抓回的对象=" + fetched_stat)
      assert_eq(
        fetched_stat.has_prefix("fsize=" + got.fsize.unwrap_or(-1L).to_string()),
        true,
      )

      let _ = client.delete(flat) catch {
        err => fail("delete flat: " + err.text())
      }
      let _ = client.delete(nested) catch {
        err => fail("delete nested: " + err.text())
      }
      let _ = client.delete(fetched_key) catch {
        err => fail("delete fetched: " + err.text())
      }
      let left = client.list_files(prefix=Some(dir), limit=Some(10)) catch {
        err => fail("list after cleanup: " + err.text())
      }
      println("清场后该前缀下条数=" + left.items.length().to_string())
      assert_eq(left.items.length(), 0)
    }
  }
}
