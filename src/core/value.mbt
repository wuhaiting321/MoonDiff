// MoonBit 跨后端一致性差分验证框架 —— 核心值模型
//
// 本包不依赖任何第三方库，也不做任何 I/O：
// 所有函数都是纯函数，因此在 wasm / wasm-gc / js / native 上
// 执行同一份代码必须得到完全相同的结果。这条约束是工具自身可信的前提。

///|
/// MoonDiff 观测的最小值集合。
///
/// 解释器只在这五种值上运算：任何一处跨后端的语义差异都会在
/// 渲染成规范形式后被记录下来。
pub(all) enum Value {
  VUnit
  VInt(Int32)
  VI64(Int64)
  VF64(Double)
  VStr(String)
  VArr(Array[Int32])
}

///|
/// 把非负整数编码成固定宽度的十六进制串（小写、零填充、无前缀）。
fn hex_fixed(n : Int32, width : Int32) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let mut out = ""
  let mut i = width - 1
  while i >= 0 {
    let shift = i * 4
    let nib = (n >> shift) & 15
    out = out + digits[nib].to_string()
    i = i - 1
  }
  out
}

///|
/// Int64 位模式的 16 位十六进制编码。
///
/// 刻意手写而不用 `to_string(radix=16)`：负数在标准库里的十六进制表示
/// 采用符号加绝对值（`-8000000000000`）而不是补码，这会掩盖真正的位模式差异。
/// 手写实现保证输出就是 64 位的补码位串，逐位可比。
pub fn hex16(v : Int64) -> String {
  let mut out = ""
  let mut i = 0
  while i < 16 {
    let shift = (15 - i) * 4
    let nib = ((v >> shift) & 15L).to_int()
    out = out + hex_fixed(nib, 1)
    i = i + 1
  }
  out
}

///|
/// 把字符码点编码成 `\u{XXXX}` 形式（BMP 用 4 位，增补平面用 6 位）。
fn escape_code(n : Int32) -> String {
  if n <= 0xFFFF {
    "\\u{" + hex_fixed(n, 4) + "}"
  } else if n < 0x100000 {
    "\\u{" + hex_fixed(n, 5) + "}"
  } else {
    "\\u{" + hex_fixed(n, 6) + "}"
  }
}

///|
/// 把字符串编码成**纯 ASCII** 的可比形式。
///
/// 转录文件必须在任何终端、任何编码环境下都能逐字节比对，
/// 因此非可打印 ASCII 一律转义；同时保留可打印 ASCII 原样，
/// 让差异报告对人类仍然可读。
pub fn escape_str(s : String) -> String {
  let mut out = ""
  for c in s.to_array() {
    let n : Int32 = c.to_int()
    if n == 92 {
      out = out + "\\\\"
    } else if n == 34 {
      out = out + "\\\""
    } else if n == 10 {
      out = out + "\\n"
    } else if n == 9 {
      out = out + "\\t"
    } else if n == 13 {
      out = out + "\\r"
    } else if n >= 32 && n <= 126 {
      out = out + c.to_string()
    } else {
      out = out + escape_code(n)
    }
  }
  out
}

///|
/// 字符串的“结构性指纹”：UTF-16 码元数与码点数。
///
/// MoonBit 的 `String` 在不同后端由不同运行时承载，
/// 把两个长度都写进转录，可以让 UTF-8/UTF-16 边界的实现差异立刻显形。
pub fn str_shape(s : String) -> String {
  let units = s.length()
  let chars = s.to_array().length()
  "\{units}/\{chars}"
}

///|
/// 按指定档位把值渲染成规范字符串。
///
/// 渲染结果是**唯一**的比较依据：两个后端只要渲染结果逐字符相同，
/// 就认为它们在该步上语义一致。
pub fn render_value(v : Value, p : Profile) -> String {
  match v {
    VUnit => "_"
    VInt(i) => "i" + i.to_string()
    VI64(l) => "l" + l.to_string()
    VF64(d) => render_f64(d, p)
    VStr(s) => "s" + str_shape(s) + ":\"" + escape_str(s) + "\""
    VArr(a) => {
      let mut out = "a" + a.length().to_string() + "["
      let mut i = 0
      while i < a.length() {
        if i > 0 {
          out = out + ","
        }
        out = out + a[i].to_string()
        i = i + 1
      }
      out + "]"
    }
  }
}

///|
/// 浮点值的规范渲染。
///
/// 这是整个工具最关键的少数几行：浮点差异有三种性质完全不同的来源，
/// 必须在同一个函数里被区分开，否则要么漏报要么淹没在噪声里。
///
/// - `BitExact`：只看 IEEE-754 位模式，NaN 载荷、符号零全部保留。
/// - `Strict`（默认）：位模式 + 宿主格式化结果。后者能抓到
///   “数值相同但打印不同”这一整类真实缺陷（如 `1e+21` 与 `1e21`）。
/// - `Semantic`：把 NaN 折叠成 `fnan`、把 ±0 折叠成 `f0`，
///   用于过滤掉规范允许的差异，只看真正的数值不一致。
pub fn render_f64(d : Double, p : Profile) -> String {
  match p {
    BitExact => "f" + hex16(d.reinterpret_as_int64())
    Strict => "f" + hex16(d.reinterpret_as_int64()) + "|" + d.to_string()
    Semantic =>
      if d.is_nan() {
        "fnan"
      } else if d == 0.0 {
        "f0"
      } else {
        "f" + hex16(d.reinterpret_as_int64()) + "|" + d.to_string()
      }
  }
}
