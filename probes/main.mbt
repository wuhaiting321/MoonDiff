// 源码探针：直接用 MoonBit 调用真实包的公开 API，不做任何 DSL 转写。
//
// 设计约束：
// 1. 不 import 本项目任何包（`wuhaiting321/moondiff`），证明「不写指令也能用」；
// 2. 每个 case 打印一行纯 ASCII，四后端逐字节比对；
// 3. 非 ASCII 值一律转成码点十六进制，避免终端编码造成假差异。

///|
/// 把字符串渲染成「码点数 + 每个码点的十六进制」，纯 ASCII。
fn hex_units(s : String) -> String {
  let us = s.to_array()
  let mut out = "[" + us.length().to_string() + "]"
  for u in us {
    out = out + " " + u.to_int().to_string()
  }
  out
}

///|
/// Int64 位模式的 16 位十六进制（补码，不用有符号十六进制）。
fn hex16(v : Int64) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let mut out = ""
  let mut i = 15
  while i >= 0 {
    let nib = ((v >> (i * 4)) & 15L).to_int()
    out = out + digits[nib].to_string()
    i = i - 1
  }
  out
}

///|
fn emit(name : String, value : String) -> Unit {
  println(name + " = " + value)
}

///|
fn main {
  let args = @env.args()
  let name = if args.length() > 0 { args[args.length() - 1] } else { "" }
  match name {
    "bigint-mul" => case_bigint_mul()
    "bigint-add-sub" => case_bigint_add_sub()
    "bigint-div-trunc" => case_bigint_div_trunc()
    "bigint-mod-sign" => case_bigint_mod_sign()
    "bigint-pow" => case_bigint_pow()
    "bigint-pow-mod" => case_bigint_pow_mod()
    "bigint-radix" => case_bigint_radix()
    "bigint-shift" => case_bigint_shift()
    "bigint-bits" => case_bigint_bits()
    "bigint-octets" => case_bigint_octets()
    "double-thirds" => case_double_thirds()
    "double-fmt-big" => case_double_fmt_big()
    "double-fmt-small" => case_double_fmt_small()
    "double-round-trip" => case_double_round_trip()
    "double-subnormal" => case_double_subnormal()
    "double-rounding" => case_double_rounding()
    "double-overflow" => case_double_overflow()
    "double-nan-literal" => case_double_nan_literal()
    "double-nan-runtime" => case_double_nan_runtime()
    "double-to-int" => case_double_to_int()
    "string-emoji" => case_string_emoji()
    "string-cjk" => case_string_cjk()
    "string-length" => case_string_length()
    "string-substring" => case_string_substring()
    "string-char-at" => case_string_char_at()
    "string-utf8" => case_string_utf8()
    "string-utf8-round-trip" => case_string_utf8_round_trip()
    "string-ascii-round-trip" => case_string_ascii_round_trip()
    "string-compare" => case_string_compare()
    "base64-round-trip" => case_base64_round_trip()
    "" | "list" => {
      for c in cases() {
        println(c)
      }
    }
    _ => {
      println("unknown case: " + name)
      println("run with `list` to print all case names")
    }
  }
}

///|
/// 全部 case 名。脚本用它枚举，避免把清单写两遍。
fn cases() -> Array[String] {
  [
    "bigint-mul", "bigint-add-sub", "bigint-div-trunc", "bigint-mod-sign",
    "bigint-pow", "bigint-pow-mod", "bigint-radix", "bigint-shift",
    "bigint-bits", "bigint-octets", "double-thirds", "double-fmt-big",
    "double-fmt-small", "double-round-trip", "double-subnormal",
    "double-rounding", "double-overflow", "double-nan-literal",
    "double-nan-runtime", "double-to-int", "string-emoji", "string-cjk",
    "string-length", "string-substring", "string-char-at", "string-utf8",
    "string-utf8-round-trip", "string-ascii-round-trip", "string-compare",
    "base64-round-trip",
  ]
}
