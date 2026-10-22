///|
test "storage type codes follow the official enum order" {
  assert_eq(StorageType::Common.code(), 0)
  assert_eq(StorageType::Infrequency.code(), 1)
  assert_eq(StorageType::Archive.code(), 2)
  assert_eq(StorageType::DeepArchive.code(), 3)
  assert_eq(StorageType::ArchiveIR.code(), 4)
  assert_eq(StorageType::IntelligentTiering.code(), 5)
}

///|
test "resource paths carry the encoded entry and code" {
  let entry = encoded_entry("bucket", Some("a/b.txt"))
  assert_eq(
    change_status_path("bucket", "a/b.txt", ObjectStatus::Disabled),
    "/chstatus/" + entry + "/status/1",
  )
  assert_eq(
    change_type_path("bucket", "a/b.txt", StorageType::Archive),
    "/chtype/" + entry + "/type/2",
  )
  assert_eq(
    delete_after_days_path("bucket", "a/b.txt", 30),
    "/deleteAfterDays/" + entry + "/30",
  )
  assert_eq(
    restore_archive_path("bucket", "a/b.txt", 7),
    "/restoreAr/" + entry + "/freezeAfterDays/7",
  )
}

///|
test "restore archive rejects freeze days outside 1..7" {
  let mut rejected = false
  check_freeze_days(0) catch {
    @error.BadParam(_) => rejected = true
    _ => ()
  }
  assert_true(rejected)
}
