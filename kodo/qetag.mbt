///|
/// 七牛 qetag：4 MiB 分块；单块是 `sha1(0x16 + data)`，多块是
/// `sha1(0x96 + concat(sha1(block)))`，最后 URL-safe Base64（带填充）。
pub fn qetag(data : Bytes) -> String {
  let block_size = 4194304
  let length = data.length()
  if length == 0 {
    return @auth.urlsafe_b64(Bytes::from_array([b'\x16']))
  }
  if length <= block_size {
    let digest = @digest.sha1_of_bytes(data)
    let out : Array[Byte] = [b'\x16']
    out.append(digest.to_array())
    @auth.urlsafe_b64(Bytes::from_array(out))
  } else {
    let block_hashes : Array[Byte] = []
    let mut offset = 0
    while offset < length {
      let end = if offset + block_size < length {
        offset + block_size
      } else {
        length
      }
      let block = data[offset:end].to_owned()
      block_hashes.append(@digest.sha1_of_bytes(block).to_array())
      offset = end
    }
    let digest = @digest.sha1_of_bytes(Bytes::from_array(block_hashes))
    let out : Array[Byte] = [b'\x96']
    out.append(digest.to_array())
    @auth.urlsafe_b64(Bytes::from_array(out))
  }
}
