# mldong/moon-kodo

七牛对象存储（Kodo）原生协议的客户端：上传令牌、`QBox` / `Qiniu` 两族请求签名、私有下载
URL、区域端点探测、表单上传与分块上传第二代，以及 `rs` / `rsf` 上的对象族。公开面对标官方
Java SDK（`Auth` / `Configuration` / `Region` / `UploadManager` / `BucketManager`），
命名沿用官方那套词汇。

它不做业务编排：桶是配置项，不是能力位；也不做建桶删桶——那是控制台的事。

## 最小用法

```moonbit
fn block_size_reading(size : Int32, last~ : Bool) -> String {
  @kodo.check_block_size(size, last~) catch {
    _ => return "refused"
  }
  "ok"
}

test "签名、URL 与边界都在本地算得出，不依赖网络" {
  let auth = @kodoauth.Auth::new("ak-example", "sk-example")
  let token = auth.upload_token("demo-bucket", key=Some("2026/10/note.txt"))
  let decoded = @kodoauth.decode_upload_token(token)
  assert_eq(decoded.0, "ak-example")
  assert_true(!decoded.1.is_empty())
  // 私有下载 URL 的次序承重：先把 `e=<过期时刻>` 拼上，对整串签，最后才拼 `&token=`
  let url = auth.private_download_url(
    "https://cdn.example.invalid/2026/10/note.txt",
    expires=120,
  )
  assert_true(url.has_prefix("https://cdn.example.invalid/2026/10/note.txt?e="))
  assert_true(url.contains("&token=ak-example:"))
  // 分块上传路径里的 key 段是 URL-safe Base64（带填充），与 rs 系的 entry 不是同一串
  assert_eq(@kodo.v2_key_segment("2026/10/note.txt"), "MjAyNi8xMC9ub3RlLnR4dA==")
  assert_eq(
    @kodo.encoded_entry("demo-bucket", Some("2026/10/note.txt")),
    "ZGVtby1idWNrZXQ6MjAyNi8xMC9ub3RlLnR4dA==",
  )
  // 除最后一片外每片必须满 1MB：这一档在任何请求发出之前就拒掉，末片不限长
  assert_eq(block_size_reading(1024, last=false), "refused")
  assert_eq(block_size_reading(1048576, last=false), "ok")
  assert_eq(block_size_reading(1, last=true), "ok")
}
```

## 装法

```bash
moon add mldong/moon-kodo
```

## 用之前要知道的几件事

- **端点靠探测**：`@kodo.query_region(transport, access_key, bucket)` 打官方 UC 的
  `v4/query`，把回包里的区域与主机表换成 `@kodoconfig.Region`；区域常量表也在
  `@kodoconfig.Region::with_region_id("z0")` 这一族里，两种给法都不把某台主机名写死。
- **上传令牌不是预签名 URL**：令牌是给表单与分块接口换一次上传机会的凭据串
  （`Authorization: UpToken …`），私有下载 URL 才是能交给无凭据客户端的那条链接。
- **块级校验是开关，不是默认**：`check_crc` 默认关；开着时表单侧带整份 crc32，
  分块侧逐片比服务端回的 md5，不等就在合并之前抛。
- **对象不存在是 612**：`stat` 抛出的 `Service` 里状态码 612 表示"没有这个对象"，
  `delete` 对同一档返回 `false`。
- 回包里的数字字段一律不走 `derive(@json.FromJson)`：那件 derive 读不进 JSON 数字，
  而 `fsize` / `putTime` / `partNumber` 恰恰都是数字。

## 开发进度

排法按存储侧那条端口（18 法）需要什么。**已实现**＝有公开件且真桶跑过；
**部分实现**＝子集真桶跑过，其余只有离线件；**待开发**＝这条线在公开面里零命中；
**不适用**＝协议里没有这一族，不是还没做。

| 存储侧要的那一格 | 本 SDK 的件 | 状态 |
|---|---|---|
| 上传（小文件与字节体） | `upload_form` `put_bytes` `io_post` | 已实现 |
| 手动分片五步（第二代 `/blocks`） | 六个件，见下注 | 已实现 |
| 存在 / 取回 / 删除 | `stat` `open_url` `delete` | 已实现 |
| 同平台复制 / 移动 | `copy` `move_object` | 已实现 |
| 单层列举 | `list_files`（`rsf` 的 `/list`；官方已把 `/v2/list` 标废弃） | 已实现 |
| 预签名下载 | `Auth::private_download_url`（官方只签 GET） | 已实现 |
| 前端直传的凭据 | `Auth::upload_token`——PUT 那一格由令牌承担，不是预签名 URL | 不适用 |
| 用户元数据 | `stat_user_metadata` ＋ `change_mime` | 已实现 |
| 端点与区域 | `query_region` `region_from_probe` | 已实现 |
| 对象级 canned ACL | Kodo 协议无这一族 | 不适用 |
| 批量操作 | `batch`（delete/stat/copy/move/chgm/chtype/chstatus/deleteAfterDays/restoreAr） | 已实现 |
| 资源管理 | `change_status` `change_type` `delete_after_days` `restore_archive` | 部分实现（解冻仅离线） |
| 内容哈希 | `qetag`（自由函数） | 已实现 |
| 桶管理 | `buckets` `create_bucket` `delete_bucket` | 部分实现（建/删未跑真桶） |
| 域名列表 | `domains` | 已实现 |
| 桶配置读 | `bucket_info` `cors_rules` `lifecycle_rules` `bucket_quota` `event_rules` | 已实现 |
| 桶配置写 | `set_cors_rules` `set_bucket_quota` `add/update/delete_lifecycle_rule`、防盗链／maxAge／私有属性／原图保护／首页／镜像回源／事件通知 | 部分实现（只有离线件） |
| 分块上传第一代（`mkfile`） | 无对应件 | 待开发 |
| `fetch` 拉取的任务态轮询 | 有 `fetch_path` 请求件，无 pfop/jobctrl 那一圈 | 待开发 |
| 图片样式／原图保护／referer | 无对应件 | 待开发 |

分片那一族的六个件：`begin_multipart`、`upload_part`、`list_parts`、`complete_multipart`、
`abort_multipart`，另加 `resume_multipart`——续传是拿既有 `uploadId` 重新组一个会话（上传令牌按 key
现签），不重开分块。

完整对标台账（官方基线、P0–P3、逐项证据）：[PARITY.md](PARITY.md)。

## 它服务于谁

这个仓是 [`mldong/moon-file-storage`](https://github.com/mldong/moon-file-storage) 的七牛载体：
存储侧的 `Platform` 端口由 `mldong/moon-file-storage-qiniu` 那层接上去，契约正文在真桶上跑。
七牛的 **S3 兼容端点**是另一条接入路径，不归这个仓，两边结论互不背书。

## 许可

Apache-2.0。
