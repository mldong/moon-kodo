///|
/// 私有下载 URL。对标 `privateDownloadUrlWithDeadline(baseUrl, deadline)`。
///
/// 次序承重：**先把 `e=<deadline>` 拼上，再对整串签，最后拼 `&token=`**。
/// 先签后拼就是给一个不存在的 URL 签名——CDN 校验的是带 `e=` 的那一条。
pub fn Auth::private_download_url_with_deadline(
  self : Auth,
  base_url : String,
  deadline : Int64,
) -> String {
  let head = base_url +
    (if base_url.contains("?") { "&e=" } else { "?e=" }) +
    deadline.to_string()
  head + "&token=" + self.sign(head)
}

///|
/// `privateDownloadUrl(baseUrl, expires)`：过期时刻由当前时钟算出来。
/// 用例不许依赖它——要确定性就用上一条显式传 `deadline`。
pub fn Auth::private_download_url(
  self : Auth,
  base_url : String,
  expires~ : Int64 = 3600,
) -> String {
  let deadline = @date.now_millis() / 1000 + expires
  self.private_download_url_with_deadline(base_url, deadline)
}
