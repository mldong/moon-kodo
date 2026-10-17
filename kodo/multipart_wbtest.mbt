///|
/// V2 分块的纯函数判据（离线，一条请求都不发）。
///
/// 期望串全部由**独立第二实现**算出再钉进这里（工装 `multipart_vectors.py`：python 的
/// `base64.urlsafe_b64encode` 与小写 `hashlib.md5`），不是拿本包自己的输出抄一份回来当标准。
/// `complete_body` 的那几份串还各自过了一次 `json.loads`，证明"我们期望的形状"本身是合法 JSON。

///|
fn part_number_reading(number : Int32) -> String {
  check_part_number(number) catch {
    err => return "refused:" + err.text()
  }
  "ok"
}

///|
fn block_size_reading(size : Int32, last~ : Bool) -> String {
  check_block_size(size, last~) catch {
    err => return "refused:" + err.text()
  }
  "ok"
}

///|
fn split_reading(total : Int32, block : Int32) -> String {
  let ranges = split_blocks(total, block) catch {
    err => return "refused:" + err.text()
  }
  let items : Array[String] = []
  for range in ranges {
    items.push("(" + range.0.to_string() + "," + range.1.to_string() + ")")
  }
  items.join(" ")
}

///|
test "分块 #0 key 段：四档实串 + 空 key 走空段" {
  assert_eq(v2_key_segment(""), "")
  assert_eq(v2_key_segment("a/b.txt"), "YS9iLnR4dA==")
  assert_eq(v2_key_segment("中文/文件.txt"), "5Lit5paHL-aWh-S7ti50eHQ=")
  assert_eq(
    v2_key_segment("moonfs-kodo-1/2.txt"),
    "bW9vbmZzLWtvZG8tMS8yLnR4dA==",
  )
  // 长度是 3 的倍数时填充本来就为空：这一档证明"带填充"不是"一律补两个等号"
  assert_eq(v2_key_segment("no-ext"), "bm8tZXh0")
}

///|
test "分块 #1 片号边界：1 与 10000 放行，两头各差一个就拒" {
  assert_eq(part_number_reading(1), "ok")
  assert_eq(part_number_reading(10000), "ok")
  assert_eq(
    part_number_reading(0),
    "refused:kodo bad param(-4): part number must be within 1~10000, got 0",
  )
  assert_eq(
    part_number_reading(10001),
    "refused:kodo bad param(-4): part number must be within 1~10000, got 10001",
  )
  assert_eq(
    part_number_reading(-1),
    "refused:kodo bad param(-4): part number must be within 1~10000, got -1",
  )
}

///|
test "分块 #2 块大小：末片不限，非末片必须在 1MB~1GB 内" {
  // 末片可以是 1 字节，也可以是 0（空对象那一档）
  assert_eq(block_size_reading(1, last=true), "ok")
  assert_eq(block_size_reading(0, last=true), "ok")
  assert_eq(block_size_reading(1073741825, last=true), "ok")
  assert_eq(block_size_reading(1048576, last=false), "ok")
  assert_eq(block_size_reading(1073741824, last=false), "ok")
  assert_eq(
    block_size_reading(1048575, last=false),
    "refused:kodo bad param(-4): every part but the last must be 1048576~1073741824 bytes, got 1048575",
  )
  assert_eq(
    block_size_reading(0, last=false),
    "refused:kodo bad param(-4): every part but the last must be 1048576~1073741824 bytes, got 0",
  )
}

///|
test "分块 #3 切偏移：两片 / 三片 / 整片 / 空对象 / 块大小越界" {
  // 1MiB+1 是真桶那条腿的尺寸：前一片满 1MB，末片 1 字节
  assert_eq(split_reading(1048577, 1048576), "(0,1048576) (1048576,1)")
  assert_eq(split_reading(1048576, 1048576), "(0,1048576)")
  assert_eq(
    split_reading(3000000, 1048576),
    "(0,1048576) (1048576,1048576) (2097152,902848)",
  )
  assert_eq(split_reading(100, 4194304), "(0,100)")
  // 空对象给一档 (0,0)：complete 至少要一个分片，切成零片会让合并无处发
  assert_eq(split_reading(0, 4194304), "(0,0)")
  assert_eq(
    split_reading(10485760, 1048575),
    "refused:kodo bad param(-4): block size must be 1048576~1073741824 bytes",
  )
  assert_eq(
    split_reading(10485760, 1073741825),
    "refused:kodo bad param(-4): block size must be 1048576~1073741824 bytes",
  )
}

///|
fn two_parts() -> Array[PartInfo] {
  [
    PartInfo::{ part_number: 1, etag: "FhY1abc", size: None, put_time: None, },
    PartInfo::{
      part_number: 2,
      etag: "FhY2\"quote",
      size: None,
      put_time: None,
    },
  ]
}

///|
fn one_part() -> Array[PartInfo] {
  [PartInfo::{ part_number: 1, etag: "FhY1abc", size: None, put_time: None, }]
}

///|
test "分块 #4 complete 体：只带 parts，etag 里的引号要转义" {
  assert_eq(
    complete_body(two_parts()),
    "{\"parts\":[{\"partNumber\":1,\"etag\":\"FhY1abc\"},{\"partNumber\":2,\"etag\":\"FhY2\\\"quote\"}]}",
  )
  // 空数组这一档本包拼得出来（零片），但 complete_multipart 在调用它之前就拒
  assert_eq(complete_body([]), "{\"parts\":[]}")
}

///|
test "分块 #5 complete 体：fname / mimeType / customVars / metaData 的键序" {
  assert_eq(
    complete_body(
      one_part(),
      filename=Some("n.txt"),
      mime_type=Some("text/plain"),
      custom_vars=[("x:uid", "7")],
      meta=[("x-qn-meta-author", "me")],
    ),
    "{\"parts\":[{\"partNumber\":1,\"etag\":\"FhY1abc\"}],\"fname\":\"n.txt\",\"mimeType\":\"text/plain\",\"customVars\":{\"x:uid\":\"7\"},\"metaData\":{\"x-qn-meta-author\":\"me\"}}",
  )
  // 不给就不写键；给了空串是要写进去的（官方 `buildBodyInfo` 只判 null，不判空串）
  assert_eq(
    complete_body(one_part(), filename=Some("")),
    "{\"parts\":[{\"partNumber\":1,\"etag\":\"FhY1abc\"}],\"fname\":\"\"}",
  )
  assert_eq(
    complete_body(one_part(), custom_vars=[("a", "b"), ("c", "d")]),
    "{\"parts\":[{\"partNumber\":1,\"etag\":\"FhY1abc\"}],\"customVars\":{\"a\":\"b\",\"c\":\"d\"}}",
  )
}

///|
/// 一块 1 MiB 的确定性内容：16 字节表重复 65536 次。真桶那条腿就拿它当满片。
fn filler_1mib() -> Bytes {
  let seed = @utf8.encode("0123456789abcdef")
  let merged : Array[Byte] = []
  for _ in 0..<65536 {
    merged.append(seed.to_array())
  }
  Bytes::from_array(merged)
}

///|
test "分块 #6 块摘要：小档、满片档、末片那 1 字节都对得上独立实现" {
  assert_eq(
    block_md5_hex(@utf8.encode("moon-kodo md5 vector")),
    "8670c0c870d550cc9bbd42cc354d92e8",
  )
  assert_eq(filler_1mib().length(), 1048576)
  assert_eq(block_md5_hex(filler_1mib()), "14d785daab3823736c981ca82a750c98")
  assert_eq(
    block_md5_hex(filler_1mib()[0:1].to_owned()),
    "cfcd208495d565ef66e7dff9f98764da",
  )
}

///|
fn md5_check_reading(number : Int32, server : String, want : String) -> String {
  check_part_md5(number, server, want) catch {
    err => return "refused:" + err.text()
  }
  "ok"
}

///|
/// KD3b 的牙：`check_crc` 开着时摘要不等必须**响**，且抛在合并之前。
test "分块 #7 块摘要比对：等则放行，不等则报是哪一片、两边各读到什么" {
  assert_eq(md5_check_reading(1, "aa", "aa"), "ok")
  assert_eq(
    md5_check_reading(2, "bb", "aa"),
    "refused:kodo bad response: block's md5 is not match at part 2, server said bb, expected aa",
  )
  // 空读数不放行：服务端没回 md5 与回了个空串都不算对上
  assert_eq(
    md5_check_reading(1, "", "aa"),
    "refused:kodo bad response: block's md5 is not match at part 1, server said , expected aa",
  )
}

///|
/// 篡改一块内容那一档先在离线钉形状：本地对**篡改后**的字节重算，与当初的期望值必然不等，
/// 判据就落在 `check_part_md5` 那一句上（真桶那条腿跑的是同一句）。
test "分块 #8 篡改一块：本地重算与期望摘要是两把，判据不把两者混成一个" {
  let clean = @utf8.encode("moon-kodo md5 vector")
  let tampered = @utf8.encode("moon-kodo md5 vectox")
  let want = block_md5_hex(clean)
  let got = block_md5_hex(tampered)
  assert_eq(want, "8670c0c870d550cc9bbd42cc354d92e8")
  assert_eq(got == want, false)
  assert_eq(md5_check_reading(1, got, want).has_prefix("refused:"), true)
}

///|
test "分块 #9 片号排序：乱序进升序出，且不受字符串比较器影响" {
  let shuffled = [
    PartInfo::{ part_number: 10, etag: "e10", size: None, put_time: None, },
    PartInfo::{ part_number: 2, etag: "e2", size: None, put_time: None, },
    PartInfo::{ part_number: 1, etag: "e1", size: None, put_time: None, },
  ]
  let ordered = sort_parts(shuffled)
  let numbers : Array[String] = []
  for part in ordered {
    numbers.push(part.part_number.to_string())
  }
  // 若按 etag 串排就会踩"先比长度"的坑：e10 会跑到 e2 前面
  assert_eq(numbers.join(","), "1,2,10")
  assert_eq(ordered[0].etag, "e1")
  assert_eq(ordered[2].etag, "e10")
}

///|
/// 一个从不发请求的传输：URL 形状与"拒在发出之前"这两族判据靠它自证没上网。
struct StubTransport {}

///|
impl @transport.Transport for StubTransport with fn send(self, request) {
  let detail = "stub transport must not be called: " + request.url
  let _ = self
  raise @transport.TransportError::InvalidRequest(detail)
}

///|
fn stub_client(bucket : String) -> Client raise @error.KodoError {
  // 桩件只取真区域的主机名，不发请求，所以凭据是假的也无妨
  let region = match @config.Region::with_region_id("z0") {
    None => raise @error.BadParam("z0 must be constructible")
    Some(one) => one
  }
  Client::{
    transport: StubTransport::{ },
    auth: @auth.Auth::new("ak-stub", "sk-stub"),
    config: @config.Config::new(region, use_https=true),
    bucket,
  }
}

///|
fn v2_url_reading(client : Client, key : String, upload_id : String) -> String {
  let url = client.v2_url(key, upload_id=Some(upload_id)) catch {
    err => return "refused:" + err.text()
  }
  url
}

///|
test "分块 #10 URL 形状：init 段 / 带 uploadId / 空 uploadId 先拒 / 越界片号先拒" {
  let client = stub_client("sample-bucket")
  assert_eq(
    client.v2_url("a/b.txt"),
    "https://upload.qiniup.com/buckets/sample-bucket/objects/YS9iLnR4dA==/uploads",
  )
  assert_eq(
    v2_url_reading(client, "a/b.txt", "U1987654321"),
    "https://upload.qiniup.com/buckets/sample-bucket/objects/YS9iLnR4dA==/uploads/U1987654321",
  )
  assert_eq(
    v2_url_reading(client, "a/b.txt", ""),
    "refused:kodo bad param(-4): uploadId is empty",
  )
  assert_eq(
    client.v2_url("a/b.txt", upload_id=Some("U1"), part_number=Some(2)),
    "https://upload.qiniup.com/buckets/sample-bucket/objects/YS9iLnR4dA==/uploads/U1/2",
  )
  // 越界片号同样拒在拼 URL 这一步，请求不会出门
  let bad_part = client.v2_url(
    "a/b.txt",
    upload_id=Some("U1"),
    part_number=Some(0),
  ) catch {
    err => "refused:" + err.text()
  }
  assert_eq(
    bad_part, "refused:kodo bad param(-4): part number must be within 1~10000, got 0",
  )
}

///|
test "分块 #11 回包读口：parts 数组逐条取字段，数字走扫描器" {
  let text = "{\"parts\":[{\"etag\":\"e1\",\"partNumber\":1,\"putTime\":1700000000000,\"size\":1048576},{\"etag\":\"e2\",\"partNumber\":2,\"size\":1}],\"partNumberMarker\":0,\"truncated\":false,\"uploadId\":\"U1\"}"
  let rows = @error.json_objects(text, "parts")
  assert_eq(rows.length(), 2)
  assert_eq(@error.json_string_field(rows[0], "etag"), Some("e1"))
  assert_eq(@error.json_int_field(rows[0], "size"), Some(1048576L))
  assert_eq(@error.json_int_field(rows[1], "partNumber"), Some(2L))
  // putTime 是 13 位：必须走 Int64，落回 Int 会截
  assert_eq(@error.json_int_field(rows[0], "putTime"), Some(1700000000000L))
  assert_eq(@error.json_int_field(rows[1], "putTime"), None)
  assert_eq(@error.json_int_field(text, "partNumberMarker"), Some(0L))
  assert_eq(@error.json_bool_field(text, "truncated"), Some(false))
  assert_eq(@error.json_bool_field(text, "uploadId"), None)
  assert_eq(@error.json_objects(text, "nope").length(), 0)
}
