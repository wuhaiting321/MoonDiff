// 自带的极简 JSON 实现。
//
// 为什么不引第三方 JSON 库：MoonDiff 的全部价值建立在“四个后端执行同一份
// 纯计算代码，结果必须逐位相同”之上。凡是能把宿主的差异偷偷带进来的依赖，
// 都会让工具的自检失去意义。这里的解析器只处理程序文件用到的子集，
// 且全部逻辑都由 MoonBit 明文实现，行为在任何后端可预测。

///|
/// JSON 值。
///
/// 数字一律保留**原始文本**（`JNum(String)`）而不是解析成 Double：
/// 程序文件里会出现 `9223372036854775807` 这类超出 f64 精度边界的常量，
/// 一旦提前转成浮点就会在解析阶段静默丢失精度，问题会被掩盖到很久以后。
pub(all) enum Json {
  JNull
  JBool(Bool)
  JNum(String)
  JStr(String)
  JArr(Array[Json])
  JObj(Array[(String, Json)])
}

///|
/// 解析游标。用 `err` 标志代替异常的传播，
/// 让解析器在任何后端都不会走异常路径（异常语义本身就是后端差异的来源之一）。
priv struct Cursor {
  cs : Array[Char]
  mut pos : Int32
  mut err : Bool
}

///|
fn peek(c : Cursor) -> Char? {
  if c.pos < c.cs.length() {
    Some(c.cs[c.pos])
  } else {
    None
  }
}

///|
fn skip_ws(c : Cursor) -> Unit {
  while c.pos < c.cs.length() {
    let ch = c.cs[c.pos]
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      c.pos = c.pos + 1
    } else {
      return
    }
  }
}

///|
fn expect(c : Cursor, ch : Char) -> Unit {
  if c.pos < c.cs.length() && c.cs[c.pos] == ch {
    c.pos = c.pos + 1
  } else {
    c.err = true
  }
}

///|
fn parse_value(c : Cursor) -> Json {
  skip_ws(c)
  match peek(c) {
    Some('{') => parse_object(c)
    Some('[') => parse_array(c)
    Some('"') => parse_string(c)
    Some('t') =>
      if c.pos + 3 < c.cs.length() &&
        c.cs[c.pos + 1] == 'r' &&
        c.cs[c.pos + 2] == 'u' &&
        c.cs[c.pos + 3] == 'e' {
        c.pos = c.pos + 4
        JBool(true)
      } else {
        c.err = true
        JNull
      }
    Some('f') =>
      if c.pos + 4 < c.cs.length() &&
        c.cs[c.pos + 1] == 'a' &&
        c.cs[c.pos + 2] == 'l' &&
        c.cs[c.pos + 3] == 's' &&
        c.cs[c.pos + 4] == 'e' {
        c.pos = c.pos + 5
        JBool(false)
      } else {
        c.err = true
        JNull
      }
    Some('n') =>
      if c.pos + 3 < c.cs.length() &&
        c.cs[c.pos + 1] == 'u' &&
        c.cs[c.pos + 2] == 'l' &&
        c.cs[c.pos + 3] == 'l' {
        c.pos = c.pos + 4
        JNull
      } else {
        c.err = true
        JNull
      }
    Some(_) => parse_number(c)
    None => {
      c.err = true
      JNull
    }
  }
}

///|
fn parse_number(c : Cursor) -> Json {
  let start = c.pos
  let mut out = ""
  while c.pos < c.cs.length() {
    let ch = c.cs[c.pos]
    let ok = (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '+' ||
      ch == '.' ||
      ch == 'e' ||
      ch == 'E'
    if ok {
      out = out + ch.to_string()
      c.pos = c.pos + 1
    } else {
      break
    }
  }
  if c.pos == start {
    c.err = true
    JNull
  } else {
    JNum(out)
  }
}

///|
fn hex_val(ch : Char) -> Int32 {
  if ch >= '0' && ch <= '9' {
    ch.to_int() - 48
  } else if ch >= 'a' && ch <= 'f' {
    ch.to_int() - 87
  } else if ch >= 'A' && ch <= 'F' {
    ch.to_int() - 55
  } else {
    -1
  }
}

///|
fn parse_hex4(c : Cursor) -> Int32 {
  let mut v = 0
  let mut i = 0
  while i < 4 {
    if c.pos >= c.cs.length() {
      c.err = true
      return v
    }
    let h = hex_val(c.cs[c.pos])
    if h < 0 {
      c.err = true
      return v
    }
    v = v * 16 + h
    c.pos = c.pos + 1
    i = i + 1
  }
  v
}

///|
fn parse_string(c : Cursor) -> Json {
  expect(c, '"')
  let mut out = ""
  while c.pos < c.cs.length() {
    let ch = c.cs[c.pos]
    c.pos = c.pos + 1
    if ch == '"' {
      return JStr(out)
    }
    if ch == '\\' {
      if c.pos >= c.cs.length() {
        c.err = true
        return JStr(out)
      }
      let esc = c.cs[c.pos]
      c.pos = c.pos + 1
      if esc == 'n' {
        out = out + "\n"
      } else if esc == 't' {
        out = out + "\t"
      } else if esc == 'r' {
        out = out + "\r"
      } else if esc == 'b' {
        out = out + "\u{0008}"
      } else if esc == 'f' {
        out = out + "\u{000C}"
      } else if esc == 'u' {
        let hi = parse_hex4(c)
        if hi >= 0xD800 && hi <= 0xDBFF && c.pos + 1 < c.cs.length() {
          // 代理对：合并成一个码点，保证字符串在任何后端都是同一串码点
          if c.cs[c.pos] == '\\' && c.cs[c.pos + 1] == 'u' {
            c.pos = c.pos + 2
            let lo = parse_hex4(c)
            let cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
            out = out + cp.unsafe_to_char().to_string()
          } else {
            out = out + hi.unsafe_to_char().to_string()
          }
        } else if hi >= 0xD800 && hi <= 0xDFFF {
          c.err = true
        } else {
          out = out + hi.unsafe_to_char().to_string()
        }
      } else {
        // \" \\ \/ 以及其它单字符转义都按字面量处理
        out = out + esc.to_string()
      }
    } else {
      out = out + ch.to_string()
    }
  }
  c.err = true
  JStr(out)
}

///|
fn parse_array(c : Cursor) -> Json {
  expect(c, '[')
  let items : Array[Json] = []
  skip_ws(c)
  if peek(c) == Some(']') {
    c.pos = c.pos + 1
    return JArr(items)
  }
  while !c.err {
    items.push(parse_value(c))
    skip_ws(c)
    match peek(c) {
      Some(',') => {
        c.pos = c.pos + 1
        skip_ws(c)
      }
      Some(']') => {
        c.pos = c.pos + 1
        return JArr(items)
      }
      _ => c.err = true
    }
  }
  JArr(items)
}

///|
fn parse_object(c : Cursor) -> Json {
  expect(c, '{')
  let fields : Array[(String, Json)] = []
  skip_ws(c)
  if peek(c) == Some('}') {
    c.pos = c.pos + 1
    return JObj(fields)
  }
  while !c.err {
    skip_ws(c)
    let k = parse_string(c)
    skip_ws(c)
    expect(c, ':')
    let v = parse_value(c)
    match k {
      JStr(name) => fields.push((name, v))
      _ => c.err = true
    }
    skip_ws(c)
    match peek(c) {
      Some(',') => {
        c.pos = c.pos + 1
        skip_ws(c)
      }
      Some('}') => {
        c.pos = c.pos + 1
        return JObj(fields)
      }
      _ => c.err = true
    }
  }
  JObj(fields)
}

///|
/// 解析一段 JSON 文本。失败返回 `None`（不做异常，见 `Cursor` 的说明）。
pub fn parse_json(src : String) -> Json? {
  let c : Cursor = { cs: src.to_array(), pos: 0, err: false, }
  skip_ws(c)
  let v = parse_value(c)
  skip_ws(c)
  if c.err || c.pos != c.cs.length() {
    None
  } else {
    Some(v)
  }
}

///|
/// 把字符串转义成合法 JSON 字符串字面量（含引号）。
///
/// 增补平面码点按 UTF-16 代理对输出，而不是 `\u{1F600}`，
/// 这样输出文件可以被任何标准 JSON 工具打开。
pub fn json_quote(s : String) -> String {
  let mut out = "\""
  for ch in s.to_array() {
    let n = ch.to_int()
    if n == 34 {
      out = out + "\\\""
    } else if n == 92 {
      out = out + "\\\\"
    } else if n == 10 {
      out = out + "\\n"
    } else if n == 9 {
      out = out + "\\t"
    } else if n == 13 {
      out = out + "\\r"
    } else if n >= 32 && n <= 126 {
      out = out + ch.to_string()
    } else if n <= 0xFFFF {
      out = out + "\\u" + hex4(n)
    } else {
      let cp = n - 0x10000
      let hi = 0xD800 + (cp >> 10)
      let lo = 0xDC00 + (cp & 0x3FF)
      out = out + "\\u" + hex4(hi) + "\\u" + hex4(lo)
    }
  }
  out + "\""
}

///|
fn hex4(n : Int32) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let mut out = ""
  let mut i = 3
  while i >= 0 {
    let nib = (n >> (i * 4)) & 15
    out = out + digits[nib].to_string()
    i = i - 1
  }
  out
}

///|
/// 紧凑序列化（不含任何多余空白，便于逐字节比对与做哈希）。
pub fn dump_json(j : Json) -> String {
  match j {
    JNull => "null"
    JBool(b) => if b { "true" } else { "false" }
    JNum(raw) => raw
    JStr(s) => json_quote(s)
    JArr(items) => {
      let mut out = "["
      let mut i = 0
      while i < items.length() {
        if i > 0 {
          out = out + ","
        }
        out = out + dump_json(items[i])
        i = i + 1
      }
      out + "]"
    }
    JObj(fields) => {
      let mut out = "{"
      let mut i = 0
      while i < fields.length() {
        if i > 0 {
          out = out + ","
        }
        out = out + json_quote(fields[i].0) + ":" + dump_json(fields[i].1)
        i = i + 1
      }
      out + "}"
    }
  }
}
