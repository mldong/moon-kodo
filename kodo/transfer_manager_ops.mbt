///|
/// Kodo 的传输管理器：小于等于 `threshold` 走表单上传，否则走 V2 分片并透传
/// `progress~`。Kodo 的续传本就在 `begin_multipart`/`resume_multipart` 这一层，
/// 管理器不另存 uploadId（会话由调用方按需持有）。
pub struct TransferManager {
  client : Client
  bucket : String
  block_size : Int32
  threshold : Int32
  progress : ((Int32, Int32) -> Unit)?
}

///|
pub fn TransferManager::new(
  client : Client,
  bucket : String,
  block_size~ : Int32 = 4194304,
  threshold~ : Int32 = 4194304,
  progress~ : ((Int32, Int32) -> Unit)? = None,
) -> TransferManager {
  TransferManager::{ client, bucket, block_size, threshold, progress, }
}

///|
pub async fn TransferManager::upload(
  self : TransferManager,
  key : String,
  data : Bytes,
) -> FormUploadResult raise @error.KodoError {
  if data.length() <= self.threshold {
    self.client.put_bytes(key, data)
  } else {
    self.client.put_bytes_multipart(
      key,
      data,
      block_size=self.block_size,
      progress=self.progress,
    )
  }
}

///|
/// 下载：签一条私有下载 URL 再取回内容（Kodo 没有独立的下载 API）。
pub async fn TransferManager::download(
  self : TransferManager,
  key : String,
  base_url~ : String = "",
  expires~ : Int64 = 3600,
) -> Bytes raise @error.KodoError {
  // 下载 URL 要用桶绑定的域名。调用方可显式给 `base_url~`（CI 里绑域名常解析不到）；
  // 不给就从 UC 取第一条，取不到就明确拒。
  let base = if !base_url.is_empty() {
    let trimmed = if base_url.has_suffix("/") {
      base_url[0:base_url.length() - 1].to_owned()
    } else {
      base_url
    }
    trimmed + "/" + key
  } else {
    let domains = self.client.domains(bucket=Some(self.bucket))
    if domains.names.length() == 0 {
      raise @error.BadParam("bucket has no bound download domain")
    }
    "https://" + domains.names[0] + "/" + key
  }
  let url = self.client.private_download_url(base, expires~)
  let response = self.client.open_url(url)
  let body = read_all(response.body)
  response.body.close()
  body
}

///|
/// 跨桶搬运：服务端 `copy`（`/copy/<源>/<目标>/force/true`），同桶改目标键也走这一条。
pub async fn TransferManager::copy_to(
  self : TransferManager,
  source_key : String,
  dest_bucket : String,
  dest_key : String,
) -> Unit raise @error.KodoError {
  self.client.copy(
    source_key,
    dest_key,
    from_bucket=Some(self.bucket),
    to_bucket=Some(dest_bucket),
    force=true,
  )
}
