// 报告渲染的白盒测试。
//
// 这个包不参与裁定，但它的输出是「人看到的那一面」：矩阵说谁和谁不一样、
// 归因说第几步哪条原语、判定说这是分歧还是终止。三处都错得起，
// 所以每个导出函数都要有断言，且至少各有一条负例。

///|
test "split_lines：丢弃末尾空行，剥掉 CR" {
  let a = split_lines("#0 iset r0 i1\n#end 1\n")
  assert_eq(a.length(), 2)
  assert_eq(a[0], "#0 iset r0 i1")
  assert_eq(a[1], "#end 1")
  // CRLF 下的行尾不能把 \r 带进转录，否则逐字节比对会假报差异
  let b = split_lines("#0 iset r0 i1\r\n#end 1")
  assert_eq(b.length(), 2)
  assert_eq(b[1], "#end 1")
  // 最后一行没有换行符时同样要保留
  assert_eq(split_lines("#end 1")[0], "#end 1")
}

///|
test "split_lines：空输入得空数组，中间空行保留" {
  let empty = split_lines("")
  assert_eq(empty.length(), 0)
  // 中间的空行是「某一步渲染成空串」的证据，不能在切分时被吃掉
  let mid = split_lines("#0 a\n\n#2 b")
  assert_eq(mid.length(), 3)
  assert_eq(mid[1], "")
}

///|
test "trace_complete：只认末行的 #end 哨兵" {
  let ok : Array[String] = ["#0 iset r0 i1", "#end 1"]
  assert_true(trace_complete(ok))
  // 没有末行的转录就是「不知道在哪一步没了」，不能当成完整
  let truncated : Array[String] = ["#0 iset r0 i1"]
  assert_false(trace_complete(truncated))
  let none : Array[String] = []
  assert_false(trace_complete(none))
  // 前缀相同但记号不同，不能靠 startswith 蒙过去
  let near : Array[String] = ["#0 iset r0 i1", "#endx 1"]
  assert_false(trace_complete(near))
}

///|
test "matrix_text：全部一致时判 PASS，且只标一条 baseline" {
  let a : Array[String] = ["#0 iset r0 i1", "#1 iadd r1 i2", "#end 2"]
  let b : Array[String] = ["#0 iset r0 i1", "#1 iadd r1 i2", "#end 2"]
  let out = matrix_text(["wasm", "js"], [a, b])
  assert_true(out.contains("PASS（逐位一致）"))
  assert_true(out.contains("baseline"))
  // 一致时不该出现归因段，出现就说明把「相同」误判成了「不同」
  assert_false(out.contains("首处分歧"))
  assert_false(out.contains("FAIL"))
}

///|
test "matrix_text：整数分歧给 FAIL、步号与差异位" {
  let a : Array[String] = ["#0 iset r0 i1", "#1 iadd r1 i2", "#end 2"]
  let b : Array[String] = ["#0 iset r0 i1", "#1 iadd r1 i3", "#end 2"]
  let out = matrix_text(["wasm", "js"], [a, b])
  assert_true(out.contains("DIVERGENT（存在跨后端差异）"))
  assert_true(out.contains("FAIL"))
  assert_true(out.contains("首处分歧 @ step 1"))
  assert_true(out.contains("原语   : iadd"))
  assert_true(out.contains("左侧   : #1 iadd r1 i2"))
  assert_true(out.contains("非浮点差异"))
}

///|
test "matrix_text：终止的后端标 ABORT 且步号显示为问号" {
  // 第二条转录没有 #end：它在途中 trap 了，转录被整体丢弃
  let a : Array[String] = ["#0 iset r0 i1", "#1 iadd r1 i2", "#end 2"]
  let b : Array[String] = ["#0 iset r0 i1"]
  let out = matrix_text(["wasm", "js"], [a, b])
  assert_true(out.contains("ABORTED"))
  assert_true(out.contains("ABORT"))
  assert_true(out.contains("无结束哨兵"))
  // 显示 "?" 而不是 "0"：真相是「不知道第几步没的」，不是「第 0 步就不同」
  assert_true(out.contains("| ?"))
  assert_true(out.contains("localize.py"))
}

///|
test "matrix_text：基线跳过终止的转录" {
  // 第一条崩了。若拿它当基线，两条健康后端会被误报成 FAIL
  let dead : Array[String] = ["#0 iset r0 i1"]
  let ok : Array[String] = ["#0 iset r0 i1", "#end 1"]
  let out = matrix_text(["wasm", "js", "native"], [dead, ok, ok])
  assert_true(out.contains("ABORT"))
  assert_true(out.contains("baseline"))
  // 健康的两条必须都是 PASS，不能因为基线选错而变成 FAIL
  assert_false(out.contains("FAIL"))
}

///|
test "matrix_text：浮点位模式差异与打印格式差异分别归类" {
  let bits_l : Array[String] = ["#0 fadd r0 f7ff8000000000000|nan", "#end 1"]
  let bits_r : Array[String] = ["#0 fadd r0 ffff8000000000000|nan", "#end 1"]
  let bits = matrix_text(["wasm", "js"], [bits_l, bits_r])
  assert_true(bits.contains("位模式不一致"))
  // 位模式相同、只有宿主打印不同：这是格式问题，不该按数值缺陷处理
  let fmt_r : Array[String] = ["#0 fadd r0 f7ff8000000000000|NaN", "#end 1"]
  let fmt = matrix_text(["wasm", "js"], [bits_l, fmt_r])
  assert_true(fmt.contains("打印格式不一致"))
  assert_false(fmt.contains("位模式不一致"))
}

///|
test "matrix_text：空输入不崩，给出明确提示" {
  let empty : Array[Array[String]] = []
  assert_eq(matrix_text([], empty), "MoonDiff: 没有可比较的转录\n")
}

///|
test "diff_text：一致时说 PASS 并给出步数" {
  let a : Array[String] = ["#0 iset r0 i1", "#end 1"]
  let b : Array[String] = ["#0 iset r0 i1", "#end 1"]
  let out = diff_text("wasm", a, "js", b)
  assert_true(out.contains("PASS"))
  assert_true(out.contains("（2 步）"))
  assert_false(out.contains("上下文"))
}

///|
test "diff_text：分歧时给两侧原文、差异位与上下文" {
  let a : Array[String] = [
    "#0 iset r0 i1",
    "#1 iset r1 i2",
    "#2 iadd r2 i3",
    "#3 imul r3 i6",
    "#end 4",
  ]
  let b : Array[String] = [
    "#0 iset r0 i1",
    "#1 iset r1 i2",
    "#2 iadd r2 i4",
    "#3 imul r3 i8",
    "#end 4",
  ]
  let out = diff_text("wasm", a, "js", b)
  assert_true(out.contains("FAIL  wasm vs js"))
  assert_true(out.contains("首异步 : 2"))
  assert_true(out.contains("wasm"))
  assert_true(out.contains("#2 iadd r2 i3"))
  assert_true(out.contains("#2 iadd r2 i4"))
  assert_true(out.contains("上下文"))
}

///|
test "diff_text：分歧发生在首步时上下文不越界" {
  let a : Array[String] = ["#0 iset r0 i1", "#end 1"]
  let b : Array[String] = ["#0 iset r0 i2", "#end 1"]
  let out = diff_text("wasm", a, "js", b)
  assert_true(out.contains("首异步 : 0"))
  // step=0 时起点必须夹到 0，否则会去索引 -2
  assert_true(out.contains("#0 iset r0 i1"))
  assert_true(out.contains("#end 1"))
}
