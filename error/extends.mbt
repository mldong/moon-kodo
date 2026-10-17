///|
/// `derive(Eq)` 生成的是 trait 实现；要能用 `err == other` 这种写法，得把方法显式提升。
/// 本工具链上不做提升会报 `implicit_impl_as_method` 警告，而门禁是零警告口径。
pub extend ServiceError with Eq::{equal, not_equal}

///|
pub extend KodoError with Eq::{equal, not_equal}
