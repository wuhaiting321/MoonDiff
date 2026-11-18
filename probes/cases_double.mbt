// Double：IEEE 754 有外部标准兜底；格式化与解析的差异会直接暴露给用户。

///|
fn case_double_thirds() -> Unit {
  emit("double-thirds", hex16((1.0 / 3.0).reinterpret_as_int64()))
}

///|
/// 大指数的文本形式：`1e+21` 与 `1e21` 是两种常见实现。
fn case_double_fmt_big() -> Unit {
  emit("double-fmt-big", 1.0e21.to_string())
}

///|
fn case_double_fmt_small() -> Unit {
  emit("double-fmt-small", 1.0e-7.to_string())
}

///|
fn case_double_round_trip() -> Unit {
  let a = 0.1 + 0.2
  emit("double-round-trip", hex16(a.reinterpret_as_int64()) + " " + a.to_string())
}

///|
/// 最小次正规数：位模式下必须恰好是 1。
fn case_double_subnormal() -> Unit {
  emit("double-subnormal", hex16(@double.min_positive.reinterpret_as_int64()))
}

///|
/// 舍入模式：2.5 的 `round` 是半值远离零还是银行家舍入，会在这里现形。
fn case_double_rounding() -> Unit {
  let a = 2.5
  let b = -2.5
  emit("double-rounding", a.round().to_string() + " " + b.round().to_string())
}

///|
/// 溢出到无穷：位模式是 7FF0000000000000。
fn case_double_overflow() -> Unit {
  let a = 1.0e308 * 10.0
  emit("double-overflow", hex16(a.reinterpret_as_int64()))
}

///|
/// 常量折叠路径下的 NaN 符号位（已知差异：wasm 为 FFF8…，js 为 7FF8…）。
fn case_double_nan_literal() -> Unit {
  emit("double-nan-literal", hex16((0.0 / 0.0).reinterpret_as_int64()))
}

///|
/// 运行期路径下的 NaN 符号位。除数由 argv 长度推出，编译器无法折叠成常量，
/// 用来证明上面的差异只出现在折叠路径上。
fn case_double_nan_runtime() -> Unit {
  let n = @env.args().length().to_double()
  let z = n - n
  emit("double-nan-runtime", hex16((0.0 / z).reinterpret_as_int64()))
}

///|
/// 浮点转整数：越界输入取饱和值还是回绕，两种实现都见过。
fn case_double_to_int() -> Unit {
  let a = 2.9
  let b = -1.9
  let big = 1.0e30
  emit(
    "double-to-int",
    a.to_int().to_string() + " " + b.to_int().to_string() + " " + big.to_int().to_string(),
  )
}
