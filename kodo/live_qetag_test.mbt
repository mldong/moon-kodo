///|
// qetag 真桶对拍：本地算出的 qetag 必须等于服务端 stat.hash。
// 缺 KODO_* 时整段 SKIP；对象测完删净。

///|
async test "真桶·qetag 与 stat.hash 对拍" {
  match read_kodo_live() {
    None => {
      println("SKIP live Kodo qetag check, KODO_* not supplied")
      println("SKIP IS NOT A PASS: qetag was not measured by this run.")
    }
    Some(live) => {
      let client = mp_client(live) catch { err => fail("setup: " + err.text()) }
      let key = "moonfs-kodo-qetag-" + @date.now_millis().to_string() + ".txt"
      let payload = @utf8.encode("qetag probe")
      let outcome = try {
        let _ = client.put_bytes(key, payload) catch {
          err => fail("put: " + err.text())
        }
        let stat = client.stat(key) catch { err => fail("stat: " + err.text()) }
        let expected = @kodo.qetag(payload)
        let got = stat.hash.unwrap_or("<none>")
        println("kodo qetag local=" + expected + " stat.hash=" + got)
        if got != expected {
          fail("qetag mismatch: " + got + " != " + expected)
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      let _ = client.delete(key) catch {
        err => {
          println("cleanup: " + err.text())
          false
        }
      }
      println("kodo extra qetag outcome=" + outcome)
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}
