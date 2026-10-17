///|
/// `stat` 回包的读口判据（离线）。那份 body 是 2026-10-17 真桶现读的原文（工装
/// `meta_probe.py`：表单带 `x-qn-meta-case` 写一枚对象，再 rs `stat` 读回），
/// 形状是**独立侧**先看到的，不是照本包的解析器反推的。

///|
fn stat_sample() -> String {
  "{\"fsize\":24,\"hash\":\"Fpg-4kRJ7t6ROJnJx931LbOih5Af\",\"lastModify\":17921974975092919,\"md5\":\"09debc3b9458030a07cf1aafd668f657\",\"mimeType\":\"text/plain\",\"putTime\":17921974975092919,\"type\":0,\"x-qn-meta\":{\"case\":\"qiniu\",\"kind\":\"adapter\"}}"
}

///|
test "对象族 #0 stat 读数：数字走 Int64，putTime 17 位不截" {
  let text = stat_sample()
  assert_eq(@error.json_int_field(text, "fsize"), Some(24L))
  assert_eq(@error.json_int_field(text, "putTime"), Some(17921974975092919L))
  assert_eq(@error.json_string_field(text, "mimeType"), Some("text/plain"))
  assert_eq(
    @error.json_string_field(text, "hash"),
    Some("Fpg-4kRJ7t6ROJnJx931LbOih5Af"),
  )
  assert_eq(stat_user_metadata(text), [("case", "qiniu"), ("kind", "adapter")])
}

///|
/// 写侧与读侧的形状不同这一条：字段是平铺的 `x-qn-meta-case`，回包是嵌套对象。
test "对象族 #1 元数据前缀只在写侧出现一次" {
  assert_eq(meta_form_fields([("case", "qiniu"), ("kind", "adapter")]), [
    ("x-qn-meta-case", "qiniu"),
    ("x-qn-meta-kind", "adapter"),
  ])
  assert_eq(meta_form_fields([]), [])
  assert_eq(meta_prefix, "x-qn-meta-")
  // 没有这一族时回空表，不是"读失败"
  assert_eq(stat_user_metadata("{\"fsize\":1}"), [])
  assert_eq(stat_user_metadata("{\"x-qn-meta\":{}}"), [])
}

///|
test "对象族 #2 键值扫描器：只收字符串值，数组与嵌套不当键值" {
  assert_eq(
    @error.json_string_pairs(
      "{\"a\":\"b\",\"c\":3,\"d\":{\"e\":\"f\"},\"g\":true}",
    ),
    [("a", "b")],
  )
  assert_eq(@error.json_string_pairs("{}"), [])
  // 数组不是一张键值表：喂进来一条都不收，免得把 `["x","y"]` 读成一对假键值
  assert_eq(@error.json_string_pairs("[\"x\",\"y\"]"), [])
  assert_eq(@error.json_string_pairs(""), [])
  // 值里带冒号与转义：按 JSON 的写法读，不按分隔符猜
  assert_eq(@error.json_string_pairs("{\"k\":\"a:b\",\"n\":\"q\\\\\"\"}"), [
    ("k", "a:b"),
    ("n", "q\\"),
  ])
}

///|
test "对象族 #3 嵌套对象切片：只认对象档，数组与标量各归各" {
  let text = stat_sample()
  assert_eq(
    @error.json_object_field(text, "x-qn-meta"),
    Some("{\"case\":\"qiniu\",\"kind\":\"adapter\"}"),
  )
  // 标量与不存在的键都不是对象
  assert_eq(@error.json_object_field(text, "fsize"), None)
  assert_eq(@error.json_object_field(text, "nope"), None)
  // 值里没有的嵌套对象也不能被"数组那一族"顺手抢走
  assert_eq(@error.json_objects(text, "x-qn-meta"), [])
  // 串里的花括号不算层
  assert_eq(
    @error.json_object_field("{\"a\":{\"k\":\"}{}\"},\"b\":1}", "a"),
    Some("{\"k\":\"}{}\"}"),
  )
}
