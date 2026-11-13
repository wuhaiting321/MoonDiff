// 规范裁定器的白盒测试。
//
// 这里的断言同时承担两个作用：证明裁定逻辑正确，以及把「什么算缺陷、
// 什么算实现自由度」这条边界固定下来——边界一旦被改动，测试会先红。

///|
test "hex16 往返：位串与 Int64 互为逆运算" {
  let vals : Array[Int64] = [
    0L, 1L, -1L, 0x7FF8000000000000L, 0xFFF8000000000000L, 0x8000000000000000L,
  ]
  for v in vals {
    match parse_hex16(@core.hex16(v)) {
      Some(b) => assert_eq(b, v)
      None => fail("解析失败")
    }
  }
}

///|
test "parse_hex16 拒绝长度不足与非法字符" {
  assert_true(parse_hex16("fff8") is None)
  assert_true(parse_hex16("zzz8000000000000") is None)
}

///|
test "正负 quiet NaN 判定为只差符号位" {
  assert_true(nan_sign_only(0x7FF8000000000000L, 0xFFF8000000000000L))
  assert_true(nan_sign_only(0xFFF8000000000000L, 0x7FF8000000000000L))
}

///|
test "非 NaN 或尾数不同时不算符号位差异" {
  // 1.0 与 -1.0 不是 NaN
  assert_true(!nan_sign_only(0x3FF0000000000000L, 0xBFF0000000000000L))
  // 两个不同的 NaN 载荷：不能算「只差符号」
  assert_true(!nan_sign_only(0x7FF8000000000000L, 0x7FF8000000000001L))
}

///|
test "INT_MIN / -1 被裁定为违反规范，终止的后端是违规方" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -2147483648),
    @spec.Op::const_i(1, -1),
    @spec.Op::binary(@spec.IDiv, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let names : Array[String] = ["wasm", "js"]
  // wasm 终止 -> 转录整体丢失；js 正常跑完三步。
  let ok : Array[String] = [
    "#0 iset r0 i-2147483648", "#1 iset r1 i-1", "#2 idiv r2 i-2147483648",
  ]
  let lost : Array[String] = []
  let traces : Array[Array[String]] = [lost, ok]
  let aborted : Array[Bool] = [true, false]
  match adjudicate(p, 2, names, traces, aborted) {
    Violation(offenders, expected, _) => {
      assert_eq(expected, "i-2147483648")
      assert_eq(offenders.length(), 1)
      assert_eq(offenders[0], "wasm")
    }
    _ => fail("应当裁定为违反规范")
  }
}

///|
test "INT_MIN % -1 的规范值是 0" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -2147483648),
    @spec.Op::const_i(1, -1),
    @spec.Op::binary(@spec.IMod, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let lost : Array[String] = []
  let traces : Array[Array[String]] = [lost]
  match adjudicate(p, 2, ["wasm"], traces, [true]) {
    Violation(_, expected, _) => assert_eq(expected, "i0")
    _ => fail("应当裁定为违反规范")
  }
}

///|
test "普通除法不触发溢出裁定" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -7),
    @spec.Op::const_i(1, 2),
    @spec.Op::binary(@spec.IDiv, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let a : Array[String] = ["#0 iset r0 i-7", "#1 iset r1 i2", "#2 idiv r2 i-3"]
  let b : Array[String] = ["#0 iset r0 i-7", "#1 iset r1 i2", "#2 idiv r2 i-4"]
  let j = adjudicate(p, 2, ["a", "b"], [a, b], [false, false])
  assert_true(judgment_tag(j) == "UNDETERMINED")
}

///|
test "NaN 符号位差异裁定为实现自由度而非缺陷" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_f(0, 0x0000000000000000L),
    @spec.Op::const_f(1, 0x0000000000000000L),
    @spec.Op::binary(@spec.FDiv, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let a : Array[String] = [
    "#0 fset r0 f0000000000000000|0.0", "#1 fset r1 f0000000000000000|0.0", "#2 fdiv r2 fff8000000000000|NaN",
  ]
  let b : Array[String] = [
    "#0 fset r0 f0000000000000000|0.0", "#1 fset r1 f0000000000000000|0.0", "#2 fdiv r2 7ff8000000000000|NaN",
  ]
  let j = adjudicate(p, 2, ["wasm", "js"], [a, b], [false, false])
  assert_eq(judgment_tag(j), "FREEDOM:nan-sign")
}

///|
test "只有格式化文本不同时裁定为格式化自由度" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_f(0, 0x4415AF1D78B58C40L),
    @spec.Op::unary(@spec.FNeg, 1, 0),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let a : Array[String] = [
    "#0 fset r0 f4415af1d78b58c40|1e+21", "#1 fneg r1 4415af1d78b58c40|1e+21",
  ]
  let b : Array[String] = [
    "#0 fset r0 f4415af1d78b58c40|1e+21", "#1 fneg r1 4415af1d78b58c40|1e21",
  ]
  let j = adjudicate(p, 1, ["wasm", "js"], [a, b], [false, false])
  assert_eq(judgment_tag(j), "FREEDOM:float-format")
}

///|
test "静态扫描能找到程序深处的溢出点" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 1),
    @spec.Op::const_i(1, 2),
    @spec.Op::binary(@spec.IAdd, 2, 0, 1),
    @spec.Op::const_i(3, -2147483648),
    @spec.Op::const_i(4, -1),
    @spec.Op::binary(@spec.IDiv, 5, 3, 4),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  match find_static_violation(p) {
    Some(s) => assert_eq(s, 5)
    None => fail("应当找到第 5 步的溢出点")
  }
}

///|
test "静态扫描对无溢出的程序返回 None" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -7),
    @spec.Op::const_i(1, 2),
    @spec.Op::binary(@spec.IDiv, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  assert_true(find_static_violation(p) is None)
}
