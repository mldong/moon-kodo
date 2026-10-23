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
