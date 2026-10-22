///|
test "bucket create path uses the official mkbucketv3 shape" {
  assert_eq(create_bucket_path("demo", "z2"), "/mkbucketv3/demo/region/z2")
}
