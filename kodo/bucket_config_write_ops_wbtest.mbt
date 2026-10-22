///|
test "referer and image paths follow the official shapes" {
  assert_eq(
    image_path("blog", "https://origin.example", ""),
    "/image/blog/from/aHR0cHM6Ly9vcmlnaW4uZXhhbXBsZQ==",
  )
  assert_eq(
    image_path("blog", "https://origin.example", "cdn.example"),
    "/image/blog/from/aHR0cHM6Ly9vcmlnaW4uZXhhbXBsZQ==/host/Y2RuLmV4YW1wbGU=",
  )
}

///|
test "event rule query repeats event and callbackURL" {
  let rule = EventRule::{
    name: "notify",
    prefix: "img/",
    suffix: ".jpg",
    events: ["put", "delete"],
    callback_urls: ["https://cb.example/a", "https://cb.example/b"],
    access_key: "ak",
    host: "cb.example",
  }
  assert_eq(
    event_rule_query(rule),
    "name=notify&prefix=img%2F&suffix=.jpg&event=put&event=delete" +
    "&callbackURL=https%3A%2F%2Fcb.example%2Fa&callbackURL=https%3A%2F%2Fcb.example%2Fb" +
    "&access_key=ak&host=cb.example",
  )
}
