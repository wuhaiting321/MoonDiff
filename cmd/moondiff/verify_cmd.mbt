// `verify` 子命令与收缩目标步的自动定位。
//
// 两个都放在 CLI 层而不是算法层：它们需要**同时**看到程序与转录，
// 而算法层（spec / core / shrink）各自只应看到自己那份数据。
// 放在这里也让 `moondiff` 仍然保持「只读 argv、只写 stdout」的约束。

///|
/// 从 `params[from..]` 里收集 `name=text` 形式的现场。
fn collect_traces(
  params : Array[String],
  from : Int32,
) -> (Array[String], Array[Array[String]]) {
  let names : Array[String] = []
  let traces : Array[Array[String]] = []
  let mut i = from
  while i < params.length() {
    let (name, text) = split_kv(params[i], i)
    names.push(name)
    traces.push(@report.split_lines(text))
    i = i + 1
  }
  (names, traces)
}

///|
/// 收缩的目标步。
///
/// 有后端终止时不采信转录里的步号：终止方的转录被整体丢弃，
/// `first_cross_divergence` 只会在「有东西突然没了」的第 0 步报分歧，
/// 那个步号指向的是转录的末尾，不是真正出事的指令。
/// 因此改走静态扫描——而且取**裁定所指**的那一条，不是第一个静态候选：
/// `int-overflow` 这类程序先有乘法溢出、后面才是除法终止，
/// 收缩到乘法那一步再复跑，trap 就消失了（本次实测撞到过）。
fn resolve_target(
  p : @spec.Program,
  names : Array[String],
  traces : Array[Array[String]],
) -> (Int32, String) {
  let aborted = abort_flags(traces)
  let mut any_abort = false
  for b in aborted {
    if b {
      any_abort = true
    }
  }
  if any_abort {
    match @oracle.find_judged_site(p, names, traces, aborted) {
      Some(s) => return (s, "有后端终止，取裁定所指的指令")
      None =>
        match @oracle.find_static_site(p) {
          Some(s) => return (s, "有后端终止但无裁定，退化为静态首个候选")
          None => ()
        }
    }
  }
  match @core.first_cross_divergence(traces) {
    Some(d) => (d.step, "首处取值分歧的步号")
    None => (
      if p.ops.length() > 0 {
        p.ops.length() - 1
      } else {
        0
      },
      "各后端一致，取末条指令",
    )
  }
}

///|
/// 在参数里找 `--` 作为「收缩前 / 收缩后」的分界。
fn split_at_dashdash(params : Array[String]) -> Int32 {
  let mut i = 0
  while i < params.length() {
    if params[i] == "--" {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 收缩后复跑验证：左右两半各自是一份现场（`name=转录`）。
fn verify_command(params : Array[String]) -> Unit {
  let at = split_at_dashdash(params)
  if at < 0 {
    println("!E usage: moondiff verify <name=trace>... -- <name=trace>...")
    return
  }
  let (names_a, traces_a) = collect_traces(params, 0)
  // 左半截到 `--` 为止，右半截从它之后开始。
  let left_names : Array[String] = []
  let left_traces : Array[Array[String]] = []
  let mut i = 0
  while i < at && i < names_a.length() {
    left_names.push(names_a[i])
    left_traces.push(traces_a[i])
    i = i + 1
  }
  let (right_names, right_traces) = collect_traces(params, at + 1)
  if right_names.length() == 0 {
    println("!E usage: 缺少收缩后的现场")
    return
  }
  let a = @shrink.sig_of(left_names, left_traces)
  let b = @shrink.sig_of(right_names, right_traces)
  say(@shrink.verify_text(a, b))
}
