///|
test "async fetch body carries url, bucket and key" {
  assert_eq(
    async_fetch_body("https://src.example/a.jpg", "blog", "img/a.jpg"),
    "{\"url\":\"https://src.example/a.jpg\",\"bucket\":\"blog\",\"key\":\"img/a.jpg\"}",
  )
  assert_eq(
    async_fetch_body(
      "https://src.example/a.jpg",
      "blog",
      "img/a.jpg",
      md5="m",
      etag="e",
    ),
    "{\"url\":\"https://src.example/a.jpg\",\"bucket\":\"blog\",\"key\":\"img/a.jpg\"," +
    "\"md5\":\"m\",\"etag\":\"e\"}",
  )
}

///|
test "prefetch path uses the encoded entry" {
  assert_eq(
    prefetch_path("blog", "img/a.jpg"),
    "/prefetch/YmxvZzppbWcvYS5qcGc=",
  )
}
