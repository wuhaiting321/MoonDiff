// String 与编码：有 Unicode 标准兜底，且跨后端最容易在「长度单位」上分叉。

///|
fn case_string_emoji() -> Unit {
  emit("string-emoji", hex_units("a😀b"))
}

///|
fn case_string_cjk() -> Unit {
  emit("string-cjk", hex_units("中文测试"))
}

///|
/// 长度单位：`length()` 报的是码点数还是码元数，是文本处理库的经典分歧点。
fn case_string_length() -> Unit {
  let s = "a😀中"
  emit(
    "string-length",
    s.length().to_string() + " " + s.to_array().length().to_string(),
  )
}

///|
fn case_string_substring() -> Unit {
  let s = "a😀中b"
  let part = s[1:3]
  emit("string-substring", hex_units(part.to_owned()))
}

///|
fn case_string_char_at() -> Unit {
  let s = "a😀中"
  let c = match s.get_char(1) {
    Some(ch) => ch.to_int().to_string()
    None => "none"
  }
  emit("string-char-at", c)
}

///|
/// UTF-8 编码的字节序列：emoji 必须是 4 字节。
fn case_string_utf8() -> Unit {
  emit("string-utf8", @hex.encode(@utf8.encode("a😀中")))
}

///|
fn case_string_utf8_round_trip() -> Unit {
  let src = "a😀中b"
  let back = @utf8.decode_lossy(@utf8.encode(src))
  emit("string-utf8-round-trip", hex_units(back))
}

///|
fn case_string_ascii_round_trip() -> Unit {
  let src = "plain-ascii-123"
  emit("string-ascii-round-trip", @hex.encode(@ascii.encode(src)))
}

///|
fn case_string_compare() -> Unit {
  let a = "abc".compare("abd").to_string()
  let b = "中".compare("文").to_string()
  emit("string-compare", a + " " + b)
}

///|
fn case_base64_round_trip() -> Unit {
  let src = "hello, 世界"
  let enc = @base64.encode(@utf8.encode(src))
  let back = @base64.decode_lossy(enc)
  emit("base64-round-trip", enc + " " + @hex.encode(back))
}
