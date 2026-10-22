///|
// 资源管理四件的真桶档：缺 KODO_* 时整段 SKIP；写只落本轮自命名前缀，测完删净。
// 断言只到“服务端接下了这一发”，不猜存储类型/状态的读回形状（stat 不回这两格）。

///|
fn res_skip() -> Unit {
  println("SKIP live Kodo resource checks, KODO_* not supplied")
  println(
    "SKIP IS NOT A PASS: new Kodo resource methods were not measured by this run.",
  )
}

///|
fn has_bucket(names : Array[String], want : String) -> Bool {
  for name in names {
    if name == want {
      return true
    }
  }
  false
}

///|
async test "真桶·域名列表：UC QBox 签名与 JSON 数组解析" {
  match read_kodo_live() {
    None => res_skip()
    Some(live) => {
      let client = mp_client(live) catch { err => fail("setup: " + err.text()) }
      let domains = client.domains() catch {
        err => fail("domains: " + err.text())
      }
      println(
        "kodo domains count=" +
        domains.names.length().to_string() +
        " body=" +
        domains.body,
      )
      if domains.body.trim() != "[]" && domains.names.length() == 0 {
        fail("domains array parse failed: " + domains.body)
      }
    }
  }
}

///|
async test "真桶·桶配置读取：bucketInfo/CORS/生命周期/配额/事件" {
  match read_kodo_live() {
    None => res_skip()
    Some(live) => {
      let client = mp_client(live) catch { err => fail("setup: " + err.text()) }
      let info = client.bucket_info() catch {
        err => fail("bucket_info: " + err.text())
      }
      let cors = client.cors_rules() catch {
        err => fail("cors_rules: " + err.text())
      }
      let lifecycle = client.lifecycle_rules() catch {
        err => fail("lifecycle_rules: " + err.text())
      }
      let quota = client.bucket_quota() catch {
        err => fail("bucket_quota: " + err.text())
      }
      let events = client.event_rules() catch {
        err => fail("event_rules: " + err.text())
      }
      let first_rule = if lifecycle.rules.length() > 0 {
        let rule = lifecycle.rules[0]
        rule.name + "/" + rule.prefix + "/" + rule.delete_after_days.to_string()
      } else {
        "<none>"
      }
      println(
        "kodo bucket config info_region=" +
        info.region.unwrap_or("<none>") +
        " private=" +
        info.private_flag.unwrap_or(-1L).to_string() +
        " cors=" +
        cors.rules.length().to_string() +
        " lifecycle=" +
        lifecycle.rules.length().to_string() +
        " first_rule=" +
        first_rule +
        " quota_size=" +
        quota.size.unwrap_or(-1L).to_string() +
        " events=" +
        events.rules.length().to_string(),
      )
      if info.body.trim().is_empty() {
        fail("bucket_info returned an empty body")
      }
      if quota.body.trim().is_empty() {
        fail("bucket_quota returned an empty body")
      }
      if lifecycle.rules.length() > 0 && lifecycle.rules[0].name.is_empty() {
        fail("lifecycle rule parsed without a name: " + lifecycle.body)
      }
    }
  }
}

///|
async test "真桶·buckets 列表：UC QBox 签名与当前桶可见" {
  match read_kodo_live() {
    None => res_skip()
    Some(live) => {
      let client = mp_client(live) catch { err => fail("setup: " + err.text()) }
      let list = client.buckets() catch {
        err => fail("buckets: " + err.text())
      }
      println("kodo buckets count=" + list.names.length().to_string())
      if !has_bucket(list.names, live.bucket) {
        fail("configured bucket not in buckets response: " + list.body)
      }
    }
  }
}

///|
async test "真桶·chstatus/chtype/deleteAfterDays：自命名前缀，测完删净" {
  match read_kodo_live() {
    None => res_skip()
    Some(live) => {
      let client = mp_client(live) catch { err => fail("setup: " + err.text()) }
      let stamp = @date.now_millis().to_string()
      let day = stamp[0:8].to_owned()
      let key = "moonfs-kodo-" + day + "/" + stamp + "-resource.txt"
      let outcome = try {
        let put = client.put_bytes(key, @utf8.encode("resource probe")) catch {
          err => fail("put: " + err.text())
        }
        if put.key.unwrap_or("") != key {
          fail("put key mismatch: " + put.key.unwrap_or("<none>"))
        }
        client.change_type(key, @kodo.StorageType::Infrequency) catch {
          err => fail("chtype: " + err.text())
        }
        client.change_status(key, @kodo.ObjectStatus::Disabled) catch {
          err => fail("chstatus disabled: " + err.text())
        }
        client.change_status(key, @kodo.ObjectStatus::Enabled) catch {
          err => fail("chstatus enabled: " + err.text())
        }
        client.delete_after_days(key, 1) catch {
          err => fail("deleteAfterDays: " + err.text())
        }
        "no-error"
      } catch {
        err => "measure: " + err.to_string()
      }
      let deleted = client.delete(key) catch {
        err => {
          println("cleanup delete: " + err.text())
          false
        }
      }
      println(
        "kodo extra resource outcome=" +
        outcome +
        " deleted=" +
        deleted.to_string(),
      )
      if outcome != "no-error" {
        fail(outcome)
      }
    }
  }
}
