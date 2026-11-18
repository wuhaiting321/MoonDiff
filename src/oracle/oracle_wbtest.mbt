// 规范裁定器的白盒测试。
//
// 这里的断言同时承担两个作用：证明裁定逻辑正确，以及把「什么算缺陷、
// 什么算无条款不一致、什么算实现自由度」这条边界固定下来——
// 边界一旦被改动，测试会先红。

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
test "Source 拒绝任何空白项" {
  // 「没有出处不许下结论」的闸门：三项任一为空白即构造失败。
  // 而 Violation 的最后一个参数类型就是 Source，所以违规裁定无法绕开它。
  assert_true(Source::new("", "298-309", "Throws a panic.") is None)
  assert_true(Source::new("builtin/intrinsics.mbt", "", "Throws a panic.") is None)
  assert_true(Source::new("builtin/intrinsics.mbt", "298-309", "") is None)
  assert_true(Source::new("builtin/intrinsics.mbt", "298-309", "   \t ") is None)
  // 文档名里带换行会破坏报告的行结构，同样拒绝。
  assert_true(Source::new("builtin/\nintrinsics.mbt", "298-309", "x") is None)
}

///|
test "Source 渲染为 文件:行号" {
  match Source::new("builtin/intrinsics.mbt", "298-309", "Throws a panic.") {
    Some(s) => assert_eq(s.render(), "builtin/intrinsics.mbt:298-309")
    None => fail("合法出处不应被拒")
  }
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
test "INT_MIN / -1 裁定为无条款不一致，不指认违规方" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -2147483648),
    @spec.Op::const_i(1, -1),
    @spec.Op::binary(@spec.IDiv, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let names : Array[String] = ["wasm", "js"]
  // wasm 终止 -> 转录整体丢失；js 回绕并跑完。
  let ok : Array[String] = [
    "#0 iset r0 i-2147483648", "#1 iset r1 i-1", "#2 idiv r2 i-2147483648",
  ]
  let lost : Array[String] = []
  let traces : Array[Array[String]] = [lost, ok]
  let aborted : Array[Bool] = [true, false]
  let j = adjudicate(p, 2, names, traces, aborted)
  assert_eq(judgment_tag(j), "UNSPECIFIED-DIVERGENCE:int-div-overflow")
  match j {
    Unspecified(_, labelled, gap, src) => {
      assert_eq(labelled.length(), 2)
      assert_eq(labelled[0], "wasm=ABORT")
      assert_eq(labelled[1], "js=i-2147483648")
      // 缺口说明必须说清「只查过哪一条、那一条只写了什么」。
      assert_true(gap.length() > 0)
      assert_eq(src.render(), "builtin/intrinsics.mbt:298-309")
      assert_true(src.quote.contains("divisor") || src.quote.length() > 0)
    }
    _ => fail("应当裁定为无条款不一致")
  }
}

///|
test "INT_MIN % -1 同样是无条款不一致" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -2147483648),
    @spec.Op::const_i(1, -1),
    @spec.Op::binary(@spec.IMod, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let lost : Array[String] = []
  let ok : Array[String] = [
    "#0 iset r0 i-2147483648", "#1 iset r1 i-1", "#2 imod r2 i0",
  ]
  let j = adjudicate(p, 2, ["wasm", "js"], [lost, ok], [true, false])
  assert_eq(judgment_tag(j), "UNSPECIFIED-DIVERGENCE:int-div-overflow")
}

///|
test "加法溢出但某后端不回绕：违反规范，出处指向 Add 条目" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 2147483647),
    @spec.Op::const_i(1, 1),
    @spec.Op::binary(@spec.IAdd, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let a : Array[String] = [
    "#0 iset r0 i2147483647", "#1 iset r1 i1", "#2 iadd r2 i-2147483648",
  ]
  let b : Array[String] = [
    "#0 iset r0 i2147483647", "#1 iset r1 i1", "#2 iadd r2 i2147483647",
  ]
  let j = adjudicate(p, 2, ["wasm", "js"], [a, b], [false, false])
  assert_eq(judgment_tag(j), "SPEC-VIOLATION:int-wrap")
  match j {
    Violation(_, offenders, expected, src) => {
      assert_eq(expected, "i-2147483648")
      assert_eq(offenders.length(), 1)
      assert_eq(offenders[0], "js")
      assert_eq(src.render(), "builtin/intrinsics.mbt:234-246")
      assert_true(src.quote.contains("wraps around"))
    }
    _ => fail("应当裁定为违反规范")
  }
}

///|
test "减法下溢同样引用 Sub 条目" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -2147483648),
    @spec.Op::const_i(1, 1),
    @spec.Op::binary(@spec.ISub, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let a : Array[String] = [
    "#0 iset r0 i-2147483648", "#1 iset r1 i1", "#2 isub r2 i2147483647",
  ]
  let b : Array[String] = [
    "#0 iset r0 i-2147483648", "#1 iset r1 i1", "#2 isub r2 i-2147483647",
  ]
  let j = adjudicate(p, 2, ["wasm", "js"], [a, b], [false, false])
  match j {
    Violation(_, _, expected, src) => {
      assert_eq(expected, "i2147483647")
      assert_eq(src.render(), "builtin/intrinsics.mbt:249-251")
    }
    _ => fail("应当裁定为违反规范")
  }
}

///|
test "未溢出的加法不套用回绕条款" {
  // 2147483646 + 1 没有溢出，回绕条款不适用；两个后端取值不同也不能判违规。
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 2147483646),
    @spec.Op::const_i(1, 1),
    @spec.Op::binary(@spec.IAdd, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let a : Array[String] = [
    "#0 iset r0 i2147483646", "#1 iset r1 i1", "#2 iadd r2 i2147483647",
  ]
  let b : Array[String] = [
    "#0 iset r0 i2147483646", "#1 iset r1 i1", "#2 iadd r2 i-2147483648",
  ]
  let j = adjudicate(p, 2, ["wasm", "js"], [a, b], [false, false])
  assert_eq(judgment_tag(j), "UNDETERMINED")
}

///|
test "所有后端一致回绕时不产生裁定" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 2147483647),
    @spec.Op::const_i(1, 1),
    @spec.Op::binary(@spec.IAdd, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let same : Array[String] = [
    "#0 iset r0 i2147483647", "#1 iset r1 i1", "#2 iadd r2 i-2147483648",
  ]
  let j = adjudicate(p, 2, ["wasm", "js"], [same, same], [false, false])
  assert_eq(judgment_tag(j), "UNDETERMINED")
}

///|
test "操作数来自运行期计算时不猜，转 Undetermined" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 6),
    @spec.Op::const_i(1, 4),
    @spec.Op::binary(@spec.IAdd, 2, 0, 1),
    @spec.Op::binary(@spec.IDiv, 3, 2, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let a : Array[String] = [
    "#0 iset r0 i6", "#1 iset r1 i4", "#2 iadd r2 i10", "#3 idiv r3 i2",
  ]
  let b : Array[String] = [
    "#0 iset r0 i6", "#1 iset r1 i4", "#2 iadd r2 i10", "#3 idiv r3 i3",
  ]
  let j = adjudicate(p, 3, ["wasm", "js"], [a, b], [false, false])
  assert_eq(judgment_tag(j), "UNDETERMINED")
}

///|
test "NaN 符号位差异裁定为实现自由度，并带条款出处" {
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
  match j {
    Freedom(_, _, src) => assert_eq(src.at, "NaN propagation")
    _ => fail("应当裁定为实现自由度")
  }
}

///|
test "只有文本写法不同时裁定为无条款不一致" {
  // 位模式相同、文本写法不同：document 只承诺「返回字符串表示」，
  // 没有规定指数形式，因此不能算违规，也不算条款明文允许的自由度。
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
  assert_eq(judgment_tag(j), "UNSPECIFIED-DIVERGENCE:float-format")
  match j {
    Unspecified(_, labelled, _, src) => {
      assert_eq(labelled.length(), 2)
      assert_eq(src.render(), "builtin/double.mbt:274-296")
    }
    _ => fail("应当裁定为无条款不一致")
  }
}

///|
test "终止的后端不被算作更早一步的违规方" {
  // 回归：wasm 是在更靠后的步骤终止的，转录被整体丢弃；
  // 若把「aborted」直接当成「本步取值错误」，就会把 IMul 那一部
  // 判成 wasm 违反回绕条款。终止不等于算错，没有定位就不指控。
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -2147483648),
    @spec.Op::const_i(1, -1),
    @spec.Op::binary(@spec.IMul, 2, 0, 1),
    @spec.Op::binary(@spec.IAdd, 3, 2, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let ok : Array[String] = [
    "#0 iset r0 i-2147483648", "#1 iset r1 i-1", "#2 imul r2 i-2147483648",
  ]
  let j = adjudicate(p, 2, ["wasm", "js"], [[], ok], [true, false])
  assert_eq(judgment_tag(j), "UNDETERMINED")
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
  match find_static_site(p) {
    Some(s) => assert_eq(s, 5)
    None => fail("应当找到第 5 步的溢出点")
  }
}

///|
test "静态扫描也认得乘法溢出" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -2147483648),
    @spec.Op::const_i(1, -1),
    @spec.Op::binary(@spec.IMul, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  match find_static_site(p) {
    Some(s) => assert_eq(s, 2)
    None => fail("应当把乘法溢出算作可静态判定的位置")
  }
}

///|
test "静态扫描对无溢出、无常量的程序返回 None" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, -7),
    @spec.Op::const_i(1, 2),
    @spec.Op::binary(@spec.IDiv, 2, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  assert_true(find_static_site(p) is None)
  let ops2 : Array[@spec.Op] = [
    @spec.Op::const_i(0, 6),
    @spec.Op::const_i(1, 4),
    @spec.Op::binary(@spec.IAdd, 2, 0, 1),
    @spec.Op::binary(@spec.IMul, 3, 2, 1),
  ]
  assert_true(find_static_site(@spec.Program::new(0, "strict", ops2)) is None)
}

///|
test "裁定文本同时打出定位与原文" {
  let src = match
    Source::new(
      "builtin/intrinsics.mbt",
      "234-246",
      "wraps around according to two's complement rules.",
    ) {
    Some(s) => s
    None => fail("出处不应为 None")
  }
  let j = Violation(IntWrap, ["js"], "i-2147483648", src)
  let text = judgment_text(j, "  ")
  assert_true(text.contains("builtin/intrinsics.mbt:234-246"))
  assert_true(text.contains("原文"))
  assert_true(text.contains("wraps around"))
}
