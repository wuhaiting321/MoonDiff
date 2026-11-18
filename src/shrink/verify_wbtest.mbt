// 复现验证：两个分支都必须有单测，且失败分支要能真的走到。

///|
/// 构造一份「正常结束」的转录：末行是 `#end <n>` 哨兵。
fn ok_trace(v : String) -> Array[String] {
  ["#0 iset r0 " + v, "#1 idiv r1 " + v, "#end 2"]
}

///|
/// 终止性差异的现场：wasm / wasm-gc 无转录，js 跑完。
fn abort_case() -> Sig {
  let names : Array[String] = ["wasm", "wasm-gc", "js"]
  let traces : Array[Array[String]] = [[], [], ok_trace("i-2147483648")]
  sig_of(names, traces)
}

///|
test "收缩未破坏依赖锥时判为复现（终止性差异）" {
  let a = abort_case()
  let b = abort_case()
  assert_true(compare(a, b) is Reproduced)
}

///|
test "收缩后不再终止，判为未复现并指出终止集合变了" {
  let a = abort_case()
  let names : Array[String] = ["wasm", "wasm-gc", "js"]
  let traces : Array[Array[String]] = [
    ok_trace("i1"),
    ok_trace("i1"),
    ok_trace("i-2147483648"),
  ]
  let b = sig_of(names, traces)
  let verdict = compare(a, b)
  assert_true(verdict is NotReproduced(_))
  match verdict {
    NotReproduced(r) => assert_true(r.contains("终止的后端集合变了"))
    _ => fail("应判为未复现")
  }
}

///|
test "收缩后各后端一致，判为未复现并说明分歧消失" {
  let names : Array[String] = ["wasm", "js"]
  let a = sig_of(names, [ok_trace("i1"), ok_trace("i2")])
  let b = sig_of(names, [ok_trace("i1"), ok_trace("i1")])
  let verdict = compare(a, b)
  match verdict {
    NotReproduced(r) => assert_true(r.contains("分歧消失"))
    _ => fail("应判为未复现")
  }
}

///|
test "取值分歧的两侧值变了要单独指出来，不笼统说分歧消失" {
  let names : Array[String] = ["wasm", "js"]
  let a = sig_of(names, [ok_trace("i1"), ok_trace("i2")])
  let b = sig_of(names, [ok_trace("i7"), ok_trace("i8")])
  let verdict = compare(a, b)
  match verdict {
    NotReproduced(r) => assert_true(r.contains("两侧值变了"))
    _ => fail("应判为未复现")
  }
}

///|
test "终止集合相同但存活方的取值分歧消失，要报形态变了" {
  let names : Array[String] = ["wasm", "wasm-gc", "js", "native"]
  // 收缩前：两个后端终止，存活的两个取值不同
  let a = sig_of(names, [[], [], ok_trace("i1"), ok_trace("i2")])
  // 收缩后：终止的还是那两个，存活的两个变成一致 —— 分歧形态从「终止+取值」退化为「只有终止」
  let b = sig_of(names, [[], [], ok_trace("i1"), ok_trace("i1")])
  let verdict = compare(a, b)
  match verdict {
    NotReproduced(r) => assert_true(r.contains("形态变了"))
    _ => fail("应判为未复现")
  }
}

///|
test "首处分歧的原语变了要被检出" {
  let names : Array[String] = ["wasm", "js"]
  let a : Array[Array[String]] = [
    ["#0 fdiv r0 f3ff0000000000000|1", "#end 1"],
    ["#0 fdiv r0 f4000000000000000|2", "#end 1"],
  ]
  let b : Array[Array[String]] = [
    ["#0 fadd r0 f3ff0000000000000|1", "#end 1"],
    ["#0 fadd r0 f4000000000000000|2", "#end 1"],
  ]
  let verdict = compare(sig_of(names, a), sig_of(names, b))
  match verdict {
    NotReproduced(r) => assert_true(r.contains("原语变了"))
    _ => fail("应判为未复现")
  }
}

///|
test "终止性差异不算成取值分歧（转录截断不是任何一条指令算错的证据）" {
  let sig = abort_case()
  // wasm / wasm-gc 的转录为空，js 有 3 行；朴素地按行比对会报「第 0 步不同」。
  assert_true(sig.divergent == false)
  assert_eq(sig.op, "-")
  assert_true(sig.aborted.length() == 2)
  let text = verify_text(sig, sig)
  assert_true(text.contains("取值分歧: 无（存活方一致）"))
  assert_true(!text.contains("取值分歧: step 0"))
}

///|
test "原程序本来就没有分歧时不许报复现" {
  let names : Array[String] = ["wasm", "js"]
  let a = sig_of(names, [ok_trace("i1"), ok_trace("i1")])
  let verdict = compare(a, a)
  match verdict {
    NotReproduced(r) => assert_true(r.contains("没有分歧"))
    _ => fail("应判为未复现")
  }
}

///|
test "步号重排不影响判定（收缩会删掉目标步之前的支线）" {
  let names : Array[String] = ["wasm", "js"]
  let a : Array[Array[String]] = [
    ["#5 idiv r1 i-2147483648", "#end 6"],
    ["#5 idiv r1 i0", "#end 6"],
  ]
  let b : Array[Array[String]] = [
    ["#2 idiv r1 i-2147483648", "#end 3"],
    ["#2 idiv r1 i0", "#end 3"],
  ]
  assert_true(compare(sig_of(names, a), sig_of(names, b)) is Reproduced)
}

///|
test "验证报告末行是字面量，脚本可直接匹配" {
  let names : Array[String] = ["wasm", "js"]
  let yes = verify_text(
    sig_of(names, [ok_trace("i1"), ok_trace("i2")]),
    sig_of(names, [ok_trace("i1"), ok_trace("i2")]),
  )
  assert_true(yes.contains("\n验证结果 : verified: reproduce\n"))
  let no = verify_text(
    sig_of(names, [ok_trace("i1"), ok_trace("i1")]),
    sig_of(names, [ok_trace("i1"), ok_trace("i1")]),
  )
  assert_true(no.contains("\n验证结果 : NOT-REPRODUCED\n"))
}
