///|
/// 对象资源管理四件：启用/禁用、存储类型、按天删除、归档解冻。
/// 路径逐条照官方 Java SDK `BucketManager`（2026-10-22 现读：`chstatus`、
/// `chtype`、`deleteAfterDays`、`restoreAr`），签名统一走现有 `rs_post`。

///|
/// 对象的启用状态。官方 `chstatus` 的路径段是 `0`／`1`。
pub(all) enum ObjectStatus {
  Enabled
  Disabled
}

///|
pub fn ObjectStatus::code(self : ObjectStatus) -> Int32 {
  match self {
    Enabled => 0
    Disabled => 1
  }
}

///|
/// Kodo 的存储类型，取值顺序照官方 `StorageType` enum 的 ordinal。
pub(all) enum StorageType {
  Common
  Infrequency
  Archive
  DeepArchive
  ArchiveIR
  IntelligentTiering
}

///|
pub fn StorageType::code(self : StorageType) -> Int32 {
  match self {
    Common => 0
    Infrequency => 1
    Archive => 2
    DeepArchive => 3
    ArchiveIR => 4
    IntelligentTiering => 5
  }
}

///|
/// `POST /chstatus/<entry>/status/<0|1>`。
pub async fn Client::change_status(
  self : Client,
  key : String,
  status : ObjectStatus,
) -> Unit raise @error.KodoError {
  let _ = self.rs_post(change_status_path(self.bucket, key, status))
}

///|
/// `POST /chtype/<entry>/type/<ordinal>`。
pub async fn Client::change_type(
  self : Client,
  key : String,
  storage_type : StorageType,
) -> Unit raise @error.KodoError {
  let _ = self.rs_post(change_type_path(self.bucket, key, storage_type))
}

///|
/// `POST /deleteAfterDays/<entry>/<days>`。`days=0` 表示取消按天删除，按官方语义原样发。
pub async fn Client::delete_after_days(
  self : Client,
  key : String,
  days : Int32,
) -> Unit raise @error.KodoError {
  if days < 0 {
    raise @error.BadParam("delete_after_days needs a non-negative day count")
  }
  let _ = self.rs_post(delete_after_days_path(self.bucket, key, days))
}

///|
/// `POST /restoreAr/<entry>/freezeAfterDays/<1..7>`。解冻有效时长按官方范围在本地先拒。
pub async fn Client::restore_archive(
  self : Client,
  key : String,
  freeze_after_days : Int32,
) -> Unit raise @error.KodoError {
  check_freeze_days(freeze_after_days)
  let _ = self.rs_post(
    restore_archive_path(self.bucket, key, freeze_after_days),
  )
}

///|
fn check_freeze_days(freeze_after_days : Int32) -> Unit raise @error.KodoError {
  if freeze_after_days < 1 || freeze_after_days > 7 {
    raise @error.BadParam(
      "restore_archive freeze_after_days must be within 1..7, got " +
      freeze_after_days.to_string(),
    )
  }
}

///|
fn change_status_path(
  bucket : String,
  key : String,
  status : ObjectStatus,
) -> String {
  "/chstatus/" +
  encoded_entry(bucket, Some(key)) +
  "/status/" +
  status.code().to_string()
}

///|
fn change_type_path(
  bucket : String,
  key : String,
  storage_type : StorageType,
) -> String {
  "/chtype/" +
  encoded_entry(bucket, Some(key)) +
  "/type/" +
  storage_type.code().to_string()
}

///|
fn delete_after_days_path(
  bucket : String,
  key : String,
  days : Int32,
) -> String {
  "/deleteAfterDays/" +
  encoded_entry(bucket, Some(key)) +
  "/" +
  days.to_string()
}

///|
fn restore_archive_path(
  bucket : String,
  key : String,
  freeze_after_days : Int32,
) -> String {
  "/restoreAr/" +
  encoded_entry(bucket, Some(key)) +
  "/freezeAfterDays/" +
  freeze_after_days.to_string()
}
