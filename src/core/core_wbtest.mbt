// 核心值模型与差异计算的白盒测试。

///|
test "hex16 输出补码位串而不是符号绝对值" {
  assert_eq(hex16(0L), "0000000000000000")
  assert_eq(hex16(1L), "0000000000000001")
  assert_eq(hex16(-1L), "ffffffffffffffff")
  assert_eq(hex16(0xFFF8000000000000L), "fff8000000000000")
  assert_eq(hex16(0x7FF8000000000000L), "7ff8000000000000")
}

///|
test "escape_str 把非 ASCII 全部转义" {
  assert_eq(escape_str("abc"), "abc")
  assert_eq(escape_str("a中"), "a\\u{4e2d}")
  assert_eq(escape_str("😀"), "\\u{1f600}")
  assert_eq(escape_str("\n"), "\\n")
  assert_eq(escape_str("\""), "\\\"")
}

///|
test "render_value 各档位对 NaN 的处理不同" {
  let nan = 0.0 / 0.0
  let bit = render_value(VF64(nan), BitExact)
  let sem = render_value(VF64(nan), Semantic)
  assert_eq(sem, "fnan")
  assert_true(bit.length() == 17)
}

///|
test "split_ws 按空白切分转录行" {
  let ws = split_ws("#12 iadd r3 i42")
  assert_eq(ws.length(), 4)
  assert_eq(ws[0], "#12")
  assert_eq(ws[1], "iadd")
  assert_eq(ws[3], "i42")
}

///|
test "first_divergence 能识别长度不一致" {
  let a : Array[String] = ["#0 a r0 i1", "#1 b r1 i2"]
  let b : Array[String] = ["#0 a r0 i1"]
  match first_divergence(a, b) {
    Some(d) => {
      assert_eq(d.step, 1)
      assert_eq(d.right, "<eof>")
    }
    None => fail("应当发现长度差异")
  }
}

///|
test "一致性得分能指出少数派" {
  let t1 : Array[String] = ["#0 x r0 i1", "#1 y r1 i2"]
  let t2 : Array[String] = ["#0 x r0 i1", "#1 y r1 i2"]
  let t3 : Array[String] = ["#0 x r0 i1", "#1 y r1 i9"]
  let scores = agreement_scores([t1, t2, t3])
  assert_eq(scores[0], 1)
  assert_eq(scores[2], 0)
  assert_eq(outlier_index([t1, t2, t3]), 2)
}
