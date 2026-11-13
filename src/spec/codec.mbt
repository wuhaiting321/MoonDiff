// 程序文件的编解码。
//
// 文本格式（单行、紧凑、纯 ASCII）：
//   {"seed":1,"profile":"strict","ops":[["iset",0,42],["iadd",2,0,1],...]}
//
// 两条硬约束：
//   - 64 位整数一律用**十进制字符串**承载，浮点一律用**16 位十六进制位串**承载。
//     只要中间经过一次 JSON 数字，就会在 f64 精度边界上静默失真，
//     而这类失真恰好会把工具要抓的差异提前抹平。
//   - 编码结果与后端无关：`dump_json` 是纯字符串拼接，不含任何宿主相关行为。

///|
/// 从对象里取字段。
fn obj_get(j : Json, key : String) -> Json? {
  match j {
    JObj(fields) => {
      let mut i = 0
      let mut found : Json? = None
      while i < fields.length() {
        if fields[i].0 == key {
          found = Some(fields[i].1)
        }
        i = i + 1
      }
      found
    }
    _ => None
  }
}

///|
/// 解析十进制字符串为 `Int`。
fn parse_int_str(s : String) -> Int32? {
  let mut i = 0
  let mut neg = false
  if s.get_char(0) == Some('-') {
    neg = true
    i = 1
  }
  if i >= s.length() {
    return None
  }
  let mut acc = 0
  while i < s.length() {
    match s.get_char(i) {
      Some(ch) => {
        let d = ch.to_int() - 48
        if d < 0 || d > 9 {
          return None
        }
        acc = acc * 10 - d
        i = i + 1
      }
      None => return None
    }
  }
  if neg {
    Some(acc)
  } else if acc == -2147483647 - 1 {
    None
  } else {
    Some(-acc)
  }
}

///|
/// 解析十进制字符串为 `Int64`。
///
/// 全程以**负数**累加：这样 `-9223372036854775808`（Int64 下界）
/// 在解析过程中不会被溢出截断，正数则最后取反。
fn parse_i64_str(s : String) -> Int64? {
  let mut i = 0
  let mut neg = false
  if s.get_char(0) == Some('-') {
    neg = true
    i = 1
  }
  if i >= s.length() {
    return None
  }
  let mut acc : Int64 = 0L
  while i < s.length() {
    match s.get_char(i) {
      Some(ch) => {
        let d = ch.to_int() - 48
        if d < 0 || d > 9 {
          return None
        }
        acc = acc * 10L - d.to_int64()
        i = i + 1
      }
      None => return None
    }
  }
  if neg {
    Some(acc)
  } else if acc == 0x8000000000000000L {
    None
  } else {
    Some(-acc)
  }
}

///|
/// 解析 16 位十六进制位串为 `Int64`（补码，不经浮点）。
fn parse_hex16(s : String) -> Int64? {
  if s.length() != 16 {
    return None
  }
  let mut acc : Int64 = 0L
  let mut i = 0
  while i < 16 {
    match s.get_char(i) {
      Some(ch) => {
        let d = if ch >= '0' && ch <= '9' {
          ch.to_int() - 48
        } else if ch >= 'a' && ch <= 'f' {
          ch.to_int() - 87
        } else if ch >= 'A' && ch <= 'F' {
          ch.to_int() - 55
        } else {
          -1
        }
        if d < 0 {
          return None
        }
        acc = (acc << 4) | d.to_int64()
        i = i + 1
      }
      None => return None
    }
  }
  Some(acc)
}

///|
/// 取整数。
fn as_int(j : Json) -> Int32? {
  match j {
    JNum(raw) => parse_int_str(raw)
    _ => None
  }
}

///|
/// 取字符串。
fn as_str(j : Json) -> String? {
  match j {
    JStr(s) => Some(s)
    _ => None
  }
}

///|
/// 取数组。
fn as_arr(j : Json) -> Array[Json]? {
  match j {
    JArr(items) => Some(items)
    _ => None
  }
}

///|
/// 把一条指令编码成 JSON 数组。
pub fn encode_op(op : Op) -> Json {
  let name = JStr(op_kind_name(op.kind))
  match op_kind_arity(op.kind) {
    0 =>
      match op.kind {
        LSet =>
          JArr([name, JNum(op.dst.to_string()), JStr(op.imm_l.to_string())])
        FSet =>
          JArr([
            name,
            JNum(op.dst.to_string()),
            JStr("@" + @core.hex16(op.imm_f.reinterpret_as_int64())),
          ])
        SSet => JArr([name, JNum(op.dst.to_string()), JStr(op.imm_s)])
        ASet => {
          let nums : Array[Json] = []
          for v in op.imm_a {
            nums.push(JNum(v.to_string()))
          }
          JArr([name, JNum(op.dst.to_string()), JArr(nums)])
        }
        _ => JArr([name, JNum(op.dst.to_string()), JNum(op.imm_i.to_string())])
      }
    1 => JArr([name, JNum(op.dst.to_string()), JNum(op.a.to_string())])
    _ =>
      JArr([
        name,
        JNum(op.dst.to_string()),
        JNum(op.a.to_string()),
        JNum(op.b.to_string()),
      ])
  }
}

///|
/// 解码一条指令。
fn decode_op(j : Json) -> Op? {
  match j {
    JArr(items) => {
      if items.length() < 2 {
        return None
      }
      let name = match items[0] {
        JStr(s) => s
        _ => return None
      }
      let kind = match op_kind_of_name(name) {
        Some(k) => k
        None => return None
      }
      let dst = match as_int(items[1]) {
        Some(v) => v
        None => return None
      }
      let arity = op_kind_arity(kind)
      if arity == 0 {
        match kind {
          LSet => {
            if items.length() < 3 {
              return None
            }
            let raw = match as_str(items[2]) {
              Some(s) => s
              None => return None
            }
            match parse_i64_str(raw) {
              Some(v) => Some(Op::const_l(dst, v))
              None => None
            }
          }
          FSet => {
            if items.length() < 3 {
              return None
            }
            let raw = match as_str(items[2]) {
              Some(s) => s
              None => return None
            }
            let mut hexs = ""
            let mut hi = 0
            if raw.length() > 0 && raw.get_char(0) == Some('@') {
              hi = 1
            }
            while hi < raw.length() {
              match raw.get_char(hi) {
                Some(c) => {
                  hexs = hexs + c.to_string()
                  hi = hi + 1
                }
                None => hi = raw.length()
              }
            }
            match parse_hex16(hexs) {
              Some(bits) => Some(Op::const_f(dst, bits))
              None => None
            }
          }
          SSet => {
            if items.length() < 3 {
              return None
            }
            match as_str(items[2]) {
              Some(s) => Some(Op::const_s(dst, s))
              None => None
            }
          }
          ASet => {
            if items.length() < 3 {
              return None
            }
            match as_arr(items[2]) {
              Some(arr) => {
                let vals : Array[Int32] = []
                let mut ok = true
                for item in arr {
                  match as_int(item) {
                    Some(v) => vals.push(v)
                    None => ok = false
                  }
                }
                if ok {
                  Some(Op::const_a(dst, vals))
                } else {
                  None
                }
              }
              None => None
            }
          }
          _ => {
            if items.length() < 3 {
              return None
            }
            match as_int(items[2]) {
              Some(v) => Some(Op::const_i(dst, v))
              None => None
            }
          }
        }
      } else if arity == 1 {
        if items.length() < 3 {
          return None
        }
        match as_int(items[2]) {
          Some(a) => Some(Op::unary(kind, dst, a))
          None => None
        }
      } else {
        if items.length() < 4 {
          return None
        }
        let a = as_int(items[2])
        let b = as_int(items[3])
        match (a, b) {
          (Some(x), Some(y)) => Some(Op::binary(kind, dst, x, y))
          _ => None
        }
      }
    }
    _ => None
  }
}

///|
/// 程序序列化成单行 JSON 文本。
pub fn encode_program(p : Program) -> String {
  let ops : Array[Json] = []
  for op in p.ops {
    ops.push(encode_op(op))
  }
  let root = JObj([
    ("seed", JNum(p.seed.to_string())),
    ("profile", JStr(p.profile)),
    ("ops", JArr(ops)),
  ])
  dump_json(root)
}

///|
/// 从 JSON 文本还原程序。
pub fn decode_program(text : String) -> Program? {
  match parse_json(text) {
    Some(root) => {
      let seed = match obj_get(root, "seed") {
        Some(j) =>
          match as_int(j) {
            Some(v) => v
            None => 0
          }
        None => 0
      }
      let profile = match obj_get(root, "profile") {
        Some(JStr(s)) => s
        _ => "strict"
      }
      match obj_get(root, "ops") {
        Some(JArr(items)) => {
          let ops : Array[Op] = []
          let mut ok = true
          for item in items {
            match decode_op(item) {
              Some(op) => ops.push(op)
              None => ok = false
            }
          }
          if ok {
            Some(Program::new(seed, profile, ops))
          } else {
            None
          }
        }
        _ => None
      }
    }
    None => None
  }
}
