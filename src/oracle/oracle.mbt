// 规范裁定：把「两边不一样」升级为「哪边违反了规范、依据在哪一行」。
//
// 差分测试最常见的失败模式是只报告「不一致」，却答不出谁错了。
// 但「谁错了」这句话只有在能引出规范原文时才成立。所以本包把出处做成类型的
// 一部分：`Source` 只能由 `Source::new` 构造，它拒绝空文档、空定位、空原文；
// 而 `Violation` 的最后一个参数就是 `Source`。于是「没有出处的违规裁定」
// 在编译期就写不出来，不靠写代码时的自觉。
//
// 四档裁定对应四种真实情况，不能混为一谈：
//   Violation   —— 有条款要求某个值，某后端给了别的值：缺陷，应当修；
//   Freedom     —— 有条款明文把选择权留给实现（如 wasm 规范的 NaN 符号位）：不是缺陷；
//   Unspecified —— 查过最接近的条款，其中没有规定，各方都能自圆其说：需上游补规范；
//   Undetermined—— 没有匹配到检测规则，或缺操作数：明确承认「判不了」，而不是猜。

///|
/// 一条可核查的规范出处。
///
/// 字段全部私有，只能由 `Source::new` 构造，而它拒绝空白内容——
/// 这是「没有出处不许下结论」的第一道闸门，第二道是 `Violation` 的参数类型。
pub struct Source {
  doc : String
  at : String
  quote : String
}

///|
/// 字符串是否只有空白字符。
fn is_blank(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    match s.get_char(i) {
      Some(c) =>
        if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
          return false
        }
      None => ()
    }
    i = i + 1
  }
  true
}

///|
/// 构造一条出处。任何一项为空白、或 `doc` 含换行（会破坏报告的行结构）
/// 都返回 `None`。
pub fn Source::new(doc : String, at : String, quote : String) -> Source? {
  if is_blank(doc) || is_blank(at) || is_blank(quote) {
    return None
  }
  let mut i = 0
  while i < doc.length() {
    match doc.get_char(i) {
      Some(c) =>
        if c == '\n' || c == '\r' {
          return None
        }
      None => ()
    }
    i = i + 1
  }
  Some({ doc: doc, at: at, quote: quote })
}

///|
/// 出处的单行写法：`文件:行号` 或 `文档:章节`。
pub fn Source::render(self : Source) -> String {
  self.doc + ":" + self.at
}

///|
/// 本项目会做裁定的议题。
///
/// 用枚举而不是字符串：标签由枚举决定，改说明文字不会让回归基线的标签漂移。
pub enum Finding {
  IntWrap
  IntDivOverflow
  NanSign
  FloatFormat
}

///|
/// 议题的稳定标识，用于一行式标签。
fn Finding::slug(self : Finding) -> String {
  match self {
    IntWrap => "int-wrap"
    IntDivOverflow => "int-div-overflow"
    NanSign => "nan-sign"
    FloatFormat => "float-format"
  }
}

///|
/// 议题的人类可读名字。
fn Finding::label(self : Finding) -> String {
  match self {
    IntWrap => "32 位整数加/减/乘的溢出回绕"
    IntDivOverflow => "整数除法/取模的商（余数）不可表示：min_value / -1"
    NanSign => "NaN 的符号位"
    FloatFormat => "浮点数的文本写法"
  }
}

///|
/// 一处分歧的裁定结果。
///
/// 四个档位各自的含义见文件头注释。`Unspecified` 与 `Freedom` 的区别在于
/// 「条款说了什么」：前者是条款没写，后者是条款写明由实现自选。
pub enum Judgment {
  Violation(Finding, Array[String], String, Source)
  Freedom(Finding, String, Source)
  Unspecified(Finding, Array[String], String, Source)
  Undetermined(String)
}

///|
/// 32 位二补数截断。
///
/// 先用 Int64 算完再手工取低 32 位，**不依赖 Int 自身的回绕行为**——
/// 否则就是拿被测的语义给被测对象出期望值，结论会自证。
fn wrap32(x : Int64) -> Int32 {
  let low = x & 0xFFFFFFFFL
  if low >= 0x80000000L {
    (low - 0x100000000L).to_int()
  } else {
    low.to_int()
  }
}

///|
/// `iadd` / `isub` / `imul` 在操作数为常量且**确实溢出**时的规范值。
///
/// 未溢出（此时回绕条款不适用）、或不是这三条原语，返回 `None`。
fn wrap_expected(kn : String, x : Int32, y : Int32) -> String? {
  let wide = if kn == "iadd" {
    x.to_int64() + y.to_int64()
  } else if kn == "isub" {
    x.to_int64() - y.to_int64()
  } else if kn == "imul" {
    x.to_int64() * y.to_int64()
  } else {
    return None
  }
  if wide >= -2147483648L && wide <= 2147483647L {
    return None
  }
  Some("i" + wrap32(wide).to_string())
}

///|
/// 回绕条款的出处：加、减、乘各有自己的条目，引用各自那一行。
fn wrap_source(kn : String) -> Source? {
  if kn == "iadd" {
    Source::new(
      "builtin/intrinsics.mbt",
      "234-246",
      "Returns a new integer that is the sum of the two operands. If the mathematical sum exceeds the range of a 32-bit integer (-2,147,483,648 to 2,147,483,647), the result wraps around according to two's complement rules.",
    )
  } else if kn == "isub" {
    Source::new(
      "builtin/intrinsics.mbt",
      "249-251",
      "Performs subtraction between two 32-bit integers, following standard two's complement arithmetic rules. When the result overflows or underflows, it wraps around within the 32-bit integer range.",
    )
  } else if kn == "imul" {
    Source::new(
      "builtin/intrinsics.mbt",
      "282-283",
      "Returns the product of the two integers. If the result overflows the range of `Int`, it wraps around according to two's complement arithmetic.",
    )
  } else {
    None
  }
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
/// 各后端在该步的取值：终止记 `ABORT`，缺行记 `?`。
///
/// 返回 `(值, 带后端名的值)`：前者只用于判断「有没有分歧」，
/// 后者进报告。两者分开，才不会因为后端名字不同而被当成取值不同。
fn readings(
  names : Array[String],
  results : Array[String],
  aborted : Array[Bool],
) -> (Array[String], Array[String]) {
  let values : Array[String] = []
  let labelled : Array[String] = []
  let mut i = 0
  while i < names.length() {
    let v = if i < aborted.length() && aborted[i] {
      "ABORT"
    } else if i < results.length() && results[i] != "" {
      canon_of(results[i])
    } else {
      "?"
    }
    values.push(v)
    labelled.push(names[i] + "=" + v)
    i = i + 1
  }
  (values, labelled)
}

///|
/// 一组取值是否全同。
fn all_equal(vs : Array[String]) -> Bool {
  let mut i = 1
  while i < vs.length() {
    if vs[i] != vs[0] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 溢出回绕：有条款要求回绕值，谁给了别的值谁违规（`Violation`）。
fn judge_wrap(
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
  let expected = match (const_before(p, op.a, step), const_before(p, op.b, step)) {
    (Some(@core.VInt(x)), Some(@core.VInt(y))) => wrap_expected(kn, x, y)
    _ => None
  }
  let expected = match expected {
    Some(e) => e
    None => return None
  }
  let offenders : Array[String] = []
  let mut k = 0
  while k < names.length() {
    // 终止的后端在本步**没有取值**：它的转录被整体丢弃，可能是本步终止，
    // 也可能是更靠后终止。没有定位就不指控，否则会把「后面才终止」算成
    // 「本步算错了」——实测中 IMul 那一步就撞过这个坑。
    let bad = if k < aborted.length() && aborted[k] {
      false
    } else if k >= results.length() || results[k] == "" {
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
  let src = match wrap_source(kn) {
    Some(s) => s
    None => return None
  }
  Some(Violation(IntWrap, offenders, expected, src))
}

///|
/// `INT_MIN / -1`：四后端取值不同，但规范没有规定这种情况。
///
/// 只报「不一致 + 最近条款没写这一条」，不判谁违规——回绕与终止都能自圆其说，
/// 替规范下判断就是上一版被驳回的那个问题。
fn judge_div(
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
  let (values, labelled) = readings(names, results, aborted)
  if all_equal(values) {
    return None
  }
  // `?` 表示既没终止也没留下取值：定位不可靠，不做归因。
  let mut i = 0
  while i < values.length() {
    if values[i] == "?" {
      return None
    }
    i = i + 1
  }
  let src = match
    Source::new(
      "builtin/intrinsics.mbt",
      "298-309",
      "Throws a panic if `divisor` is zero.",
    ) {
    Some(s) => s
    None => return None
  }
  let gap = "该条目全文只规定「除数为 0 时 panic」，未规定商不可表示（min_value / -1）时应回绕还是终止。回绕一侧与四条算术运算的定宽二补数语义一致，终止一侧与硬件除法异常一致，两者都能自圆其说；本工具只报事实，不替规范下判断。"
  Some(Unspecified(IntDivOverflow, labelled, gap, src))
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
/// 该步是否命中任一检测规则。
fn judge_step(
  p : @spec.Program,
  step : Int32,
  names : Array[String],
  traces : Array[Array[String]],
  aborted : Array[Bool],
) -> Judgment? {
  let at = results_at(traces, step)
  match judge_wrap(p, step, names, at, aborted) {
    Some(j) => Some(j)
    None => judge_div(p, step, names, at, aborted)
  }
}

///|
/// 第 `i` 步是否「可静态判定」：回绕溢出，或 `min_value / -1`。
fn is_static_candidate(p : @spec.Program, i : Int32) -> Bool {
  if i < 0 || i >= p.ops.length() {
    return false
  }
  let op = p.ops[i]
  let kn = @spec.op_kind_name(op.kind)
  let x = const_before(p, op.a, i)
  let y = const_before(p, op.b, i)
  let wrap_hit = match (x, y) {
    (Some(@core.VInt(a)), Some(@core.VInt(b))) => wrap_expected(kn, a, b) is Some(_)
    _ => false
  }
  let div_hit = (kn == "idiv" || kn == "imod") &&
    (match (x, y) {
      (Some(@core.VInt(a)), Some(@core.VInt(b))) => a == -2147483648 && b == -1
      _ => false
    })
  wrap_hit || div_hit
}

///|
/// 静态扫描：程序里第一处「可静态判定」的位置。
///
/// 存在的理由是终止性差异：后端 trap 时连已打印的转录都会被丢弃，
/// 转录里的步号归零，不能作为定位依据。此时按程序结构静态找出真正的
/// 溢出点，才能给出「第几步、哪条原语」的结论。
pub fn find_static_site(p : @spec.Program) -> Int32? {
  let mut i = 0
  while i < p.ops.length() {
    if is_static_candidate(p, i) {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// 按静态候选逐个裁定，返回第一处能下结论的位置。
///
/// 不能只看第一个候选：像 `int-overflow` 那样程序里先有乘法溢出、
/// 后面才是除法终止，第一个候选往往拿不到结论，必须继续往后找。
pub fn find_judged_site(
  p : @spec.Program,
  names : Array[String],
  traces : Array[Array[String]],
  aborted : Array[Bool],
) -> Int32? {
  let mut i = 0
  while i < p.ops.length() {
    if is_static_candidate(p, i) {
      match judge_step(p, i, names, traces, aborted) {
        Some(_) => return Some(i)
        None => ()
      }
    }
    i = i + 1
  }
  None
}

///|
/// 静态定位 + 裁定：给出「裁定所指那一条指令」的判定。
fn judge_static(
  p : @spec.Program,
  names : Array[String],
  traces : Array[Array[String]],
  aborted : Array[Bool],
) -> Judgment? {
  match find_judged_site(p, names, traces, aborted) {
    Some(s) => judge_step(p, s, names, traces, aborted)
    None => None
  }
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
  let src = match
    Source::new(
      "webassembly.github.io/spec/core/exec/numerics.html",
      "NaN propagation",
      "When the result of a floating-point operator other than fneg, fabs, or fcopysign is a NaN, then its sign is non-deterministic and the payload is computed as follows:",
    ) {
    Some(s) => s
    None => return None
  }
  let note = "条款明文说符号位不确定，因此「各后端不同」本身不是缺陷。但同一表达式在不同编译路径（常量折叠 vs 运行期）给出不同位模式，会让依赖位序列化的代码（哈希、缓存键、黄金文件比对）出现平台相关行为，工程上应显式归一化。"
  Some(Freedom(NanSign, note, src))
}

///|
/// 数值位相同、只有格式化文本不同。
fn judge_float_format(
  names : Array[String],
  results : Array[String],
  aborted : Array[Bool],
) -> Judgment? {
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
  let (_, labelled) = readings(names, results, aborted)
  let src = match
    Source::new(
      "builtin/double.mbt",
      "274-296",
      "Returns a string representation of the double-precision floating-point number.",
    ) {
    Some(s) => s
    None => return None
  }
  let gap = "该条目只承诺「返回字符串表示」，未规定指数写法（1e+21 与 1e21）、尾随零与有效位数。位模式一致时文本差异不影响计算结果，但会让面向文本的黄金文件比对、日志比对失效。"
  Some(Unspecified(FloatFormat, labelled, gap, src))
}

///|
/// 对一处跨后端分歧给出裁定。
///
/// `results[k]` 是第 k 个后端在该步的实际转录行，缺行传空串；
/// `aborted[k]` 表示该后端在途中终止。
///
/// 判定顺序刻意固定：先查有条款支撑的硬缺陷，再查「无条款的不一致」，
/// 最后查实现自由度。顺序反了就会把真缺陷混进「自由度」里放过。
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
  match judge_step(p, step, names, traces, aborted) {
    Some(j) => return j
    None => ()
  }
  // 有后端终止时，转录被丢弃、步号归零，改用静态扫描逐点定位。
  if any_abort {
    match judge_static(p, names, traces, aborted) {
      Some(j) => return j
      None => ()
    }
  }
  let at = results_at(traces, step)
  match judge_nan_sign(at) {
    Some(j) => return j
    None => ()
  }
  match judge_float_format(names, at, aborted) {
    Some(j) => return j
    None => ()
  }
  Undetermined(
    "该步没有匹配到已实现的检测规则（溢出回绕 / min÷-1 / NaN 符号位 / 浮点文本），或不满足规则前提（操作数为常量）。若某后端在途中终止，确切步号需用 scripts/localize.py 二分确认；此处不下结论，也不用猜。",
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
/// 出处两行：`依据` 给出定位，`原文` 给出可逐字核对的内容。
fn source_text(src : Source, indent : String, cont : String) -> String {
  indent +
  "依据   : " +
  src.render() +
  "\n" +
  indent +
  "原文   : \"" +
  wrap_note(src.quote, 64, cont) +
  "\"\n"
}

///|
/// 裁定的可读文本（纯 ASCII 之外只用中文，不含颜色转义）。
pub fn judgment_text(j : Judgment, indent : String) -> String {
  let cont = indent + "         "
  match j {
    Violation(finding, offenders, expected, src) => {
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
      "结论   : 违反语言规范，有条款支撑（Verdict: SPEC-VIOLATION）\n" +
      indent +
      "议题   : " +
      finding.label() +
      "\n" +
      indent +
      "违规方 : " +
      who +
      "\n" +
      indent +
      "规范值 : " +
      expected +
      "\n" +
      source_text(src, indent, cont)
    }
    Unspecified(finding, labelled, gap, src) => {
      let mut vals = ""
      let mut i = 0
      while i < labelled.length() {
        if i > 0 {
          vals = vals + ", "
        }
        vals = vals + labelled[i]
        i = i + 1
      }
      indent +
      "结论   : 无条款不一致（Verdict: UNSPECIFIED-DIVERGENCE）\n" +
      indent +
      "议题   : " +
      finding.label() +
      "\n" +
      indent +
      "分歧   : " +
      wrap_note(vals, 64, cont) +
      "\n" +
      indent +
      "缺口   : " +
      wrap_note(gap, 64, cont) +
      "\n" +
      source_text(src, indent, cont)
    }
    Freedom(finding, note, src) =>
      indent +
      "结论   : 实现自由度，非缺陷（Verdict: IMPLEMENTATION-FREEDOM）\n" +
      indent +
      "议题   : " +
      finding.label() +
      "\n" +
      source_text(src, indent, cont) +
      indent +
      "说明   : " +
      wrap_note(note, 64, cont) +
      "\n"
    Undetermined(reason) =>
      indent +
      "结论   : 无法判定（Verdict: UNDETERMINED）\n" +
      indent +
      "原因   : " +
      wrap_note(reason, 64, cont) +
      "\n"
  }
}

///|
/// 裁定的一行式摘要，用于回归基线比对。
pub fn judgment_tag(j : Judgment) -> String {
  match j {
    Violation(f, _, _, _) => "SPEC-VIOLATION:" + f.slug()
    Freedom(f, _, _) => "FREEDOM:" + f.slug()
    Unspecified(f, _, _, _) => "UNSPECIFIED-DIVERGENCE:" + f.slug()
    Undetermined(_) => "UNDETERMINED"
  }
}
