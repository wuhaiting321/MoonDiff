// 报告渲染。
//
// 只输出 ASCII：转录本身是纯 ASCII，报告也必须能在任何终端、任何编码页
// 下被逐字节比对——不然工具自己的输出就会成为新的不确定来源。

///|
/// 按 `\n` 切行，丢弃末尾空行。
pub fn split_lines(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for ch in text.to_array() {
    if ch == '\n' {
      out.push(cur)
      cur = ""
    } else if ch != '\r' {
      cur = cur + ch.to_string()
    }
  }
  if cur != "" {
    out.push(cur)
  }
  out
}

///|
/// 右侧补空格到宽度 `n`。
fn pad(s : String, n : Int32) -> String {
  let mut out = s
  while out.length() < n {
    out = out + " "
  }
  out
}

///|
/// 分隔线。
fn rule(widths : Array[Int32]) -> String {
  let mut out = "+"
  for w in widths {
    let mut i = 0
    while i < w + 2 {
      out = out + "-"
      i = i + 1
    }
    out = out + "+"
  }
  out
}

///|
/// 一行的渲染。
fn row(cells : Array[String], widths : Array[Int32]) -> String {
  let mut out = "|"
  let mut i = 0
  while i < cells.length() {
    out = out + " " + pad(cells[i], widths[i]) + " |"
    i = i + 1
  }
  out
}

///|
/// 转录是否正常结束（末行为 `#end <n>` 哨兵）。
pub fn trace_complete(t : Array[String]) -> Bool {
  if t.length() == 0 {
    return false
  }
  let ws = @core.split_ws(t[t.length() - 1])
  ws.length() > 0 && ws[0] == "#end"
}

///|
/// 多后端一致性矩阵。
///
/// 这是整个工具最该被一眼看懂的东西：一列一个后端，一行一个后端，
/// 一眼就能看出谁和谁不一样、在第几步不一样。
pub fn matrix_text(
  names : Array[String],
  traces : Array[Array[String]],
) -> String {
  if traces.length() == 0 {
    return "MoonDiff: 没有可比较的转录\n"
  }
  let aborted : Array[Bool] = []
  for t in traces {
    aborted.push(!trace_complete(t))
  }
  let mut any_abort = false
  for b in aborted {
    if b {
      any_abort = true
    }
  }
  // 基线取第一条“正常完成”的转录：若拿一条崩掉的空转录当基线，
  // 所有健康后端都会被误报成 FAIL，反而掩盖真正的问题。
  let mut base_idx = 0
  let mut bi = 0
  let mut found_base = false
  while bi < traces.length() {
    if !aborted[bi] && !found_base {
      base_idx = bi
      found_base = true
    }
    bi = bi + 1
  }
  let base = traces[base_idx]
  let step_counts : Array[Int32] = []
  for t in traces {
    step_counts.push(t.length())
  }
  let div = @core.first_cross_divergence(traces)
  let passing = div is None

  let mut out = "\nMoonDiff 一致性矩阵\n"
  out = out + "  后端数量 : " + traces.length().to_string() + "\n"
  out = out + "  转录步数 : "
  let mut i = 0
  while i < step_counts.length() {
    if i > 0 {
      out = out + " / "
    }
    out = out + step_counts[i].to_string()
    i = i + 1
  }
  out = out + "\n"
  let verdict = if any_abort {
    "ABORTED（有后端在途中终止，见 note 列）"
  } else if passing {
    "PASS（逐位一致）"
  } else {
    "DIVERGENT（存在跨后端差异）"
  }
  out = out + "  判定     : " + verdict + "\n\n"
  let widths : Array[Int32] = [12, 8, 6, 18]
  out = out + rule(widths) + "\n"
  out = out + row(["backend", "status", "step", "note"], widths) + "\n"
  out = out + rule(widths) + "\n"
  let mut k = 0
  while k < traces.length() {
    let d = @core.first_divergence(base, traces[k])
    let status = if aborted[k] {
      "ABORT"
    } else if d is None {
      "PASS"
    } else {
      "FAIL"
    }
    // 终止性差异下转录被整体丢弃，步号必然归零；显示 "?" 而不是 "0"，
    // 否则读者会以为「第 0 步就不同」，而真相是「不知道在第几步没了」。
    let step = if aborted[k] {
      "?"
    } else {
      match d {
        Some(v) => v.step.to_string()
        None => "-"
      }
    }
    let note = if aborted[k] {
      "无结束哨兵：trap/abort，转录可能被丢弃"
    } else {
      match d {
        Some(v) => {
          let canon = match @core.split_ws(v.left) {
            ws => if ws.length() >= 4 { ws[3] } else { "" }
          }
          let kind = @core.canon_kind(canon)
          if kind == "f64" {
            "f64/" + @core.f64_divergence_side(v.left, v.right)
          } else {
            kind
          }
        }
        None => if k == base_idx { "baseline" } else { "-" }
      }
    }
    out = out + row([names[k], status, step, note], widths) + "\n"
    k = k + 1
  }
  out = out + rule(widths) + "\n"
  if any_abort {
    out = out +
      "\n注意：存在终止性差异（ABORT）。这类差异不会体现为某一步的取值不同，\n"
    out = out +
      "      而是某个后端在途中直接终止；用 scripts/localize.py 可以二分出确切步号。\n"
    return out
  }
  match div {
    Some(d) => {
      out = out + "\n首处分歧 @ step " + d.step.to_string() + "\n"
      let la = @core.split_ws(d.left)
      let lb = @core.split_ws(d.right)
      let opname = if la.length() >= 2 { la[1] } else { "?" }
      out = out + "  原语   : " + opname + "\n"
      out = out + "  左侧   : " + d.left + "\n"
      out = out + "  右侧   : " + d.right + "\n"
      let pos = @core.first_differing_char(d.left, d.right)
      out = out + "  差异位 : 第 " + pos.to_string() + " 个字符\n"
      let class = if la.length() >= 4 {
        @core.f64_divergence_side(
          la[3],
          if lb.length() >= 4 {
            lb[3]
          } else {
            ""
          },
        )
      } else {
        "shape"
      }
      if op_kind_is_float(opname) {
        if class == "format" {
          out = out +
            "  归类   : 数值一致、打印格式不一致（宿主格式化差异）\n"
        } else if class == "bits" {
          out = out +
            "  归类   : 位模式不一致（数值语义差异，优先处理）\n"
        } else {
          out = out +
            "  归类   : 值的形态不一致（长度/结构不同）\n"
        }
      } else {
        out = out + "  归类   : 非浮点差异，见上方两行原文\n"
      }
    }
    None => ()
  }
  out
}

///|
/// 判断原语名是否属于浮点域（用于报告里的归类提示）。
fn op_kind_is_float(name : String) -> Bool {
  let f = name.get_char(0)
  match f {
    Some('f') => true
    _ => {
      let s = name.get_char(1)
      match s {
        Some('2') => true
        _ => false
      }
    }
  }
}

///|
/// 两份转录的差异摘要（用于 `moondiff diff`）。
pub fn diff_text(
  name_a : String,
  a : Array[String],
  name_b : String,
  b : Array[String],
) -> String {
  let d = @core.first_divergence(a, b)
  match d {
    None =>
      "PASS  " +
      name_a +
      " 与 " +
      name_b +
      " 逐位一致（" +
      a.length().to_string() +
      " 步）"
    Some(v) => {
      let mut out = "FAIL  " + name_a + " vs " + name_b + "\n"
      out = out + "  首异步 : " + v.step.to_string() + "\n"
      out = out + "  " + pad(name_a, 8) + ": " + v.left + "\n"
      out = out + "  " + pad(name_b, 8) + ": " + v.right + "\n"
      let pos = @core.first_differing_char(v.left, v.right)
      out = out + "  差异位 : 第 " + pos.to_string() + " 个字符\n"
      // 上下文：分歧前后各两步，便于直接定位数据流
      let from = if v.step >= 2 { v.step - 2 } else { 0 }
      out = out + "  上下文 :\n"
      let mut i = from
      while i < v.step + 3 && i < a.length() {
        out = out + "    " + a[i] + "\n"
        i = i + 1
      }
      out
    }
  }
}
