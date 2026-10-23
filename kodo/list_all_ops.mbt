///|
/// 翻页器：按 `marker`/`is_eof` 把 [Client::list_files] 翻到底。
/// `max_pages` 防跑飞（默认 1000 页）；`body` 留最后一页原文。
pub async fn Client::list_all_files(
  self : Client,
  prefix~ : String? = None,
  delimiter~ : String? = None,
  limit~ : Int32? = None,
  max_pages~ : Int32 = 1000,
) -> FileListing raise @error.KodoError {
  let items : Array[FileInfo] = []
  let prefixes : Array[String] = []
  let mut marker : String? = None
  let mut pages = 0
  let mut body = ""
  let mut last_eof = true
  let mut next_marker : String? = None
  while pages < max_pages {
    let page = self.list_files(prefix~, marker~, delimiter~, limit~)
    items.append(page.items)
    prefixes.append(page.common_prefixes)
    body = page.body
    last_eof = page.is_eof
    next_marker = page.marker
    pages = pages + 1
    if page.is_eof {
      break
    }
    // Kodo 的 marker 是服务端给的不透明游标（实测是 base64 JSON），不是键；
    // 缺 marker 就是到底（`is_eof` 在末页可能仍是 false，2026-10-22 真桶读数）。
    match page.marker {
      Some(value) => if value.is_empty() { break } else { marker = Some(value) }
      None => break
    }
  }
  FileListing::{
    items,
    common_prefixes: prefixes,
    marker: next_marker,
    is_eof: last_eof,
    body,
  }
}
