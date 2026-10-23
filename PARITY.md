# moon-kodo · 官方 Kodo SDK 对标台账

> 协议基线：[Kodo API 概览](https://developer.qiniu.com/kodo/3939/overview-of-the-api)
> 参考实现：`qiniu/java-sdk@v7.19.0`（2025-06-20）；交叉核对 Python `v7.18.2`（2026-07-21）、Go `storagev2` 64 个 endpoint 包
> 本仓版本：`mldong/moon-kodo@0.15.0`
> 当前公开面：51 个 `Client::` 方法（0.14.0），另有令牌/签名/区域探测件
> 状态：规划骨架；现有行先记 `已实现`，真桶证据待按基线逐行复核

## 1. 当前公开面

| ID | 能力族 | 官方操作 | 我们的方法 | 档 | 状态 | 证据/备注 |
|---|---|---|---|---|---|---|
| KODO-UPL-001 | 表单上传 | `UploadManager.put` / 表单 POST | `put_bytes` | P0 | 真桶已验证 | `kodo/live_kodo_test.mbt`（2026-10-22 真桶绿）；策略经 `policy~` 透传 |
| KODO-MPU-001 | 分片 V2 | `initiateMultipartUpload` / `uploadPart` / `complete` / `abort` / `listParts` | `begin_multipart` `upload_part` `list_parts` `complete_multipart` `abort_multipart` `resume_multipart` | P0 | 真桶已验证 | `kodo/live_multipart_test.mbt`（2026-10-22 真桶绿） |
| KODO-OBJ-001 | 对象基础 | `stat` / `delete` / `copy` / `move` / `changeMime` | `stat` `delete` `copy` `move_object` `change_mime` | P0 | 真桶已验证 | `kodo/live_object_test.mbt`（2026-10-22 真桶绿） |
| KODO-OBJ-002 | 列举 V1 | `BucketManager.listFiles`（rsf `/list`） | `list_files` | P0 | 真桶已验证 | `kodo/live_object_test.mbt`（2026-10-22 真桶绿） |
| KODO-OBJ-003 | 抓取 | `fetch` | `fetch` | P0 | 真桶已验证 | `kodo/live_object_test.mbt`（2026-10-22 真桶绿） |
| KODO-OBJ-004 | 批量操作 | `BucketManager.batch`（delete/stat/copy/move/chgm/chtype/chstatus/deleteAfterDays/restoreAr） | `batch` | P0 | 真桶已验证 | `kodo/batch_ops_wbtest.mbt`、`kodo/live_batch_test.mbt`（2026-10-22 真桶绿） |
| KODO-HASH-001 | 内容哈希 | `qetag` | `qetag`（自由函数） | P0 | 真桶已验证 | `kodo/qetag_wbtest.mbt`、`kodo/live_qetag_test.mbt`（2026-10-22 与 stat.hash 逐字相同） |
| KODO-OBJ-005 | 对象状态 | `chstatus` | `change_status` | P0 | 真桶已验证 | `kodo/resource_ops_wbtest.mbt`、`kodo/live_resource_test.mbt`（2026-10-22 真桶绿） |
| KODO-OBJ-006 | 存储类型 | `chtype` | `change_type` | P0 | 真桶已验证 | `kodo/resource_ops_wbtest.mbt`、`kodo/live_resource_test.mbt`（2026-10-22 真桶绿） |
| KODO-OBJ-008 | 归档恢复 | `restoreAr` | `restore_archive` | P1 | 已实现 | `kodo/resource_ops_wbtest.mbt`；真桶档待补（需先归档再解冻） |
| KODO-OBJ-009 | 对象生命周期 | `deleteAfterDays` | `delete_after_days` | P1 | 真桶已验证 | `kodo/resource_ops_wbtest.mbt`、`kodo/live_resource_test.mbt`（2026-10-22 真桶绿） |
| KODO-DL-001 | 私有下载 | `DownloadUrl.buildURL` / `privateDownloadUrl` | `private_download_url` `open_url` | P0 | 真桶已验证 | `kodo/live_object_test.mbt`（2026-10-22 真桶绿） |
| KODO-REG-001 | 区域探测 | `Region.autoRegion` / UC `v4/query` | `query_region` `region_from_probe` | P2 | 真桶已验证 | `kodo/region_probe.mbt`（2026-10-22 真桶绿） |
| KODO-UP-001 | 字节体上传 | `UploadManager.put` 字节/流入口 | `put_bytes` `put_bytes_multipart` | P0 | 真桶已验证 | `kodo/live_multipart_test.mbt`（2026-10-22 真桶绿） |

## 2. 缺口台账

### P0 · 数据面核心

| ID | 官方操作 | 我们的方法 | 状态 | 备注 |
|---|---|---|---|---|
| KODO-UPL-002 | 表单上传完整策略：returnBody/callback/saveKey/fsizeLimit/mimeLimit/detectMime/fileType/trafficLimit | `put_bytes` / `begin_multipart` / `resume_multipart` 的 `policy~` 透传 | 已实现 | 策略串走 `UploadPolicy` 白名单；表单字段由 `extra_fields` 给；高层便捷封装未做 |
| KODO-LST-002 | List V2（流式，`/v2/list`） | — | 不纳入 | 官方 `listV2`/`listFilesV2` 已标 `@Deprecated`，推荐 V1 `/list`；本仓走的就是 V1 |
| KODO-MPU-002 | 分片 V1（`mkblk`/`bput`/`mkfile`） | — | 不纳入 | 官方 Java 7.19 基线已无 V1 方法（仅 V2） |
| KODO-OBJ-007 | 条件请求 / 校验和 | — | 不纳入 | 官方 Java 基线无对应请求头/入口 |

### P1 · 控制面与厂商数据面扩展

| ID | 能力/官方操作 | 我们的方法 | 档 | 状态 | 证据/备注 |
|---|---|---|---|---|---|
| KODO-BKT-001 | `buckets` / `mkbucketv3` / `drop` | `buckets` `create_bucket` `delete_bucket` | P1 | 部分真桶 | `kodo/bucket_admin_ops_wbtest.mbt`、`kodo/live_resource_test.mbt`（buckets 2026-10-22 真桶绿；建/删桶未跑） |
| KODO-BKT-002 | 域名列表 | `domains` | P1 | 真桶已验证 | `kodo/bucket_domain_ops_wbtest.mbt`、`kodo/live_resource_test.mbt`（2026-10-22 真桶返回 1 个域名） |
| KODO-BKT-007 | `getBucketInfo` | `bucket_info` | P1 | 真桶已验证 | `kodo/bucket_config_ops_wbtest.mbt`、`kodo/live_resource_test.mbt`（2026-10-22 真桶 region=z2/private=0） |
| KODO-BKT-003 | `private`（桶访问权限） | `set_bucket_private` | P1 | 部分真桶 | 写只落离线件（一开即整桶鉴权，绝不在配置桶真写） |
| KODO-BKT-008 | CORS | `cors_rules` `set_cors_rules` | P1 | 部分真桶 | 读 2026-10-22 真桶绿（空规则）；写只落离线件 |
| KODO-BKT-009 | 生命周期 | `lifecycle_rules` `add_lifecycle_rule` `update_lifecycle_rule` `delete_lifecycle_rule` | P1 | 部分真桶 | 读真桶返回 1 条（name=moon、prefix=moonfs-、delete_after_days=1）；写只落离线件 |
| KODO-BKT-010 | 配额 | `bucket_quota` `set_bucket_quota` | P1 | 部分真桶 | 读真桶 size=-1（无限额）；写只落离线件 |
| KODO-BKT-011 | 事件通知 | `event_rules` `add_event_rule` `update_event_rule` `delete_event_rule` | P1 | 部分真桶 | 读真桶 0 条；写侧只落离线件 |
| KODO-BKT-004 | referer 防盗链 | `set_refer_anti_leech` | P1 | 部分真桶 | 官方只有写口；离线件已落 |
| KODO-BKT-005 | 桶标签 tagging | — | P1 | 不纳入 | 官方 Java 基线无桶标签方法 |
| KODO-BKT-006 | image / indexPage / accessMode / maxAge | `set_bucket_image` `unset_bucket_image` `set_index_page` `set_bucket_access_style` `set_bucket_max_age` | P1 | 部分真桶 | 全部只有离线条；remark/style 官方 Java 基线无对应方法，不纳入 |
| KODO-OBJ-010 | asyncFetch / checkAsyncFetch / prefetch | `async_fetch` `check_async_fetch` `prefetch` | P1 | 部分真桶 | 三件都会触发服务端真实动作，只落离线件；真桶需显式开关 |
| KODO-OBJ-011 | `avinfo` | — | P1 | 不纳入 | 官方 Java 基线无 avinfo 方法 |

### P2 · 便利/安全层

| ID | 能力 | 状态 | 备注 |
|---|---|---|---|
| KODO-SEC-001 | UploadToken 完整策略面（insertOnly/callback/persistentOps/...） | 未开始 | 令牌已有基础 scope/deadline |
| KODO-SEC-002 | 回调校验（`isValidCallback`） | 未开始 | 官方已标废弃，按基线确认是否纳入 |
| KODO-CNV-001 | 断点记录 / 进度回调 / TransferManager | 未开始 | 高层 helper |
| KODO-CNV-002 | 重试策略 / 分页器 / 错误映射 | 部分实现 | `list_all_files` 翻页器真桶绿；`put_bytes_multipart` 已收 `progress~` 按片回调；断点续传未做 |

### P3 · 可选模块

| ID | 能力 | 状态 | 备注 |
|---|---|---|---|
| KODO-EXT-001 | pfop / prefop（Dora 持久化处理） | 未开始 | 独立模块，不属于 Kodo 核心 |
| KODO-EXT-002 | CDN 刷新/预取/日志/统计 | 未开始 | 独立产品线 |
| KODO-EXT-003 | 分享 / 统计 17 接口 | 未开始 | 独立产品线或增值 |

## 3. 不适用/边界

| 项 | 结论 | 理由 |
|---|---|---|
| 对象级 canned ACL | 不适用 | Kodo 协议无这一族；S3 兼容层也没有对象级 ACL |
| 版本控制 | 待确认 | 官方存储 SDK 基线未见版本控制方法；S3 兼容层明示不支持 `x-amz-version-id` |
| SSE / Object Lock | 待确认 | S3 兼容层公共头明示不支持；原生面按基线复核 |
| STS 临时凭据 | 不纳入原生核心 | 原生走 UploadToken；S3 兼容层 STS 与原生语义不同，单列 |
| 域名绑定 | 不适用 SDK 核心 | 官方 Python SDK 文档明确绑定域名等管理操作已移出 SDK |

## 4. 下一批

1. 现有约 22 法真桶已复核（2026-10-22）。
2. `batch`、`chstatus`、`chtype`、`deleteAfterDays`、`qetag`、桶管理三件、域名列表已真桶绿；`restoreAr` 与分片 V1（兼容档）继续。
3. 桶配置读侧（bucketInfo/CORS/生命周期/配额/事件）2026-10-22 真桶绿；写侧只落离线件，等独立测试桶再验。
4. List V2 官方已 `@Deprecated`，不纳入；pfop/CDN 单独立项，不阻塞核心。
