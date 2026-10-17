///|
/// 离线向量。期望值由一份**独立的** python 参照实现算出（工装在
/// `G:/dev-tools/tmp/2026-10-16-kodo/`：`kodo_ref.py` 按 2026-10-16 现读的官方
/// `qiniu/java-sdk` `util/Auth.java` 逐字重写，`gen_vectors.py` 用它生成本文件），
/// 不是 MoonBit 侧自己复述一遍——同输入同输出才算过。
/// 键是测试用的假键，与任何真凭据无关。卡 §6 的 KD1 / KD1b 落在这个文件上。
fn kd_bytes_of(items : Array[Int32]) -> Bytes {
  let out : Array[Byte] = []
  for i in items {
    out.push(i.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// 判"这个输入必须被拒"。`urlsafe_b64_decode` 成功档返回 Bytes，与 `catch` 臂的
/// Bool 不同型，所以只能包一层函数。
fn kd_b64_rejects(text : String) -> Bool {
  let _ = urlsafe_b64_decode(text) catch { _ => return true }
  false
}

///|
/// 同上形状，判 `raw_path_query` 的拒收档。
fn kd_url_rejects(text : String) -> Bool {
  let _ = raw_path_query(text) catch { _ => return true }
  false
}

///|
/// `Auth::new` 的两档都用文案读出。成功档回 `ok:` 加公开那半把键——
/// 判据要的是"这里必须走 raised 那支"，把两支都写成 String 才能同型断言
/// （`return` 在 catch 臂里是底型，所以这样写能过类型检查）。
fn kd_new_text(access_key : String, secret_key : String) -> String {
  let made = Auth::new(access_key, secret_key) catch {
    err => return "raised:" + err.text()
  }
  "ok:" + made.access_key()
}

///|
let kd_ak = "QnFK-test-access-key"

///|
let kd_sk = "test-secret-密钥"

///|
let kd_deadline = 1893456000L

///|
test "签名族 #1 sign：ak:urlsafe_b64(hmac_sha1(sk, data))" {
  let v1 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  // hello
  assert_eq(
    Auth::sign(v1, "hello"),
    "QnFK-test-access-key:UnBDNPQQd9MFUTmZoJ0ppJOyQLg=",
  )
  // 中文与符号 /\?=
  assert_eq(
    Auth::sign(v1, "中文与符号 /\\?="),
    "QnFK-test-access-key:jBrnMqNQKqij4l2erUjwxb-GdSA=",
  )
  // 空串
  assert_eq(
    Auth::sign(v1, ""),
    "QnFK-test-access-key:9J4yRZEScCRENLECprCNHLA63yY=",
  )
}

///|
test "签名族 #2 sign_with_data：先对编码后的串签，再拼编码串" {
  let v1 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  assert_eq(
    Auth::sign_with_data_bytes(v1, kd_bytes_of([97, 98, 99])),
    "QnFK-test-access-key:jKAMw6sC0gDMpSeptzsOcAy8sR0=:YWJj",
  )
  assert_eq(
    Auth::sign_with_data_bytes(
      v1,
      kd_bytes_of([
        123, 34, 115, 99, 111, 112, 101, 34, 58, 34, 98, 117, 99, 107, 101, 116,
        58, 107, 101, 121, 34, 44, 34, 100, 101, 97, 100, 108, 105, 110, 101, 34,
        58, 49, 125,
      ]),
    ),
    "QnFK-test-access-key:oUBPuh25Tf-fojfkJDqdVDyUJO0=:eyJzY29wZSI6ImJ1Y2tldDprZXkiLCJkZWFkbGluZSI6MX0=",
  )
  assert_eq(
    Auth::sign_with_data_bytes(
      v1,
      kd_bytes_of([231, 173, 150, 231, 149, 165, 228, 184, 173, 230, 150, 135]),
    ),
    "QnFK-test-access-key:TSWVJPVgb5WmKACxLBUF_dRhPPI=:562W55Wl5Lit5paH",
  )
}

///|
test "签名族 #3 urlsafe_b64：带填充（NO_WRAP 只关换行），且用 URL 表（-/_）" {
  assert_eq(urlsafe_b64(kd_bytes_of([])), "")
  assert_eq(urlsafe_b64(kd_bytes_of([102])), "Zg==")
  assert_eq(urlsafe_b64(kd_bytes_of([102, 111])), "Zm8=")
  assert_eq(urlsafe_b64(kd_bytes_of([102, 111, 111])), "Zm9v")
  assert_eq(urlsafe_b64(kd_bytes_of([102, 111, 111, 98])), "Zm9vYg==")
  assert_eq(urlsafe_b64(kd_bytes_of([251, 255, 191])), "-_-_")
  assert_eq(urlsafe_b64(kd_bytes_of([255, 255, 255])), "____")
  // 解码两条档都吃：官方 Java 的解码器把末尾 `=` 当可选（Base64.java:83），所以无填充串也要解得开
  assert_eq(urlsafe_b64_decode("____"), kd_bytes_of([255, 255, 255]))
  assert_eq(urlsafe_b64_decode("Zm9v"), kd_bytes_of([102, 111, 111]))
  // 长度不是 4 的倍数的无填充串也要靠补平才解得开（hutool 是严格档）
  assert_eq(urlsafe_b64_decode("Zg"), kd_bytes_of([102]))
  assert_eq(urlsafe_b64_decode("Zm9vYg"), kd_bytes_of([102, 111, 111, 98]))
  assert_eq(urlsafe_b64_decode("Zg=="), kd_bytes_of([102]))
  // 真坏的填充才拒：`=` 出现在中间
  assert_eq(kd_b64_rejects("Z=9v"), true)
}

///|
test "签名族 #4 QBox 待签串：raw 路径 + (?查询) + 换行 + 仅表单 body" {
  let v1 = qbox_signing_string("https://rs.qbox.me/stat/YWJj", None, None) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v1), "/stat/YWJj\n")
  let v2 = qbox_signing_string(
    "https://rs.qbox.me/list?bucket=moonfs&marker=m&limit=2",
    None,
    None,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v2), "/list?bucket=moonfs&marker=m&limit=2\n")
  let v3 = qbox_signing_string("https://rs.qbox.me/stat/abc?", None, None) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v3), "/stat/abc\n")
  let v4 = qbox_signing_string("https://rs.qbox.me", None, None) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v4), "\n")
  let v5 = qbox_signing_string(
    "https://up.qiniup.com",
    Some(
      kd_bytes_of([
        116, 111, 107, 101, 110, 61, 97, 98, 99, 38, 107, 101, 121, 61, 97, 37, 50,
        70, 98, 46, 116, 120, 116,
      ]),
    ),
    Some("application/x-www-form-urlencoded"),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v5), "\ntoken=abc&key=a%2Fb.txt")
  let v6 = qbox_signing_string(
    "https://up.qiniup.com",
    Some(kd_bytes_of([116, 111, 107, 101, 110, 61, 97, 98, 99])),
    Some("APPLICATION/X-WWW-FORM-URLENCODED"),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v6), "\ntoken=abc")
  let v7 = qbox_signing_string(
    "https://rs.qbox.me/stat/x",
    Some(
      kd_bytes_of([
        123, 34, 105, 103, 110, 111, 114, 101, 34, 58, 34, 109, 101, 34, 125,
      ]),
    ),
    Some("application/json"),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v7), "/stat/x\n")
  let v8 = qbox_signing_string("https://rs.qbox.me/stat/%E4%B8%AD", None, None) catch {
    err => fail(err.text())
  }
  assert_eq(@utf8.decode_lossy(v8), "/stat/%E4%B8%AD\n")
  let v9 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  let v10 = Auth::sign_request(
    v9,
    "https://rs.qbox.me/stat/YWJj",
    body=None,
    content_type=None,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v10, "QnFK-test-access-key:YXMr20TV4wQIGRZ8fkEwq1iDGX4=")
  let v11 = Auth::sign_request(
    v9,
    "https://rs.qbox.me/list?bucket=moonfs&marker=m&limit=2",
    body=None,
    content_type=None,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v11, "QnFK-test-access-key:FBzRTB0XRXS0VbtT2L9-tBC2Grg=")
  let v12 = Auth::sign_request(
    v9,
    "https://rs.qbox.me/stat/abc?",
    body=None,
    content_type=None,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v12, "QnFK-test-access-key:YSfYiocPO_6z2lFm-NKlyPcK4VA=")
  let v13 = Auth::sign_request(
    v9,
    "https://rs.qbox.me",
    body=None,
    content_type=None,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v13, "QnFK-test-access-key:QYY7k0RJmvEQlUfhDaRaaje5dz4=")
  let v14 = Auth::sign_request(
    v9,
    "https://up.qiniup.com",
    body=Some(
      kd_bytes_of([
        116, 111, 107, 101, 110, 61, 97, 98, 99, 38, 107, 101, 121, 61, 97, 37, 50,
        70, 98, 46, 116, 120, 116,
      ]),
    ),
    content_type=Some("application/x-www-form-urlencoded"),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v14, "QnFK-test-access-key:0G_K7FljzTNlSZZ2TAxdWXrtvzw=")
  let v15 = Auth::sign_request(
    v9,
    "https://up.qiniup.com",
    body=Some(kd_bytes_of([116, 111, 107, 101, 110, 61, 97, 98, 99])),
    content_type=Some("APPLICATION/X-WWW-FORM-URLENCODED"),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v15, "QnFK-test-access-key:-SufxklV74sEcB3w1gv5xwDuFH8=")
  let v16 = Auth::sign_request(
    v9,
    "https://rs.qbox.me/stat/x",
    body=Some(
      kd_bytes_of([
        123, 34, 105, 103, 110, 111, 114, 101, 34, 58, 34, 109, 101, 34, 125,
      ]),
    ),
    content_type=Some("application/json"),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v16, "QnFK-test-access-key:r4v93FUWrBb1mLOmlu4hDqFAIOA=")
  let v17 = Auth::sign_request(
    v9,
    "https://rs.qbox.me/stat/%E4%B8%AD",
    body=None,
    content_type=None,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v17, "QnFK-test-access-key:FYmk8FmoKSs7cktiO8_EXsA1iqg=")
  // QBox 头就是把上面那条摘要挂上 `QBox ` 前缀
  let v18 = Auth::qbox_authorization(
    v9,
    "https://rs.qbox.me/stat/YWJj",
    body=None,
    content_type=None,
  ) catch {
    err => fail(err.text())
  }
  let v19 = Auth::sign_request(
    v9,
    "https://rs.qbox.me/stat/YWJj",
    body=None,
    content_type=None,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v18.name, "Authorization")
  assert_eq(v18.value, "QBox " + v19)
}

///|
test "签名族 #5 私有 URL：先拼 e=，再对整串签，最后才拼 token=" {
  let v1 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  assert_eq(
    Auth::private_download_url_with_deadline(
      v1, "https://cdn.example.invalid/uploads/中文.txt", kd_deadline,
    ),
    "https://cdn.example.invalid/uploads/中文.txt?e=1893456000&token=QnFK-test-access-key:iy0MHATqpMRqGp28tmfDZ8HHDqs=",
  )
  assert_eq(
    Auth::private_download_url_with_deadline(
      v1, "https://cdn.example.invalid/a.png?imageView2/1/w/120", kd_deadline,
    ),
    "https://cdn.example.invalid/a.png?imageView2/1/w/120&e=1893456000&token=QnFK-test-access-key:Gf0RpPZNzk8byUG3FGkoMaX7fNA=",
  )
  // 带 expires 的那一档读当前时钟，只断形状不断读数
  let v2 = Auth::private_download_url(v1, "https://x.invalid/a.png")
  assert_eq(v2.contains("?e="), true)
  assert_eq(v2.contains("&token="), true)
}

///|
test "签名族 #6 上传令牌：scope/deadline 拼接与 strict 白名单" {
  let v1 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  let p_saveKey = UploadPolicy::new().put("saveKey", Text("$(hash)/$(ext)"))
  let p_fsizeLimit = p_saveKey.put("fsizeLimit", Count(1048576L))
  let p_insertOnly = p_fsizeLimit.put("insertOnly", Flag(true))
  let p_mimeLimit = p_insertOnly.put("mimeLimit", Text("image/png;jpeg"))
  let p_notAWhitelistField = p_mimeLimit.put(
    "notAWhitelistField",
    Text("dropped-when-strict"),
  )
  let policy = p_notAWhitelistField
  // strict=true：白名单外那条被丢掉
  let v2 = Auth::upload_token_with_deadline(
    v1,
    "moonfs",
    kd_deadline,
    key=Some("a/b.txt"),
    policy=Some(policy),
    strict=true,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(
    v2, "QnFK-test-access-key:wLhn2jCeNHDLSTTUpspG_ADZ7qs=:eyJzYXZlS2V5IjoiJChoYXNoKS8kKGV4dCkiLCJmc2l6ZUxpbWl0IjoxMDQ4NTc2LCJpbnNlcnRPbmx5Ijp0cnVlLCJtaW1lTGltaXQiOiJpbWFnZS9wbmc7anBlZyIsInNjb3BlIjoibW9vbmZzOmEvYi50eHQiLCJkZWFkbGluZSI6MTg5MzQ1NjAwMH0=",
  )
  let v3 = decode_upload_token(v2) catch { err => fail(err.text()) }
  assert_eq(v3.0, kd_ak)
  assert_eq(
    v3.2,
    "{\"saveKey\":\"$(hash)/$(ext)\",\"fsizeLimit\":1048576,\"insertOnly\":true,\"mimeLimit\":\"image/png;jpeg\",\"scope\":\"moonfs:a/b.txt\",\"deadline\":1893456000}",
  )
  // strict=false：非白名单字段照收
  let v4 = Auth::upload_token_with_deadline(
    v1,
    "moonfs",
    kd_deadline,
    key=None,
    policy=Some(policy),
    strict=false,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(
    v4, "QnFK-test-access-key:YwdE29gXj4ngh5oYJ1OAGobB6MI=:eyJzYXZlS2V5IjoiJChoYXNoKS8kKGV4dCkiLCJmc2l6ZUxpbWl0IjoxMDQ4NTc2LCJpbnNlcnRPbmx5Ijp0cnVlLCJtaW1lTGltaXQiOiJpbWFnZS9wbmc7anBlZyIsIm5vdEFXaGl0ZWxpc3RGaWVsZCI6ImRyb3BwZWQtd2hlbi1zdHJpY3QiLCJzY29wZSI6Im1vb25mcyIsImRlYWRsaW5lIjoxODkzNDU2MDAwfQ==",
  )
  let v5 = decode_upload_token(v4) catch { err => fail(err.text()) }
  assert_eq(
    v5.2,
    "{\"saveKey\":\"$(hash)/$(ext)\",\"fsizeLimit\":1048576,\"insertOnly\":true,\"mimeLimit\":\"image/png;jpeg\",\"notAWhitelistField\":\"dropped-when-strict\",\"scope\":\"moonfs\",\"deadline\":1893456000}",
  )
  // key 不给时 scope 只有桶名；policy 不给时只剩 scope 与 deadline
  let v6 = Auth::upload_token_with_deadline(
    v1,
    "moonfs",
    kd_deadline,
    key=None,
    policy=None,
    strict=true,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(
    v6, "QnFK-test-access-key:K01kqQm91BmfJDXz25U4Z_uCJpg=:eyJzY29wZSI6Im1vb25mcyIsImRlYWRsaW5lIjoxODkzNDU2MDAwfQ==",
  )
  let v7 = decode_upload_token(v6) catch { err => fail(err.text()) }
  assert_eq(v7.2, "{\"scope\":\"moonfs\",\"deadline\":1893456000}")
}

///|
test "签名族 #6b 令牌的本地拒收档（返回了值就是判据失败）" {
  let v1 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  let stale = UploadPolicy::new().put("asyncOps", Text("x"))
  assert_eq(
    kd_token_text(v1, "moonfs", Some(stale), true),
    "raised:kodo bad param(-4): asyncOps is deprecated!",
  )
  assert_eq(
    kd_token_text(v1, "", None, true),
    "raised:kodo bad param(-4): upload token needs a bucket name",
  )
  // 空 ak / 空 sk：官方 create 抛 IllegalArgumentException，这里同一档
  assert_eq(
    kd_new_text("", kd_sk),
    "raised:kodo bad param(-4): access key is empty",
  )
  assert_eq(
    kd_new_text(kd_ak, ""),
    "raised:kodo bad param(-4): secret key is empty",
  )
  // 正常档不是被误拒的：两把键都在就出得来
  assert_eq(kd_new_text(kd_ak, kd_sk), "ok:QnFK-test-access-key")
}

///|
test "签名族 #6c 令牌走时钟那一档时，deadline 是秒不是毫秒" {
  let v1 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  let v2 = v1.upload_token("moonfs") catch { err => fail(err.text()) }
  let v3 = decode_upload_token(v2) catch { err => fail(err.text()) }
  let deadline = kd_deadline_from(v3.2)
  let now_sec = @date.now_millis() / 1000L
  // 秒档：过期点在 now 之后一小时内；毫秒档会大三个数量级，立刻红
  assert_eq(deadline > now_sec, true)
  assert_eq(deadline - now_sec < 3700L, true)
  assert_eq(deadline < 10000000000L, true)
}

///|
test "签名族 #7 Qiniu 待签串：解码路径 + raw 查询 + Host + 排序后的 X-Qiniu 头" {
  let v1 = qiniu_signing_string(
    "https://up.example.com/buckets/moonfs/objects/YWJj/uploads",
    "POST",
    Some(kd_bytes_of([123, 34, 112, 97, 114, 116, 115, 34, 58, 91, 93, 125])),
    [
      @transport.Header::{ name: "Content-Type", value: "application/json", },
      @transport.Header::{ name: "X-Qiniu-Date", value: "20300101T000000Z", },
    ],
  ) catch {
    err => fail(err.text())
  }
  assert_eq(
    v1, "POST /buckets/moonfs/objects/YWJj/uploads\nHost: up.example.com\nContent-Type: application/json\nX-Qiniu-Date: 20300101T000000Z\n\n{\"parts\":[]}",
  )
  let v2 = qiniu_signing_string(
    "http://127.0.0.1:19100/stat/abc",
    "GET",
    None,
    [],
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v2, "GET /stat/abc\nHost: 127.0.0.1:19100\n\n")
  let v3 = qiniu_signing_string(
    "https://uc.qiniuapi.com/v4/query?ak=key&bucket=moonfs",
    "GET",
    None,
    [],
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v3, "GET /v4/query?ak=key&bucket=moonfs\nHost: uc.qiniuapi.com\n\n")
  let v4 = qiniu_signing_string(
    "https://up.example.com/x?",
    "POST",
    Some(kd_bytes_of([116, 111, 107, 101, 110, 61, 49])),
    [
      @transport.Header::{
        name: "Content-Type",
        value: "application/x-www-form-urlencoded",
      },
    ],
  ) catch {
    err => fail(err.text())
  }
  assert_eq(
    v4, "POST /x?\nHost: up.example.com\nContent-Type: application/x-www-form-urlencoded\n\ntoken=1",
  )
  let v5 = qiniu_signing_string(
    "https://up.example.com/x",
    "POST",
    Some(kd_bytes_of([114, 97, 119])),
    [
      @transport.Header::{
        name: "Content-Type",
        value: "application/octet-stream",
      },
    ],
  ) catch {
    err => fail(err.text())
  }
  assert_eq(
    v5, "POST /x\nHost: up.example.com\nContent-Type: application/octet-stream\n\n",
  )
  let v6 = qiniu_signing_string("https://up.example.com/x", "", None, [
    @transport.Header::{ name: "x-qiniu-b", value: "2", },
    @transport.Header::{ name: "X-Qiniu-A", value: "1", },
    @transport.Header::{ name: "X-Qiniu-", value: "太短不算", },
    @transport.Header::{ name: "Content-Type", value: "application/json", },
  ]) catch {
    err => fail(err.text())
  }
  assert_eq(
    v6, "GET /x\nHost: up.example.com\nContent-Type: application/json\nX-Qiniu-A: 1\nX-Qiniu-B: 2\n\n",
  )
  let v7 = qiniu_signing_string(
    "https://up.example.com/a%2Fb?c=%20d",
    "GET",
    None,
    [],
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v7, "GET /a/b?c=%20d\nHost: up.example.com\n\n")
  let v8 = qiniu_signing_string("https://up.example.com/x", "GET", None, [
    @transport.Header::{ name: "X-Qiniu-Z", value: "1", },
    @transport.Header::{ name: "X-Qiniu-Ab", value: "2", },
    @transport.Header::{ name: "X-Qiniu-Aaa", value: "3", },
  ]) catch {
    err => fail(err.text())
  }
  assert_eq(
    v8, "GET /x\nHost: up.example.com\nX-Qiniu-Aaa: 3\nX-Qiniu-Ab: 2\nX-Qiniu-Z: 1\n\n",
  )
}

///|
test "签名族 #8 Qiniu 请求头：时间戳头进签名，Authorization 排在最后" {
  let v1 = Auth::new(kd_ak, kd_sk) catch { err => fail(err.text()) }
  let payload = @utf8.encode("{}")
  let base = [
    @transport.Header::{ name: "Content-Type", value: "application/json", },
  ]
  let v2 = Auth::qiniu_authorization(
    v1,
    "https://up.example.com/buckets/moonfs/objects/YWJj/uploads",
    "POST",
    body=Some(payload),
    headers=base,
    timestamp=Some(On(kd_deadline * 1000L)),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v2.length(), 3)
  assert_eq(v2[0].name, "Content-Type")
  assert_eq(v2[1].name, "X-Qiniu-Date")
  assert_eq(v2[1].value, "20300101T000000Z")
  assert_eq(v2[2].name, "Authorization")
  assert_eq(
    v2[2].value,
    "Qiniu QnFK-test-access-key:VJ0UiEV_yo8Bi7ZXba8SnhRJ43c=",
  )
  // Off 档＝官方那个 DISABLE_QINIU_TIMESTAMP_SIGNATURE：不带时间戳头
  let v3 = Auth::qiniu_authorization(
    v1,
    "https://up.example.com/buckets/moonfs/objects/YWJj/uploads",
    "POST",
    body=Some(payload),
    headers=base,
    timestamp=Some(Off),
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v3.length(), 2)
  assert_eq(
    v3[1].value,
    "Qiniu QnFK-test-access-key:T-2Tx_8YDmX-TFBwAOh4FKtuQF8=",
  )
  // 不传 timestamp 时按当前时钟补：只断形状，不断读数
  let v4 = Auth::qiniu_authorization(
    v1,
    "https://up.example.com/buckets/moonfs/objects/YWJj/uploads",
    "POST",
    body=Some(payload),
    headers=base,
  ) catch {
    err => fail(err.text())
  }
  assert_eq(v4.length(), 3)
  assert_eq(v4[1].name, "X-Qiniu-Date")
  assert_eq(v4[1].value.length(), 16)
}

///|
test "签名族 #9 X-Qiniu-Date 形状：UTC 的 yyyyMMdd'T'HHmmss'Z'" {
  assert_eq(qiniu_date_utc(0L), "19700101T000000Z")
  assert_eq(qiniu_date_utc(1893456000000L), "20300101T000000Z")
  assert_eq(qiniu_date_utc(1700000599000L), "20231114T222319Z")
}

///|
test "签名族 #10 头名规范化：token 表外的字符让整串原样返回" {
  assert_eq(canonical_mime_header_key("accept-encoding"), "Accept-Encoding")
  assert_eq(canonical_mime_header_key("X-Qiniu-Date"), "X-Qiniu-Date")
  assert_eq(canonical_mime_header_key("x-qiniu-date"), "X-Qiniu-Date")
  assert_eq(canonical_mime_header_key("content-TYPE"), "Content-Type")
  assert_eq(canonical_mime_header_key("bad name"), "bad name")
  assert_eq(canonical_mime_header_key("非ascii"), "非ascii")
  assert_eq(canonical_mime_header_key("x-qiniu-"), "X-Qiniu-")
  assert_eq(canonical_mime_header_key("a|b~c^d`e"), "A|b~c^d`e")
  assert_eq(canonical_mime_header_key("E|b~c^d`e"), "E|b~c^d`e")
}

///|
test "签名族 #11 percent 还原：合法转义逐字节拼回，非法的原样留" {
  assert_eq(percent_decode("/a%2Fb"), "/a/b")
  assert_eq(percent_decode("%E4%B8%AD%E6%96%87"), "中文")
  assert_eq(percent_decode("%zz"), "%zz")
  assert_eq(percent_decode("%2"), "%2")
  assert_eq(percent_decode("plain"), "plain")
  assert_eq(percent_decode("%2f%2F"), "//")
  assert_eq(percent_decode("%"), "%")
  assert_eq(percent_decode("%41%42"), "AB")
}

///|
test "签名族 #12 拆 URL：`?` 有与没有是两档，空路径就是空串" {
  let v1 = raw_path_query("https://rs.qbox.me/stat/abc") catch {
    err => fail(err.text())
  }
  assert_eq(v1, ("/stat/abc", None))
  let v2 = raw_path_query("https://rs.qbox.me/stat/abc?x=1") catch {
    err => fail(err.text())
  }
  assert_eq(v2, ("/stat/abc", Some("x=1")))
  let v3 = raw_path_query("https://rs.qbox.me/stat/abc?") catch {
    err => fail(err.text())
  }
  assert_eq(v3, ("/stat/abc", Some("")))
  let v4 = raw_path_query("https://rs.qbox.me") catch {
    err => fail(err.text())
  }
  assert_eq(v4, ("", None))
  let v5 = raw_path_query("https://rs.qbox.me/a%2Fb?c=%20d") catch {
    err => fail(err.text())
  }
  assert_eq(v5, ("/a%2Fb", Some("c=%20d")))
  let v6 = host_port("http://127.0.0.1:19100/x") catch {
    err => fail(err.text())
  }
  assert_eq(v6, ("127.0.0.1", Some(19100)))
  let v7 = host_port("https://uc.qiniuapi.com/v4/query") catch {
    err => fail(err.text())
  }
  assert_eq(v7, ("uc.qiniuapi.com", None))
  let v8 = host_port("http://host:name/x") catch { err => fail(err.text()) }
  assert_eq(v8, ("host:name", None))
  // 没有 scheme 就没什么可签的：报错而不是猜
  assert_eq(kd_url_rejects("rs.qbox.me/stat"), true)
}

///|
/// 令牌那条路的读数取回来：正常返回带值，被拒就写 `raised:` 加文案
/// （`upload_token_with_deadline` 会 raise，成功与失败两档同型才能断言）。
fn kd_token_text(
  auth : Auth,
  bucket : String,
  policy : UploadPolicy?,
  strict : Bool,
) -> String {
  auth.upload_token_with_deadline(
    bucket,
    kd_deadline,
    key=None,
    policy~,
    strict~,
  ) catch {
    err => "raised:" + err.text()
  }
}

///|
/// 从策略 JSON 里读出 `deadline` 的数值（只扫数字，读到非数字就停）。
fn kd_deadline_from(text : String) -> Int64 {
  let key = "\"deadline\":"
  let at = match text.find(key) {
    None => abort("策略 JSON 里没有 deadline：" + text)
    Some(i) => i + key.length()
  }
  let chars = text[at:text.length()].to_owned().to_array()
  let mut value = 0L
  let mut i = 0
  while i < chars.length() {
    let code = chars[i].to_int()
    if code >= 48 && code <= 57 {
      value = value * 10L + (code - 48).to_int64()
      i = i + 1
    } else {
      i = chars.length()
    }
  }
  value
}
