///|
/// `uploadToken(bucket, key, expires, policy, strict)`：**令牌不是预签名 URL**（卡 §7-2）。
/// 产出的是"给客户端换一次上传机会"的凭据串，形状 `accessKey:签名:策略JSON 的 base64`，
/// 用在 upHost 的表单/分块接口上；私有效 URL 走 `private_download_url`。
pub fn Auth::upload_token(
  self : Auth,
  bucket : String,
  key~ : String? = None,
  expires~ : Int64 = 3600,
  policy~ : UploadPolicy? = None,
  strict~ : Bool = true,
) -> String raise @error.KodoError {
  let deadline = @date.now_millis() / 1000 + expires
  self.upload_token_with_deadline(bucket, deadline, key~, policy~, strict~)
}

///|
/// `uploadTokenWithDeadline`：过期时刻显式传进来。用例与探针都用这一档，
/// 免得断言里藏着"跑的时候几点"。
pub fn Auth::upload_token_with_deadline(
  self : Auth,
  bucket : String,
  deadline : Int64,
  key~ : String? = None,
  policy~ : UploadPolicy? = None,
  strict~ : Bool = true,
) -> String raise @error.KodoError {
  if bucket.is_empty() {
    // 桶名是配置项，配空了要在这里停，而不是让服务端回一个 612 让人猜
    raise @error.BadParam("upload token needs a bucket name")
  }
  let body = match policy {
    None => UploadPolicy::new()
    Some(value) => value
  }
  self.sign_with_data(
    upload_policy_json(body, upload_scope(bucket, key), deadline, strict),
  )
}

///|
/// 把令牌串拆回三段：`access_key`、签名、解码后的策略 JSON。
/// 这是判据用的读口——KD1 要断言的是 scope/deadline 的**内容**，不是猜一串不透明的东西。
pub fn decode_upload_token(
  token : String,
) -> (String, String, String) raise @error.KodoError {
  match token.split_once(":") {
    None =>
      raise @error.BadParam(
        "token is not `accessKey:sign:encodedPolicy`: " + token,
      )
    Some((head, tail)) => {
      let access_key = head.to_owned()
      let rest = tail.to_owned()
      match rest.split_once(":") {
        None => raise @error.BadParam("token has no encoded policy: " + token)
        Some((sign, encoded)) =>
          (
            access_key,
            sign.to_owned(),
            @utf8.decode_lossy(urlsafe_b64_decode(encoded.to_owned())),
          )
      }
    }
  }
}
