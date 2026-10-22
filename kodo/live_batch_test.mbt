///|
// `POST /batch` 真桶档：两条删除 + 一条 stat 缺键，逐项 code 要分开读。
// 缺 KODO_* 时整段 SKIP；写只落本轮自命名前缀，测完删净。

///|
fn batch_skip() -> Unit {
  println("SKIP live Kodo batch checks, KODO_* not supplied")
  println("SKIP IS NOT A PASS: Kodo batch was not measured by this run.")
}

///|
async test "真桶·batch 批删与逐项 code：自命名前缀，测完删净" {
  match read_kodo_live() {
    None => batch_skip()
    Some(live) => {
      let client = mp_client(live) catch { err => fail("setup: " + err.text()) }
      let stamp = @date.now_millis().to_string()
      let day = stamp[0:8].to_owned()
      let k1 = "moonfs-kodo-" + day + "/" + stamp + "-batch-a.txt"
      let k2 = "moonfs-kodo-" + day + "/" + stamp + "-batch-b.txt"
      let outcome = try {
        let _ = client.put_bytes(k1, @utf8.encode("batch-a")) catch {
          err => fail("put a: " + err.text())
        }
        let _ = client.put_bytes(k2, @utf8.encode("batch-b")) catch {
          err => fail("put b: " + err.text())
        }
        let result = client.batch([
          @kodo.BatchOp::Delete(k1),
          @kodo.BatchOp::Delete(k2),
          @kodo.BatchOp::Stat(k1),
        ]) catch {
          err => fail("batch: " + err.text())
        }
        if result.items.length() != 3 {
          fail("batch items " + result.items.length().to_string())
        }
        if result.items[0].code != Some(200L) ||
          result.items[1].code != Some(200L) {
          fail("batch delete codes: " + result.body)
        }
        if result.items[2].code != Some(612L) {
          fail("batch stat missing code: " + result.body)
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      let _ = client.delete(k1) catch {
        err => {
          println("cleanup a: " + err.text())
          false
        }
      }
      let _ = client.delete(k2) catch {
        err => {
          println("cleanup b: " + err.text())
          false
        }
      }
      println("kodo extra batch outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}
