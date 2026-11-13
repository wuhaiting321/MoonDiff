// 把规范裁定接到矩阵输出上。
//
// 矩阵只说「谁和谁不一样」，裁定说「谁错了、依据是什么」。
// 两段拼在一起，读者才不需要自己拿差异去翻语言规范。

///|
/// 各后端是否在途中终止（缺少结束哨兵）。
fn abort_flags(traces : Array[Array[String]]) -> Array[Bool] {
  let out : Array[Bool] = []
  for t in traces {
    out.push(!@report.trace_complete(t))
  }
  out
}

///|
/// 为一组转录生成裁定段；完全一致时返回空串。
fn verdict_section(
  prog : @spec.Program,
  names : Array[String],
  traces : Array[Array[String]],
) -> String {
  let aborted = abort_flags(traces)
  match @core.first_cross_divergence(traces) {
    None => ""
    Some(d) => {
      // 把整份转录交给裁定器：它会在静态定位后按**真正的溢出步**重新取值。
      let j = @oracle.adjudicate(prog, d.step, names, traces, aborted)
      "\n裁定\n" + @oracle.judgment_text(j, "  ")
    }
  }
}

///|
/// 解析 `@<程序JSON>` 形式的前缀参数；不是这种形式返回 `None`。
pub fn parse_program_arg(a : String) -> @spec.Program? {
  if a.length() < 2 {
    return None
  }
  match a.get_char(0) {
    Some('@') => @spec.decode_program(a[1:].to_owned())
    _ => None
  }
}
