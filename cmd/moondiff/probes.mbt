// 手工构造的边界探针。
//
// 随机生成擅长发现“意料之外”的差异，但它不保证覆盖到你已经知道的最危险的点。
// 这里的每个探针都对应一类公认的实现陷阱（NaN 符号、除零、INT_MIN 取反、
// 位宽越界、代理对、次正规数），由固定指令序列构造，因此**永远可复现**。

///|
/// 探针名列表（顺序即报告顺序）。
fn probe_names() -> Array[String] {
  [
    "frem-zero", "fdiv-zero", "nan-arith", "cast-edge", "i64-overflow", "int-overflow",
    "str-unicode", "subnormal",
  ]
}

///|
/// 按名字构造探针程序；未知名字返回 `None`。
fn probe_program(name : String, profile : String) -> @spec.Program? {
  let ops : Array[@spec.Op] = []
  if name == "frem-zero" {
    // ±0 之间的取余：IEEE-754 规定结果是 NaN，但没有规定 NaN 的符号位
    ops.push(@spec.Op::const_f(0, 0x0000000000000000L))
    ops.push(@spec.Op::const_f(1, 0x8000000000000000L))
    ops.push(@spec.Op::binary(@spec.FRem, 2, 0, 1))
    ops.push(@spec.Op::binary(@spec.FRem, 3, 1, 0))
    ops.push(@spec.Op::const_f(4, 0x3FF0000000000000L))
    ops.push(@spec.Op::binary(@spec.FRem, 5, 4, 0))
    ops.push(@spec.Op::binary(@spec.FDiv, 6, 0, 1))
  } else if name == "fdiv-zero" {
    // 除零产生 ±inf / NaN，符号约定与 opcode 选择强相关
    ops.push(@spec.Op::const_f(0, 0x0000000000000000L))
    ops.push(@spec.Op::const_f(1, 0x3FF0000000000000L))
    ops.push(@spec.Op::const_f(2, 0xBFF0000000000000L))
    ops.push(@spec.Op::binary(@spec.FDiv, 3, 1, 0))
    ops.push(@spec.Op::binary(@spec.FDiv, 4, 2, 0))
    ops.push(@spec.Op::binary(@spec.FDiv, 5, 0, 0))
    ops.push(@spec.Op::binary(@spec.FDiv, 6, 1, 2))
  } else if name == "nan-arith" {
    // NaN 参与运算后符号位/载荷是否被保留
    ops.push(@spec.Op::const_f(0, 0x7FF8000000000001L))
    ops.push(@spec.Op::const_f(1, 0x7FF0000000000000L))
    ops.push(@spec.Op::const_f(2, 0x3FF0000000000000L))
    ops.push(@spec.Op::binary(@spec.FAdd, 3, 0, 2))
    ops.push(@spec.Op::binary(@spec.FMul, 4, 0, 1))
    ops.push(@spec.Op::unary(@spec.FAbs, 5, 0))
    ops.push(@spec.Op::unary(@spec.FNeg, 6, 0))
    ops.push(@spec.Op::binary(@spec.FMin, 7, 0, 2))
    ops.push(@spec.Op::binary(@spec.FMax, 8, 0, 2))
  } else if name == "cast-edge" {
    // 越界与 NaN 的整数转换：饱和、回绕、还是 trap？
    ops.push(@spec.Op::const_f(0, 0x7FF8000000000001L))
    ops.push(@spec.Op::const_f(1, 0x54B249AD2594C37DL))
    ops.push(@spec.Op::const_f(2, 0xD4B249AD2594C37DL))
    ops.push(@spec.Op::const_i(3, 2147483647))
    ops.push(@spec.Op::unary(@spec.F2I, 4, 0))
    ops.push(@spec.Op::unary(@spec.F2I, 5, 1))
    ops.push(@spec.Op::unary(@spec.F2I, 6, 2))
    ops.push(@spec.Op::unary(@spec.F2L, 7, 1))
    ops.push(@spec.Op::unary(@spec.I2F, 8, 3))
    ops.push(@spec.Op::unary(@spec.I2L, 9, 3))
  } else if name == "i64-overflow" {
    // INT64_MIN / -1 是唯一会溢出的有符号除法；移位量按 64 取模
    ops.push(@spec.Op::const_l(0, 0x8000000000000000L))
    ops.push(@spec.Op::const_l(1, -1L))
    ops.push(@spec.Op::const_l(2, 64L))
    ops.push(@spec.Op::const_l(3, 63L))
    ops.push(@spec.Op::binary(@spec.LMul, 4, 0, 1))
    ops.push(@spec.Op::binary(@spec.LShl, 5, 1, 2))
    ops.push(@spec.Op::binary(@spec.LShr, 6, 0, 3))
    ops.push(@spec.Op::binary(@spec.LAdd, 7, 2, 3))
  } else if name == "int-overflow" {
    // 32 位溢出与符号取模
    ops.push(@spec.Op::const_i(0, 2147483647))
    ops.push(@spec.Op::const_i(1, -2147483648))
    ops.push(@spec.Op::const_i(2, -1))
    ops.push(@spec.Op::const_i(3, 2))
    ops.push(@spec.Op::binary(@spec.IAdd, 4, 0, 2))
    ops.push(@spec.Op::binary(@spec.IMul, 5, 1, 2))
    ops.push(@spec.Op::binary(@spec.IDiv, 6, 1, 2))
    ops.push(@spec.Op::binary(@spec.IMod, 7, 1, 3))
    ops.push(@spec.Op::binary(@spec.IShl, 8, 0, 3))
  } else if name == "str-unicode" {
    // 码元数 vs 码点数、代理对拼接与比较
    ops.push(@spec.Op::const_s(0, "a中😀"))
    ops.push(@spec.Op::const_s(1, ""))
    ops.push(@spec.Op::const_s(2, "\u{0000}x"))
    ops.push(@spec.Op::unary(@spec.SLen, 3, 0))
    ops.push(@spec.Op::unary(@spec.SLen, 4, 1))
    ops.push(@spec.Op::unary(@spec.SLen, 5, 2))
    ops.push(@spec.Op::binary(@spec.SCat, 6, 0, 2))
    ops.push(@spec.Op::binary(@spec.SCmp, 7, 0, 1))
    ops.push(@spec.Op::binary(@spec.SCmp, 8, 2, 0))
  } else if name == "subnormal" {
    // 次正规数与最大值附近：格式化与运算都可能分叉
    ops.push(@spec.Op::const_f(0, 0x0000000000000001L))
    ops.push(@spec.Op::const_f(1, 0x0010000000000000L))
    ops.push(@spec.Op::const_f(2, 0x7FEFFFFFFFFFFFFFL))
    ops.push(@spec.Op::const_f(3, 0x4000000000000000L))
    ops.push(@spec.Op::binary(@spec.FMul, 4, 0, 3))
    ops.push(@spec.Op::binary(@spec.FDiv, 5, 1, 3))
    ops.push(@spec.Op::binary(@spec.FMul, 6, 2, 3))
    ops.push(@spec.Op::unary(@spec.FFloor, 7, 0))
    ops.push(@spec.Op::unary(@spec.FTrunc, 8, 1))
  } else {
    return None
  }
  Some(@spec.Program::new(0, profile, ops))
}

///|
/// 列出/输出探针。
fn run_probe(params : Array[String]) -> Unit {
  if params.length() == 0 {
    let names = probe_names()
    println("可用探针：")
    for n in names {
      println("  " + n)
    }
    return
  }
  let name = params[0]
  let profile = if params.length() > 1 { params[1] } else { "strict" }
  match probe_program(name, profile) {
    Some(p) => println(@spec.encode_program(p))
    None => println("!E unknown-probe " + name)
  }
}
