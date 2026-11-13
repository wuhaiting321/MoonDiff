// 生成器：确定性、覆盖引导语料。

///|
test "同一种子给出同一序列" {
  let a = Rng::new(12345)
  let b = Rng::new(12345)
  let mut i = 0
  while i < 8 {
    assert_eq(a.next(), b.next())
    i = i + 1
  }
}

///|
test "不同种子给出不同序列" {
  let a = Rng::new(1)
  let b = Rng::new(2)
  assert_true(a.next() != b.next())
}

///|
test "生成结果对同一种子可复现" {
  let p1 = generate(gen_config(99, 40, 8, "strict"))
  let p2 = generate(gen_config(99, 40, 8, "strict"))
  assert_eq(p1.ops.length(), p2.ops.length())
  assert_eq(encode_of(p1), encode_of(p2))
}

///|
fn encode_of(p : @spec.Program) -> String {
  @spec.encode_program(p)
}

///|
test "语料库只收带来新边的输入" {
  let c = Corpus::new()
  let p = generate(gen_config(7, 20, 8, "strict"))
  assert_true(c.add(p, [10, 11]))
  assert_true(!c.add(p, [10, 11]))
  assert_true(c.add(p, [12]))
  assert_eq(c.size(), 2)
}
