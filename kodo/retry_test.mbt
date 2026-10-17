///|
/// 重试档的行为判据（离线，一条请求都不上网）：按脚本行事的桩传输数出"真发了几次"，
/// 三档读数——没应答后重发一次就成了 / 两次都没应答就停（不多发） / 服务端回过话一律不多发。

///|
enum Scripted {
  Raise(@transport.TransportError)
  Answer(Int32)
}

///|
struct QuietBody {}

///|
impl @transport.ResponseBody for QuietBody with fn read(self, max_bytes) {
  let _ = max_bytes
  let _ = self
  None
}

///|
impl @transport.ResponseBody for QuietBody with fn close(self) {
  let _ = self
}

///|
struct ScriptedTransport {
  script : Array[Scripted]
  received : Array[@transport.Request]
}

///|
impl @transport.Transport for ScriptedTransport with fn send(self, request) {
  self.received.push(request)
  let index = self.received.length() - 1
  let step = if index < self.script.length() {
    self.script[index]
  } else {
    Scripted::Answer(200)
  }
  match step {
    Scripted::Raise(err) => raise err
    Scripted::Answer(code) =>
      @transport.Response::{ status: code, headers: [], body: QuietBody::{ }, }
  }
}

///|
fn scripted_client(
  script : Array[Scripted],
) -> (@kodo.Client, ScriptedTransport) raise {
  let stub = ScriptedTransport::{ script, received: [], }
  let transport : &@transport.Transport = stub
  let region = match @config.Region::with_region_id("z0") {
    None => fail("z0 must be constructible")
    Some(one) => one
  }
  let client = @kodo.Client::new(
    transport,
    @auth.Auth::new("ak-stub", "sk-stub"),
    @config.Config::new(region, use_https=true),
    "blog",
  )
  (client, stub)
}

///|
async fn stat_outcome(client : @kodo.Client) -> String raise @error.KodoError {
  let row = client.stat("a/b.txt")
  "ok fsize=" + row.fsize.unwrap_or(-1L).to_string()
}

///|
async test "重试行为 #4 流式体不在重发之列（官方 canReset=false 那一档）" {
  assert_eq(@kodo.replayable(@transport.RequestBody::Empty), true)
  let data = @utf8.encode("streamed body")
  let reader = @io.MemoryReader::MemoryReader(writer => writer.write(data))
  let streamed = @transport.RequestBody::Stream(
    reader,
    Some(data.length().to_int64()),
  )
  assert_eq(@kodo.replayable(streamed), false)
  // `MemoryReader` 背后是个生产者任务：不读到尽头，退出时会被运行时算成"还有任务活着"
  let acc : Array[Byte] = []
  let mut more = true
  while more {
    match reader.read_some(max_len=4096) {
      None => more = false
      Some(chunk) => acc.append(chunk.to_array())
    }
  }
  assert_eq(acc.length(), data.length())
}

///|
async test "重试行为 #0 第一发没应答、第二发成了 ⇒ 恰好两发且读数为成功" {
  let (client, stub) = scripted_client([
    Scripted::Raise(@transport.TransportError::Timeout),
  ])
  let reading = stat_outcome(client) catch { err => "raised:" + err.text() }
  println("读数=" + reading + " 发出=" + stub.received.length().to_string())
  assert_eq(reading, "ok fsize=-1")
  assert_eq(stub.received.length(), 2)
}

///|
async test "重试行为 #1 两发都没应答 ⇒ 只多发一次就把失败交回去" {
  let (client, stub) = scripted_client([
    Scripted::Raise(@transport.TransportError::Network("stalled")),
    Scripted::Raise(@transport.TransportError::Network("stalled")),
  ])
  let reading = stat_outcome(client) catch { err => "raised:" + err.text() }
  println("读数=" + reading + " 发出=" + stub.received.length().to_string())
  assert_eq(reading, "raised:kodo network(-1): stalled")
  assert_eq(stub.received.length(), 2)
}

///|
async test "重试行为 #2 服务端回了 612 ⇒ 一发都不多发（重发等于把一次已发生的操作再来一遍）" {
  let (client, stub) = scripted_client([Scripted::Answer(612)])
  let reading = stat_outcome(client) catch { err => "raised:" + err.text() }
  println("读数=" + reading + " 发出=" + stub.received.length().to_string())
  assert_eq(reading.has_prefix("raised:kodo service(612)"), true)
  assert_eq(stub.received.length(), 1)
}

///|
async test "重试行为 #3 预签名 GET 那条路也吃同一档（open_url 走的就是 send）" {
  let (client, stub) = scripted_client([
    Scripted::Raise(@transport.TransportError::Timeout),
  ])
  let response = client.open_url("https://blog.example.invalid/a/b.txt") catch {
    err => fail("open_url raised: " + err.text())
  }
  let line = "open_url status=" +
    response.status.to_string() +
    " 发出=" +
    stub.received.length().to_string()
  println(line)
  assert_eq(response.status, 200)
  assert_eq(stub.received.length(), 2)
  response.body.close()
}
