// 收缩后的复现验证。
//
// 为什么要这一层：收缩的正确性是可以静态论证的（依赖闭包保证被保留指令的
// 输入一个字节都没变），但「不需要重跑」在被检查之前只是一个承诺。
// 初审的意见正是冲着这一点：机制写得再对，没有一次真实的再执行，
// 读者就只能选择相信或不信。
//
// 所以这里把承诺换成可执行的事实：收缩出来的程序**真的再交给同一批后端
// 编译执行一次**，然后比较收缩前后两份现场的五项特征。五项全同才算复现。
//
// 比较的是「特征」而不是「原始转录」，因为收缩会删掉目标步之前的支线指令，
// 步号必然重排——拿行文本逐字比对会把正确的收缩判成失败。
// 特征里不含步号：步号重排是预期行为，不是差异。

///|
/// 一次执行的现场特征。
///
/// 故意做成「可枚举的几项」而不是一个布尔值：验证失败时要说得出
/// 是哪一项变了，否则「verified」这个词本身又变成不可核查的断言。
///
/// 两个面分开记：**终止**（哪些后端没打完）与**取值**（活下来的后端之间
/// 是否分歧）。不分开的话，某个后端 trap 会让转录在第 0 步「凭空消失」，
/// 于是 `first_cross_divergence` 把截断报成「第 0 步取值不同」——
/// 那是转录长度的差异，不是任何一条指令算出来的值的差异。
pub struct Sig {
  backends : Int32
  /// 未打印结束哨兵的后端名，按输入顺序。
  aborted : Array[String]
  /// 存活后端之间是否存在取值分歧。
  divergent : Bool
  /// 取值分歧所在步（收缩后会重排，仅用于展示，不参与比较）。
  step : Int32
  /// 取值分歧的原语名。
  op : String
  /// 取值分歧两侧的规范值。
  left : String
  right : String
}

///|
/// 复现判定。
pub enum Repro {
  Reproduced
  NotReproduced(String)
}

///|
/// 取第 `idx` 个空白分隔字段；越界返回空串。
fn tok(line : String, idx : Int32) -> String {
  let ws = @core.split_ws(line)
  if idx < ws.length() {
    ws[idx]
  } else {
    ""
  }
}

///|
/// 把 `name=...` 形式的字段拼成逗号串；空数组返回 `-`。
fn join_names(xs : Array[String]) -> String {
  if xs.length() == 0 {
    return "-"
  }
  let mut out = ""
  let mut i = 0
  while i < xs.length() {
    if i > 0 {
      out = out + ","
    }
    out = out + xs[i]
    i = i + 1
  }
  out
}

///|
/// 从一份执行的转录里提取特征。
pub fn sig_of(names : Array[String], traces : Array[Array[String]]) -> Sig {
  let aborted : Array[String] = []
  // 存活后端：它们的转录完整，取值之间才有可比性。
  let alive : Array[Array[String]] = []
  let mut i = 0
  while i < traces.length() {
    if @report.trace_complete(traces[i]) {
      alive.push(traces[i])
    } else {
      aborted.push(names[i])
    }
    i = i + 1
  }
  match @core.first_cross_divergence(alive) {
    Some(d) => {
      // 转录行形如 `#3 idiv r2 i-2147483648`：字段 1 是原语，字段 3 是规范值。
      let lp = tok(d.left, 1)
      let op = if lp == "" { tok(d.right, 1) } else { lp }
      Sig::{
        backends: traces.length(),
        aborted,
        divergent: true,
        step: d.step,
        op,
        left: tok(d.left, 3),
        right: tok(d.right, 3),
      }
    }
    None =>
      Sig::{
        backends: traces.length(),
        aborted,
        divergent: false,
        step: -1,
        op: "-",
        left: "",
        right: "",
      }
  }
}

///|
/// 比较收缩前后的现场，判定分歧是否真的还在。
///
/// 检查顺序按「最容易掩盖问题的程度」排：先确认原来确实有分歧可复现，
/// 再看参与的后端是否还是同一批、终止的是不是还是那几个，
/// 最后才看取值。顺序反了的话，一个后端掉队会被报成「取值不同」，
/// 把真正的原因藏起来。
pub fn compare(orig : Sig, shrunk : Sig) -> Repro {
  // 「有分歧」= 有后端终止，或存活后端之间取值不一致。两者任一成立。
  let orig_has = orig.aborted.length() > 0 || orig.divergent
  let shrunk_has = shrunk.aborted.length() > 0 || shrunk.divergent
  if orig.backends < 2 {
    return NotReproduced("参与比较的后端不足 2 个，没有可复现的分歧")
  }
  if !orig_has {
    return NotReproduced("原程序在该步没有分歧，没有可复现的对象")
  }
  if orig.backends != shrunk.backends {
    return NotReproduced(
      "后端数量变了：" +
      orig.backends.to_string() +
      " -> " +
      shrunk.backends.to_string() +
      "（收缩后应交给同一批后端执行）",
    )
  }
  if join_names(orig.aborted) != join_names(shrunk.aborted) {
    return NotReproduced(
      "终止的后端集合变了：" +
      join_names(orig.aborted) +
      " -> " +
      join_names(shrunk.aborted),
    )
  }
  if !shrunk_has {
    return NotReproduced("收缩后各后端逐位一致，分歧消失（收缩不是语义空操作）")
  }
  if orig.divergent != shrunk.divergent {
    return NotReproduced(
      "分歧的形态变了：收缩前" +
      (if orig.divergent { "是取值分歧" } else { "只有终止" }) +
      "，收缩后" +
      (if shrunk.divergent { "是取值分歧" } else { "只有终止" }),
    )
  }
  if orig.divergent && orig.op != shrunk.op {
    return NotReproduced(
      "取值分歧的原语变了：" + orig.op + " -> " + shrunk.op,
    )
  }
  if orig.divergent && (orig.left != shrunk.left || orig.right != shrunk.right) {
    return NotReproduced(
      "取值分歧的两侧值变了：" +
      orig.left +
      " vs " +
      orig.right +
      " -> " +
      shrunk.left +
      " vs " +
      shrunk.right,
    )
  }
  Reproduced
}

///|
/// 一行摘要，用于验证报告。
fn summary(s : Sig) -> String {
  let mut out = s.backends.to_string() + " 后端"
  if s.aborted.length() > 0 {
    out = out + " | 终止: " + join_names(s.aborted)
  } else {
    out = out + " | 终止: 无"
  }
  if s.divergent {
    let l = if s.left == "" { "<eof>" } else { s.left }
    let r = if s.right == "" { "<eof>" } else { s.right }
    out = out +
      " | 取值分歧: step " +
      s.step.to_string() +
      " " +
      s.op +
      " [" +
      l +
      " vs " +
      r +
      "]"
  } else if s.aborted.length() > 0 {
    out = out + " | 取值分歧: 无（存活方一致）"
  } else {
    out = out + " | 取值分歧: 无（逐位一致）"
  }
  out
}

///|
/// 验证报告。末行固定为 `verified: reproduce` 或 `NOT-REPRODUCED`，
/// 两者都是字面量，便于脚本与 CI 精确匹配——不做模糊判断。
pub fn verify_text(orig : Sig, shrunk : Sig) -> String {
  let mut out = "\n收缩后复跑验证（重跑实测，非承诺）\n"
  out = out + "  收缩前   : " + summary(orig) + "\n"
  out = out + "  收缩后   : " + summary(shrunk) + "\n"
  match compare(orig, shrunk) {
    Reproduced => {
      out = out +
        "  说明     : 后端集合、终止集合、取值分歧的原语与两侧值均与收缩前相同\n"
      out + "验证结果 : verified: reproduce\n"
    }
    NotReproduced(reason) => {
      out = out + "  原因     : " + reason + "\n"
      out + "验证结果 : NOT-REPRODUCED\n"
    }
  }
}
