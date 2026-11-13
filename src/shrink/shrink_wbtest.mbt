// 收缩：依赖闭包的正确性。

///|
test "依赖闭包包含全部前驱，不含无关指令" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_i(0, 1),
    @spec.Op::const_i(1, 2),
    @spec.Op::const_i(9, 99),
    @spec.Op::binary(@spec.IAdd, 2, 0, 1),
    @spec.Op::binary(@spec.IMul, 3, 2, 0),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let mark = dependency_cone(p, 4)
  assert_true(mark[4])
  assert_true(mark[3])
  assert_true(mark[0])
  assert_true(mark[1])
  // r9 只在第 2 条被写、之后从未被读，属于死写入，不在闭包内
  assert_true(!mark[2])
}

///|
test "收缩后仍能复现同一条分歧" {
  let ops : Array[@spec.Op] = [
    @spec.Op::const_l(0, 1L),
    @spec.Op::const_i(7, 5),
    @spec.Op::const_f(1, 0x3FF0000000000000L),
    @spec.Op::const_f(2, 0x0000000000000000L),
    @spec.Op::binary(@spec.FDiv, 3, 1, 2),
  ]
  let p = @spec.Program::new(0, "strict", ops)
  let small = shrink(p, 4)
  // 5 条 -> 3 条：r0 与 r7 都没被 fdiv 依赖，一并删除
  assert_eq(small.ops.length(), 3)
  assert_eq(small.ops[2].dst, 3)
}
