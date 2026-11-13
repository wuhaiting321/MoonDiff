// MoonDiff 命令行。
//
// 设计上刻意只依赖 argv + stdout：不读文件、不读环境、不 spawn 子进程。
// 原因有二：
//   1. 框架自身必须能在四个后端上跑出**完全相同**的报告，否则它就没有资格
//      去断言别人的四后端一致性；
//   2. 编排（并发跑四个后端）交给脚本，工具只负责“算”，职责单一，也便于被 CI 调用。
//
// 因为 js 后端会把 `node` 与脚本路径塞进 argv，这里不假设固定下标，
// 而是扫描出子命令名再取其后的参数。

///|
/// 所有子命令。
fn commands() -> Array[String] {
  [
    "gen", "gencorpus", "run", "diff", "matrix", "shrink", "stats", "probe", "adjudicate",
    "literal", "version", "help",
  ]
}

///|
/// 在 argv 中定位子命令，返回 (子命令, 其后的参数)。
fn locate(
  args : Array[String],
  defaults : (String, Array[String]),
) -> (String, Array[String]) {
  let cmds = commands()
  let mut i = 0
  while i < args.length() {
    let mut j = 0
    while j < cmds.length() {
      if args[i] == cmds[j] {
        let rest : Array[String] = []
        let mut k = i + 1
        while k < args.length() {
          rest.push(args[k])
          k = k + 1
        }
        return (cmds[j], rest)
      }
      j = j + 1
    }
    i = i + 1
  }
  defaults
}

///|
/// 字符串转整数，失败用 `dflt`。
fn to_int(s : String, dflt : Int32) -> Int32 {
  if s == "" {
    return dflt
  }
  let mut i = 0
  let mut neg = false
  if s.get_char(0) == Some('-') {
    neg = true
    i = 1
  }
  let mut acc = 0
  let mut ok = i < s.length()
  while i < s.length() {
    match s.get_char(i) {
      Some(ch) => {
        let d = ch.to_int() - 48
        if d < 0 || d > 9 {
          ok = false
        } else {
          acc = acc * 10 + d
        }
        i = i + 1
      }
      None => ok = false
    }
  }
  if !ok {
    dflt
  } else if neg {
    -acc
  } else {
    acc
  }
}

///|
/// 按第一个 `=` 拆成 (名字, 正文)；没有 `=` 时名字为 `B<i>`。
fn split_kv(arg : String, index : Int32) -> (String, String) {
  match arg.find("=") {
    Some(at) => {
      let mut name = ""
      let mut text = ""
      let mut i = 0
      while i < arg.length() {
        match arg.get_char(i) {
          Some(c) => {
            if i < at {
              name = name + c.to_string()
            } else if i > at {
              text = text + c.to_string()
            }
            i = i + 1
          }
          None => i = arg.length()
        }
      }
      (name, text)
    }
    None => ("B" + index.to_string(), arg)
  }
}

///|
/// 去掉末尾换行后整段输出（避免与 println 叠加出空行）。
fn say(s : String) -> Unit {
  let mut out = s
  while out.length() > 0 && out.get_char(out.length() - 1) == Some('\n') {
    let mut cut = ""
    let mut i = 0
    while i < out.length() - 1 {
      match out.get_char(i) {
        Some(c) => {
          cut = cut + c.to_string()
          i = i + 1
        }
        None => i = out.length()
      }
    }
    out = cut
  }
  println(out)
}

///|
/// 帮助文本。
fn help_text() -> String {
  let mut out = "\nMoonDiff —— MoonBit 跨后端一致性差分验证框架\n\n"
  out = out + "用法：\n"
  out = out +
    "  moondiff gen <seed> <ops> [profile] [regs]   生成一个规格程序（JSON）\n"
  out = out +
    "  moondiff gencorpus <seed> <n> <ops>          生成 n 个程序，每行一个\n"
  out = out +
    "  moondiff run <program-json>                  在当前后端执行并打印转录\n"
  out = out +
    "  moondiff diff <transcript-a> <transcript-b>  两份转录的差异摘要\n"
  out = out +
    "  moondiff matrix [@<program-json>] <name=text>...  多后端矩阵（带程序时附规范裁定）\n"
  out = out +
    "  moondiff shrink <program-json> <step>        收缩到分歧依赖锥\n"
  out = out +
    "  moondiff stats <program-json>                指令分布统计\n"
  out = out +
    "  moondiff probe [name] [profile]              手工边界探针程序\n"
  out = out +
    "  moondiff literal                             常量折叠探针电池\n"
  out = out + "  moondiff version                             版本信息\n\n"
  out = out + "档位（profile）：\n"
  let profs : Array[@core.Profile] = [
    @core.Profile::BitExact,
    @core.Profile::Strict,
    @core.Profile::Semantic,
  ]
  for p in profs {
    out = out + "  " + p.name() + " : " + p.describe() + "\n"
  }
  out
}

///|
/// 统计各值域的指令条数。
fn stats_text(p : @spec.Program) -> String {
  let domains : Array[String] = ["int", "i64", "f64", "cast", "string", "array"]
  let counts : Array[Int32] = [0, 0, 0, 0, 0, 0]
  for op in p.ops {
    let d = @spec.op_kind_domain(op.kind)
    let mut i = 0
    while i < domains.length() {
      if domains[i] == d {
        counts[i] = counts[i] + 1
      }
      i = i + 1
    }
  }
  let mut out = "\n程序统计\n  指令数 : " +
    p.ops.length().to_string() +
    "\n"
  out = out + "  寄存器 : " + p.reg_count().to_string() + "\n"
  out = out + "  档位   : " + p.profile + "\n"
  let mut i = 0
  while i < domains.length() {
    out = out + "  " + domains[i] + " : " + counts[i].to_string() + "\n"
    i = i + 1
  }
  out
}

///|
fn main {
  let (cmd, params) = locate(@env.args(), ("help", []))
  if cmd == "gen" {
    let seed = to_int(if params.length() > 0 { params[0] } else { "1" }, 1)
    let ops = to_int(if params.length() > 1 { params[1] } else { "64" }, 64)
    let prof = if params.length() > 2 { params[2] } else { "strict" }
    let regs = to_int(if params.length() > 3 { params[3] } else { "8" }, 8)
    let p = @gen.generate(@gen.gen_config(seed, ops, regs, prof))
    println(@spec.encode_program(p))
  } else if cmd == "gencorpus" {
    let seed = to_int(if params.length() > 0 { params[0] } else { "1" }, 1)
    let count = to_int(if params.length() > 1 { params[1] } else { "16" }, 16)
    let ops = to_int(if params.length() > 2 { params[2] } else { "64" }, 64)
    let mut i = 0
    while i < count {
      let p = @gen.generate(@gen.gen_config(seed + i, ops, 8, "strict"))
      println(@spec.encode_program(p))
      i = i + 1
    }
  } else if cmd == "run" {
    let text = if params.length() > 0 { params[0] } else { "" }
    match @spec.decode_program(text) {
      Some(p) => {
        let res = @exec.run_program(p, @core.Profile::parse(p.profile))
        for line in res.trace {
          println(line)
        }
      }
      None => println("!E parse")
    }
  } else if cmd == "diff" {
    let a = @report.split_lines(
      if params.length() > 0 {
        params[0]
      } else {
        ""
      },
    )
    let b = @report.split_lines(
      if params.length() > 1 {
        params[1]
      } else {
        ""
      },
    )
    println(@report.diff_text("A", a, "B", b))
  } else if cmd == "matrix" {
    let names : Array[String] = []
    let traces : Array[Array[String]] = []
    // 可选的 `@<程序JSON>` 前缀：带上它，矩阵之后会多出一段规范裁定。
    let mut i = 0
    let mut prog : @spec.Program? = None
    if params.length() > 0 {
      match parse_program_arg(params[0]) {
        Some(p) => {
          prog = Some(p)
          i = 1
        }
        None => ()
      }
    }
    while i < params.length() {
      let (name, text) = split_kv(params[i], i)
      names.push(name)
      traces.push(@report.split_lines(text))
      i = i + 1
    }
    let body = @report.matrix_text(names, traces)
    let verdict = match prog {
      Some(p) => verdict_section(p, names, traces)
      None => ""
    }
    say(body + verdict)
  } else if cmd == "adjudicate" {
    // 输出单行判定标签，供回归基线（scripts/regress.sh）逐行比对。
    let text = if params.length() > 0 { params[0] } else { "" }
    match @spec.decode_program(text) {
      Some(p) => {
        let names : Array[String] = []
        let traces : Array[Array[String]] = []
        let mut i = 1
        while i < params.length() {
          let (name, t) = split_kv(params[i], i)
          names.push(name)
          traces.push(@report.split_lines(t))
          i = i + 1
        }
        match @core.first_cross_divergence(traces) {
          None => println("PASS")
          Some(d) => {
            let aborted = abort_flags(traces)
            println(
              @oracle.judgment_tag(
                @oracle.adjudicate(p, d.step, names, traces, aborted),
              ),
            )
          }
        }
      }
      None => println("PARSE-ERROR")
    }
  } else if cmd == "shrink" {
    let text = if params.length() > 0 { params[0] } else { "" }
    let step = to_int(if params.length() > 1 { params[1] } else { "0" }, 0)
    match @spec.decode_program(text) {
      Some(p) => {
        let small = @shrink.shrink(p, step)
        let st = @shrink.shrink_stats(p, small)
        println(
          "// 收缩：" +
          st.before.to_string() +
          " 条 -> " +
          st.after.to_string() +
          " 条（依赖锥第 " +
          step.to_string() +
          " 步）",
        )
        println(@shrink.render_pseudo(small))
        println("// 压缩后程序：")
        println(@spec.encode_program(small))
      }
      None => println("!E parse")
    }
  } else if cmd == "stats" {
    let text = if params.length() > 0 { params[0] } else { "" }
    match @spec.decode_program(text) {
      Some(p) => say(stats_text(p))
      None => println("!E parse")
    }
  } else if cmd == "probe" {
    run_probe(params)
  } else if cmd == "literal" {
    println(
      "literal 电池在 driver 中：moon run cmd/driver --target <t> -- literals",
    )
  } else if cmd == "version" {
    println("moondiff 0.1.0")
  } else {
    say(help_text())
  }
}
