// 程序编解码与 JSON 的白盒测试。

///|
test "JSON 基本往返" {
  let text = "{\"a\":1,\"b\":[true,null,\"x\"],\"c\":-2}"
  match parse_json(text) {
    Some(j) => assert_eq(dump_json(j), text)
    None => fail("解析失败")
  }
}

///|
test "JSON 代理对合并成一个码点" {
  match parse_json("\"\\ud83d\\ude00\"") {
    Some(JStr(s)) => assert_eq(s.to_array().length(), 1)
    _ => fail("应当解析出字符串")
  }
}

///|
test "程序编解码保持 Int64 下界与浮点位模式" {
  let ops : Array[Op] = [
    Op::const_i(0, -2147483648),
    Op::const_l(1, 0x8000000000000000L),
    Op::const_f(2, 0xFFF8000000000000L),
    Op::const_s(3, "中"),
    Op::const_a(4, [1, 2, 3]),
    Op::binary(IAdd, 5, 0, 0),
    Op::unary(SLen, 6, 3),
  ]
  let p = Program::new(42, "strict", ops)
  let text = encode_program(p)
  match decode_program(text) {
    Some(q) => {
      assert_eq(q.ops.length(), 7)
      assert_eq(q.seed, 42)
      assert_eq(q.ops[1].imm_l, 0x8000000000000000L)
      assert_eq(
        @core.hex16(q.ops[2].imm_f.reinterpret_as_int64()),
        "fff8000000000000",
      )
      assert_eq(q.ops[3].imm_s, "中")
      assert_eq(q.ops[4].imm_a.length(), 3)
    }
    None => fail("程序解码失败")
  }
}

///|
test "损坏的程序返回 None 而不是崩溃" {
  assert_true(decode_program("{\"ops\":[") is None)
  assert_true(decode_program("{\"seed\":1,\"ops\":[[\"nope\",0]]}") is None)
  assert_true(
    decode_program("{\"seed\":1,\"ops\":[[\"iset\",0,\"x\"]]}") is None,
  )
}
