// 四后端共用的执行器。
//
// 用法：
//   moon run cmd/driver --target <wasm|wasm-gc|js|native> -- <程序 JSON>
//   moon run cmd/driver --target <...> -- literals
//
// 这个程序会被编译到每一个后端上。它不做任何 I/O、不读时钟、不依赖环境，
// 所以同一份输入在两个后端上输出不同，只能是后端本身的语义差异。
//
// 参数取 `args[末尾]`：js 后端会把 `node` 与脚本路径塞进 argv，
// wasm 后端不会（实测 js 的 argc 比 wasm 多 1）。取末尾元素是唯一
// 在四个后端上都稳定的取参方式。

///|
/// 一条常量折叠探针：源码里写死的表达式，编译期折叠后的结果。
///
/// 这类差异**只能**通过源码级常量表达式观测到：如果表达式在运行时求值，
/// 四个后端会走同一段机器码逻辑；一旦被折叠，各后端的常量求值器就会各显神通。
struct Probe {
  name : String
  text : String
}

///|
/// 常量折叠探针电池。
///
/// 名字固定、顺序固定、输出只有 ASCII，便于逐行比对。
fn literal_battery() -> Array[Probe] {
  [
    { name: "nan_div", text: @core.hex16((0.0 / 0.0).reinterpret_as_int64()), },
    {
      name: "nan_mul_inf",
      text: @core.hex16((0.0 * @double.infinity).reinterpret_as_int64()),
    },
    {
      name: "nan_sub",
      text: @core.hex16(
        (@double.infinity - @double.infinity).reinterpret_as_int64(),
      ),
    },
    { name: "inf_div", text: @core.hex16((1.0 / 0.0).reinterpret_as_int64()), },
    { name: "neg_zero", text: @core.hex16((-0.0).reinterpret_as_int64()), },
    { name: "one_third", text: (1.0 / 3.0).to_string(), },
    { name: "big_float", text: 1.0e21.to_string(), },
    { name: "small_float", text: 1.0e-7.to_string(), },
    {
      name: "subnormal",
      text: 0x0000000000000001L.reinterpret_as_double().to_string(),
    },
    { name: "max_times_two", text: (1.0e308 * 10.0).to_string(), },
    { name: "int_mul_overflow", text: (1000000 * 1000000).to_string(), },
    { name: "int_neg_div", text: (-7 / 2).to_string(), },
    { name: "int_neg_mod", text: (-7 % 2).to_string(), },
    { name: "i64_max_add", text: (9223372036854775807L + 1L).to_string(), },
    { name: "i64_neg_shl", text: (-1L << 3).to_string(), },
    { name: "double_round", text: 2.5.round().to_string(), },
    { name: "double_neg_round", text: 2.5.neg().round().to_string(), },
    { name: "double_trunc", text: 2.9.trunc().to_string(), },
    { name: "double_to_int", text: 2.9.to_int().to_string(), },
    { name: "sqrt_two", text: @core.hex16(2.0.sqrt().reinterpret_as_int64()), },
    { name: "str_units", text: "a中😀".length().to_string(), },
    { name: "str_chars", text: "a中😀".to_array().length().to_string(), },
    { name: "str_cat", text: @core.escape_str("x" + "中"), },
    { name: "str_cmp", text: "a".compare("b").to_string(), },
  ]
}

///|
fn run_literals() -> Unit {
  let probes = literal_battery()
  let mut i = 0
  while i < probes.length() {
    println("L\{i} \{probes[i].name} = \{probes[i].text}")
    i = i + 1
  }
}

///|
/// 末位参数（跨后端稳定的取参方式）。
fn last_arg(args : Array[String]) -> String {
  if args.length() == 0 {
    ""
  } else {
    args[args.length() - 1]
  }
}

///|
fn main {
  let arg = last_arg(@env.args())
  if arg == "literals" {
    run_literals()
    return
  }
  if arg == "" || arg == "help" || arg == "--help" {
    println("usage: driver <program-json> | driver literals")
    return
  }
  match @spec.decode_program(arg) {
    Some(p) => {
      let prof = @core.Profile::parse(p.profile)
      let res = @exec.run_program(p, prof)
      for line in res.trace {
        println(line)
      }
      // 结束哨兵：没有它说明后端在途中终止（trap/abort），
      // 此时已缓冲的输出可能整体丢失，转录长度不能当作步数看。
      println("#end " + res.trace.length().to_string())
    }
    None =>
      // 解析失败时输出单行稳定标记，便于脚本区分「程序坏了」与「后端不一致」
      println("!E parse")
  }
}
