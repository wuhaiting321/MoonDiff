// 确定性随机源。
//
// 不用宿主 `@random`：它在一部分后端上由系统熵初始化，
// 同一 seed 在不同后端会给出不同序列，语料也就无法复现。
// 这里用 xorshift64*，纯整数运算，四个后端逐位一致。

///|
/// 确定性伪随机源。
pub struct Rng {
  mut state : Int64
}

///|
/// 用 32 位种子初始化（零种子会被抬到常量，避免退化到全零状态）。
pub fn Rng::new(seed : Int32) -> Rng {
  let s = seed.to_int64()
  { state: if s == 0L { 0x9E3779B97F4A7C15L } else { s }, }
}

///|
/// 下一个 64 位随机数（xorshift64*）。
pub fn Rng::next(self : Rng) -> Int64 {
  let mut x = self.state
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  self.state = x
  x * 2685821657736338717L
}

///|
/// `[0, bound)` 区间内的随机整数。`bound <= 0` 时返回 0。
pub fn Rng::below(self : Rng, bound : Int32) -> Int32 {
  if bound <= 0 {
    return 0
  }
  let v = self.next()
  let m = v % bound.to_int64()
  let mm = if m < 0 { -m } else { m }
  mm.to_int()
}

///|
/// 以 `pct`（0–100）的概率返回真。
pub fn Rng::chance(self : Rng, pct : Int32) -> Bool {
  self.below(100) < pct
}

///|
/// 从数组里随机取一个元素；空数组返回 `None`。
pub fn[T] Rng::pick(self : Rng, items : Array[T]) -> T? {
  if items.length() == 0 {
    None
  } else {
    Some(items[self.below(items.length())])
  }
}
