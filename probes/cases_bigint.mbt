// BigInt：两套实现（bigint_js.mbt / bigint_default.mbt / bigint_wide.mbt）
// 是差异高发区。大整数运算的数学结果是唯一标准，不依赖任何语言条款。

///|
fn case_bigint_mul() -> Unit {
  let a = @bigint.BigInt::from_string("123456789012345678901234567890")
  let b = @bigint.BigInt::from_string("-987654321098765432109876543210")
  emit("bigint-mul", (a * b).to_string())
}

///|
fn case_bigint_add_sub() -> Unit {
  let a = @bigint.BigInt::from_string("999999999999999999999999999999")
  let b = @bigint.BigInt::from_string("1")
  emit("bigint-add-sub", (a + b).to_string() + " " + (a - b).to_string())
}

///|
/// 截断方向：`-7 / 2` 应当是 `-3`（向零截断），不是 `-4`。
fn case_bigint_div_trunc() -> Unit {
  let a = @bigint.BigInt::from_string("-7")
  let b = @bigint.BigInt::from_string("2")
  emit("bigint-div-trunc", (a / b).to_string())
}

///|
/// 取模符号：`-7 % 2` 应当与被除数同号，即 `-1`。
fn case_bigint_mod_sign() -> Unit {
  let a = @bigint.BigInt::from_string("-7")
  let b = @bigint.BigInt::from_string("2")
  emit("bigint-mod-sign", (a % b).to_string())
}

///|
fn case_bigint_pow() -> Unit {
  let a = @bigint.BigInt::from_string("2")
  let e = @bigint.BigInt::from_int(100)
  emit("bigint-pow", a.pow(e).to_string())
}

///|
fn case_bigint_pow_mod() -> Unit {
  let a = @bigint.BigInt::from_string("3")
  let e = @bigint.BigInt::from_int(100)
  let m = @bigint.BigInt::from_int(7)
  emit("bigint-pow-mod", a.pow(e, modulus=m).to_string())
}

///|
/// 进制往返：十进制值 → 十六进制字符串 → 按 16 解析回来。
fn case_bigint_radix() -> Unit {
  let a = @bigint.BigInt::from_string("255")
  let hex = a.to_string(radix=16)
  let back = @bigint.BigInt::from_string(hex, radix=16)
  emit("bigint-radix", hex + " " + back.to_string())
}

///|
fn case_bigint_shift() -> Unit {
  let a = @bigint.BigInt::from_string("1")
  let up = a.shl(64)
  emit("bigint-shift", up.to_string() + " " + up.shr(60).to_string())
}

///|
fn case_bigint_bits() -> Unit {
  let a = @bigint.BigInt::from_string("123456789012345678901234567890")
  emit("bigint-bits", a.bit_length().to_string() + " " + a.ctz().to_string())
}

///|
/// 序列化：大整数的字节表示，直接看十六进制。
fn case_bigint_octets() -> Unit {
  let a = @bigint.BigInt::from_string("123456789012345678901234567890")
  emit("bigint-octets", @hex.encode(a.to_octets()))
}
