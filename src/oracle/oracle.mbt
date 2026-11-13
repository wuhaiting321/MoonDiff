// 规范裁定：把「两边不一样」升级为「哪边违反了规范」。
//
// 差分测试最常见的失败模式是只报告「不一致」，却答不出谁错了。
// 一旦有可引用的语言规范，结论就能从「有差异」推进到「某后端违反语义」。
// 本包只做这一件事：给定程序、步号与各后端的实际结果，给出裁定。
//
// 裁定的三个档位对应三种真实情况，不能混为一谈：
//   Violation   —— 有后端违反可引用的规范，是缺陷，应当修；
//   Freedom     —— 规范未作规定，属实现自由度，不是缺陷，但需在序列化等场景注意；
//   Undetermined—— 缺规范依据或缺操作数，明确承认「判不了」，而不是猜。

///|
/// 一处分歧的裁定结果。
pub(all) enum Judgment {
  /// 有后端违反可引用的规范。`offenders` 为违规方，`expected` 为规范值。
  Violation(Array[String], String, String)
  /// 规范未规定，属实现自由度。不算缺陷。
  Freedom(String, String)
  /// 判不了：缺规范依据或缺少操作数信息。明确承认，而不是猜测。
  Undetermined(String)
}

///|
/// 单个十六进制字符的值；非法字符返回 -1。
fn hex_digit(c : Char) -> Int32 {
  let n = c.to_int()
  if n >= 48 && n <= 57 {
    n - 48
  } else if n >= 97 && n <= 102 {
    n - 87
  } else if n >= 65 && n <= 70 {
    n - 55
  } else {
    -1
  }
}

///|
/// 解析 16 位十六进制补码位串（与 `@core.hex16` 互为逆运算）。
///
/// 只接受恰好 16 位：短于 16 位说明调用方给的不是 `f64` 位模式，
/// 此时宁可返回 `None` 让上层转 `Undetermined`，也不能猜。
pub fn parse_hex16(s : String) -> Int64? {
  if s.length() < 16 {
    return None
  }
  let mut v : Int64 = 0L
  let mut i = 0
  while i < 16 {
    match s.get_char(i) {
      Some(c) => {
        let d = hex_digit(c)
        if d < 0 {
          return None
        }
        v = v * 16L + d.to_int64()
        i = i + 1
      }
      None => return None
    }
  }
  Some(v)
}

///|
/// 转录行里的规范值（第 4 个空白分隔字段）。
fn canon_of(line : String) -> String {
  let ws = @core.split_ws(line)
  if ws.length() >= 4 {
    ws[3]
  } else {
    ""
  }
}

///|
/// `f64` 规范值里 `|` 之前的位串部分。
fn bits_part(canon : String) -> String {
  let mut i = 0
  while i < canon.length() {
    if canon.get_char(i) == Some('|') {
      return canon[0:i].to_owned()
    }
    i = i + 1
  }
  canon
}

///|
/// `|` 之后的格式化文本部分（没有则为空串）。
fn text_part(canon : String) -> String {
  let mut i = 0
  while i < canon.length() {
    if canon.get_char(i) == Some('|') {
      return canon[i + 1:].to_owned()
    }
    i = i + 1
  }
  ""
}

///|
/// 位模式是否是一个 NaN（指数位全 1、尾数非 0）。
fn is_nan_bits(b : Int64) -> Bool {
  (b & 0x7FF0000000000000L) == 0x7FF0000000000000L &&
  (b & 0x000FFFFFFFFFFFFFL) != 0L
}

///|
/// 两个位模式是否「都是 NaN，且清除符号位后完全相同」。
///
/// 这是判定「NaN 符号位差异属于实现自由度」的唯一依据：
/// 若连尾数都不同，就不是符号位问题，不能算自由度。
pub fn nan_sign_only(a : Int64, b : Int64) -> Bool {
  is_nan_bits(a) &&
  is_nan_bits(b) &&
  (a & 0x7FFFFFFFFFFFFFFFL) == (b & 0x7FFFFFFFFFFFFFFFL)
}

///|
/// 寄存器 `reg` 在 `before` 步之前最后一次被写入的常量；不是常量则 `None`。
///
/// 只有常量操作数才能让裁定有确定依据。若操作数来自运行期计算，
/// 裁定应转 `Undetermined`——拿不到输入就不该断言谁错。
fn const_before(p : @spec.Program, reg : Int32, before : Int32) -> @core.Value? {
  let mut i = before - 1
  while i >= 0 {
    let op = p.ops[i]
    if op.dst == reg {
      let v = match op.kind {
        @spec.ISet => Some(@core.VInt(op.imm_i))
        @spec.LSet => Some(@core.VI64(op.imm_l))
        @spec.FSet => Some(@core.VF64(op.imm_f))
        @spec.SSet => Some(@core.VStr(op.imm_s))
        _ => None
      }
      return v
    }
    i = i - 1
  }
  None
}

///|
/// 32 位整数除法/取模的溢出点：`INT_MIN / -1`。
///
/// 这是 `i32` 除法唯一会溢出的情形（除数为 0 已由本项目规格定义为 0）。
/// MoonBit 的 `Int` 是 32 位二补数、溢出回绕，因此规范结果应当是
/// `-2147483648`（取模为 `0`），而不是终止进程。
fn judge_int_div(
  p : @spec.Program,
  step : Int32,
  names : Array[String],
  results : Array[String],
  aborted : Array[Bool],
) -> Judgment? {
  if step < 0 || step >= p.ops.length() {
    return None
  }
  let op = p.ops[step]
  let kn = @spec.op_kind_name(op.kind)
  if kn != "idiv" && kn != "imod" {
    return None
  }
  let hit = match (const_before(p, op.a, step), const_before(p, op.b, step)) {
    (Some(@core.VInt(x)), Some(@core.VInt(y))) => x == -2147483648 && y == -1
    _ => false
  }
  if !hit {
    return None
  }
  let expected = if kn == "idiv" { "i-2147483648" } else { "i0" }
  let offenders : Array[String] = []
  let mut k = 0
  while k < names.length() {
    // abort 场景下转录被整体丢弃，`results[k]` 是空串；
    // 此时只把终止的后端判为违规方，不能拿空串当"值不对"去冤枉健康后端。
    let bad = if aborted[k] {
      true
    } else if results[k] == "" {
      false
    } else {
      canon_of(results[k]) != expected
    }
    if bad {
      offenders.push(names[k])
    }
    k = k + 1
  }
  if offenders.length() == 0 {
    return None
  }
  Some(
    Violation(
      offenders, expected, "moonbitlang/core 文档：Int 为 32 位整数，采用二补数运算，溢出按回绕处理（示例 2147483647 + 1 == -2147483648）；`Div` 条目只规定除数为 0 时 panic，未单独规定商不可表示的情形，故本条依据的是 Int 的定宽二补数溢出语义。同一规则下 INT_MIN / -1 的规范结果应为 INT_MIN 本身，而非终止进程。",
    ),
  )
}

///|
/// 取各后端在第 `step` 步的转录行；缺行补空串。
///
/// 必须按「目标步」取值：静态定位会把步号从 0 改到真正的溢出点，
/// 若仍沿用原来的结果数组，就会拿第 0 步的常量去和数据流无关的期望值比较，
/// 从而把无辜的后端判成违规方。
fn results_at(traces : Array[Array[String]], step : Int32) -> Array[String] {
  let out : Array[String] = []
  for t in traces {
    if step >= 0 && step < t.length() {
      out.push(t[step])
    } else {
      out.push("")
    }
  }
  out
}

///|
/// 静态扫描：程序里第一处「可静态判定会违反规范」的位置。
///
/// 存在的理由是终止性差异：后端 trap 时连已打印的转录都会被丢弃，
/// 转录里的步号归零，不能作为定位依据。此时按程序结构静态找出真正的
/// 溢出点，才能给出「第几步、哪条原语」的结论。
pub fn find_static_violation(p : @spec.Program) -> Int32? {
  let mut i = 0
  while i < p.ops.length() {
    let op = p.ops[i]
    let kn = @spec.op_kind_name(op.kind)
    if kn == "idiv" || kn == "imod" {
      let hit = match (const_before(p, op.a, i), const_before(p, op.b, i)) {
        (Some(@core.VInt(x)), Some(@core.VInt(y))) =>
          x == -2147483648 && y == -1
        _ => false
      }
      if hit {
        return Some(i)
      }
    }
    i = i + 1
  }
  None
}

///|
/// 全体结果是否都是 NaN 且只差符号位。
fn judge_nan_sign(results : Array[String]) -> Judgment? {
  let bits : Array[Int64] = []
  let mut i = 0
  while i < results.length() {
    if results[i] != "" {
      match parse_hex16(bits_part(canon_of(results[i]))) {
        Some(b) => if is_nan_bits(b) { bits.push(b) } else { return None }
        None => return None
      }
    }
    i = i + 1
  }
  if bits.length() < 2 {
    return None
  }
  let mask = bits[0] & 0x7FFFFFFFFFFFFFFFL
  let mut j = 1
  while j < bits.length() {
    if (bits[j] & 0x7FFFFFFFFFFFFFFFL) != mask {
      return None
    }
    j = j + 1
  }
  Some(
    Freedom(
      "NaN 符号位", "IEEE 754-2019 §6.2.3 不规定 NaN 的符号位，正负 quiet NaN 都是合法结果。因此「各后端不同」本身不是缺陷；但同一表达式在不同编译路径（常量折叠 vs 运行期）给出不同位模式，会让依赖位序列化的代码（哈希、缓存键、黄金文件比对）出现平台相关行为，工程上应显式归一化。",
    ),
  )
}

///|
/// 数值位相同、只有格式化文本不同。
fn judge_format(results : Array[String]) -> Judgment? {
  let canons : Array[String] = []
  let mut i = 0
  while i < results.length() {
    if results[i] != "" {
      canons.push(canon_of(results[i]))
    }
    i = i + 1
  }
  if canons.length() < 2 {
    return None
  }
  let b0 = bits_part(canons[0])
  let t0 = text_part(canons[0])
  if b0 == "" {
    return None
  }
  let mut differs_text = false
  let mut j = 1
  while j < canons.length() {
    if bits_part(canons[j]) != b0 {
      return None
    }
    if text_part(canons[j]) != t0 {
      differs_text = true
    }
    j = j + 1
  }
  if !differs_text {
    return None
  }
  Some(
    Freedom(
      "浮点格式化", "规范未规定浮点转字符串的具体写法（指数形式、尾随零、小数位数）。数值位模式一致时，文本差异不影响计算结果，但会让面向文本的黄金测试、日志比对失效。",
    ),
  )
}

///|
/// 对一处跨后端分歧给出裁定。
///
/// `results[k]` 是第 k 个后端在该步的实际转录行，缺行传空串；
/// `aborted[k]` 表示该后端在途中终止。
///
/// 判定顺序刻意固定：先查有规范依据的硬缺陷，再查实现自由度，最后落到
/// `Undetermined`。顺序反了就会把真缺陷混进「自由度」里放过。
pub fn adjudicate(
  p : @spec.Program,
  step : Int32,
  names : Array[String],
  traces : Array[Array[String]],
  aborted : Array[Bool],
) -> Judgment {
  let mut any_abort = false
  for b in aborted {
    if b {
      any_abort = true
    }
  }
  // 先按现场步号判：正常（无终止）时步号准确，这条路径最精确。
  match judge_int_div(p, step, names, results_at(traces, step), aborted) {
    Some(j) => return j
    None => ()
  }
  // 有后端终止时，转录被丢弃、步号归零，改用静态扫描定位真正的溢出点。
  if any_abort {
    match find_static_violation(p) {
      Some(s) =>
        match judge_int_div(p, s, names, results_at(traces, s), aborted) {
          Some(j) => return j
          None => ()
        }
      None => ()
    }
  }
  let at = results_at(traces, step)
  match judge_nan_sign(at) {
    Some(j) => return j
    None => ()
  }
  match judge_format(at) {
    Some(j) => return j
    None => ()
  }
  Undetermined(
    "缺少可引用的规范依据，或该步操作数不是常量。需要人工对照语言规范确认。",
  )
}

///|
/// 按显示宽度折行：ASCII 记 1 列，其余字符记 2 列。
///
/// 只用于裁定的说明文字，不用于转录。转录必须逐字节确定，
/// 折行会让「同一步的比较」失去意义；说明文字给人看，折行才有价值。
/// 断点优先落在空格或中文标点之后，避免把 `2147483647` 这类数字拆开。
fn wrap_note(s : String, width : Int, indent : String) -> String {
  let chars = s.to_array()
  let n = chars.length()
  let mut out = ""
  let mut i = 0
  let mut first = true
  while i < n {
    if !first {
      out = out + "\n" + indent
    }
    let mut col = 0
    let mut j = i
    let mut brk = -1
    while j < n {
      let c = chars[j]
      let w = if c.to_int() < 128 { 1 } else { 2 }
      if col + w > width && j > i {
        break
      }
      col = col + w
      if c == ' ' || c == '；' || c == '，' || c == '、' || c == '。' || c == '：' {
        brk = j
      }
      j = j + 1
    }
    let mut end = j
    // 断点太靠前就不采用，否则会退化成「一行一个字」。
    if j < n && brk >= i + 2 {
      end = brk + 1
    }
    // 去掉行尾空格：否则输出里会留下看不见但逐字节存在的尾随空白。
    while end > i + 1 && chars[end - 1] == ' ' {
      end = end - 1
    }
    let mut k = i
    while k < end {
      out = out + chars[k].to_string()
      k = k + 1
    }
    i = end
    while i < n && chars[i] == ' ' {
      i = i + 1
    }
    first = false
  }
  out
}

///|
/// 裁定的可读文本（纯 ASCII 之外只用中文，不含颜色转义）。
pub fn judgment_text(j : Judgment, indent : String) -> String {
  let cont = indent + "         "
  match j {
    Violation(offenders, expected, basis) => {
      let mut who = ""
      let mut i = 0
      while i < offenders.length() {
        if i > 0 {
          who = who + ", "
        }
        who = who + offenders[i]
        i = i + 1
      }
      indent +
      "结论   : 违反语言规范（Verdict: SPEC-VIOLATION）\n" +
      indent +
      "违规方 : " +
      who +
      "\n" +
      indent +
      "规范值 : " +
      expected +
      "\n" +
      indent +
      "依据   : " +
      wrap_note(basis, 68, cont) +
      "\n"
    }
    Freedom(topic, note) =>
      indent +
      "结论   : 实现自由度，非缺陷（Verdict: IMPLEMENTATION-FREEDOM）\n" +
      indent +
      "议题   : " +
      wrap_note(topic, 68, cont) +
      "\n" +
      indent +
      "说明   : " +
      wrap_note(note, 68, cont) +
      "\n"
    Undetermined(reason) =>
      indent +
      "结论   : 无法判定（Verdict: UNDETERMINED）\n" +
      indent +
      "原因   : " +
      wrap_note(reason, 68, cont) +
      "\n"
  }
}

///|
/// 裁定的一行式摘要，用于回归基线比对。
pub fn judgment_tag(j : Judgment) -> String {
  match j {
    Violation(_, _, _) => "SPEC-VIOLATION"
    Freedom(topic, _) =>
      if topic == "NaN 符号位" {
        "FREEDOM:nan-sign"
      } else if topic == "浮点格式化" {
        "FREEDOM:float-format"
      } else {
        "FREEDOM:other"
      }
    Undetermined(_) => "UNDETERMINED"
  }
}
