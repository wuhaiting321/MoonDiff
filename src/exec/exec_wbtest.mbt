// 解释器：确定性与显式语义。

///|
test "同一程序两次执行必须逐行相同" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 7),
    @spec.Op::const_i(1, -3),
    @spec.Op::binary(@spec.IDiv, 2, 0, 1),
    @spec.Op::binary(@spec.IMod, 3, 0, 1),
    @spec.Op::const_f(4, 0x3FF0000000000000L),
    @spec.Op::const_f(5, 0x0000000000000000L),
    @spec.Op::binary(@spec.FDiv, 6, 4, 5),
    @spec.Op::const_s(7, "中a"),
    @spec.Op::unary(@spec.SLen, 8, 7),
  ]
  let p = @spec.Program::new(1, "strict", ops)
  let a = run_program(p, @core.Profile::Strict)
  let b = run_program(p, @core.Profile::Strict)
  assert_eq(a.trace.length(), 9)
  let mut i = 0
  while i < a.trace.length() {
    assert_eq(a.trace[i], b.trace[i])
    i = i + 1
  }
}

///|
test "整数除零被定义为 0 且不触发 trap" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 5),
    @spec.Op::const_i(1, 0),
    @spec.Op::binary(@spec.IDiv, 2, 0, 1),
    @spec.Op::binary(@spec.IMod, 3, 0, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let r = run_program(p, @core.Profile::Strict)
  assert_eq(r.trace.length(), 4)
  assert_true(r.trace[2] == "#2 idiv r2 i0")
}

///|
test "浮点转整数是饱和语义" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_f(0, 0x54B249AD2594C37DL),
    @spec.Op::const_f(1, 0xFFF8000000000000L),
    @spec.Op::unary(@spec.F2I, 2, 0),
    @spec.Op::unary(@spec.F2I, 3, 1),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let r = run_program(p, @core.Profile::Strict)
  assert_true(r.trace[2] == "#2 f2i r2 i2147483647")
  assert_true(r.trace[3] == "#3 f2i r3 i0")
}

///|
test "覆盖表记录到执行过的原语" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 1),
    @spec.Op::unary(@spec.INeg, 1, 0),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let r = run_program(p, @core.Profile::Strict)
  assert_true(r.coverage.length() >= 2)
}
