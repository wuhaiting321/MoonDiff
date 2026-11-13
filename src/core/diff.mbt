// 转录比对：把“四份转录”化简成“第一处分歧 + 上下文”。

///|
/// 一处分歧：发生在第 `step` 步，两个后端分别给出 `left` / `right`。
pub struct Divergence {
  step : Int32
  left : String
  right : String
}

///|
/// 按空白切分一行转录，得到 `[step, reg, canon]`。
///
/// 转录行格式固定为 `#<step> <reg> <canon>`，其中 canon 自身不含空格
/// （字符串已被转义成 `\u{XXXX}`），因此按空格切分是无歧义的。
pub fn split_ws(line : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in line.to_array() {
    if c == ' ' || c == '\t' || c == '\r' {
      if cur != "" {
        out.push(cur)
        cur = ""
      }
    } else {
      cur = cur + c.to_string()
    }
  }
  if cur != "" {
    out.push(cur)
  }
  out
}

///|
/// 两个字符串第一个不同字符的下标；完全相同则返回较短串的长度。
pub fn first_differing_char(a : String, b : String) -> Int32 {
  let ca = a.to_array()
  let cb = b.to_array()
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  let mut i = 0
  while i < n {
    if ca[i] != cb[i] {
      return i
    }
    i = i + 1
  }
  n
}

///|
/// 两条转录共同前缀的行数。
pub fn common_prefix_len(a : Array[String], b : Array[String]) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut i = 0
  while i < n {
    if a[i] != b[i] {
      return i
    }
    i = i + 1
  }
  n
}

///|
/// 两条转录的第一处分歧；完全一致时返回 `None`。
///
/// 长度不同也算分歧：短的那条在第 `n` 行“消失”，
/// 这通常意味着某个后端提前跳出了循环或提前触发了错误。
pub fn first_divergence(a : Array[String], b : Array[String]) -> Divergence? {
  let i = common_prefix_len(a, b)
  if i == a.length() && i == b.length() {
    None
  } else {
    let left = if i < a.length() { a[i] } else { "<eof>" }
    let right = if i < b.length() { b[i] } else { "<eof>" }
    Some({ step: i, left, right, })
  }
}

///|
/// 多份转录的第一处“不一致”。全部一致时返回 `None`。
///
/// 与两两比较不同，这里以**步**为单位：只要某一步上所有后端不全相同，
/// 该步就是分歧点，报告里再单独指出谁是少数派。
pub fn first_cross_divergence(traces : Array[Array[String]]) -> Divergence? {
  if traces.length() < 2 {
    return None
  }
  let mut step = 0
  while true {
    let mut baseline : String? = None
    let mut outlier : String? = None
    let mut i = 0
    let mut ended = 0
    while i < traces.length() {
      let t = traces[i]
      if step >= t.length() {
        ended = ended + 1
      } else if baseline == None {
        baseline = Some(t[step])
      } else if t[step] != baseline.unwrap() && outlier == None {
        outlier = Some(t[step])
      }
      i = i + 1
    }
    if ended > 0 {
      if ended == traces.length() {
        return None
      }
      let shown = if baseline == None { "<eof>" } else { baseline.unwrap() }
      let other = if outlier == None { "<eof>" } else { outlier.unwrap() }
      return Some({ step, left: shown, right: other, })
    }
    if outlier != None {
      return Some({ step, left: baseline.unwrap(), right: outlier.unwrap(), })
    }
    step = step + 1
  }
  None
}

///|
/// 全部转录是否逐行相同。
pub fn all_equal(traces : Array[Array[String]]) -> Bool {
  if traces.length() < 2 {
    return true
  }
  let first = traces[0]
  let mut i = 1
  while i < traces.length() {
    let other = traces[i]
    if other.length() != first.length() {
      return false
    }
    let mut j = 0
    while j < first.length() {
      if first[j] != other[j] {
        return false
      }
      j = j + 1
    }
    i = i + 1
  }
  true
}

///|
/// 每条转录“与多少条其他转录完全一致”。
///
/// 在 3 个以上后端时，这个计数直接给出多数派：
/// 得分最高的是主流行为，得分最低的是需要被举报的那个。
pub fn agreement_scores(traces : Array[Array[String]]) -> Array[Int32] {
  let n = traces.length()
  let scores : Array[Int32] = []
  let mut i = 0
  while i < n {
    let mut s = 0
    let mut j = 0
    while j < n {
      if i != j {
        let d = first_divergence(traces[i], traces[j])
        if d is None {
          s = s + 1
        }
      }
      j = j + 1
    }
    scores.push(s)
    i = i + 1
  }
  scores
}

///|
/// 少数派下标（一致性得分最低者）。全部一致时返回 `-1`。
pub fn outlier_index(traces : Array[Array[String]]) -> Int32 {
  let scores = agreement_scores(traces)
  let mut best = -1
  let mut best_score = 1 << 30
  let mut i = 0
  while i < scores.length() {
    if scores[i] < best_score {
      best_score = scores[i]
      best = i
    }
    i = i + 1
  }
  if best_score == traces.length() - 1 {
    -1
  } else {
    best
  }
}

///|
/// 从规范形式里取出“值类别”标签，用于报告里定位问题域。
pub fn canon_kind(canon : String) -> String {
  if canon == "" {
    return "empty"
  }
  match canon.get_char(0) {
    Some('i') => "int"
    Some('l') => "i64"
    Some('f') => "f64"
    Some('s') => "string"
    Some('a') => "array"
    Some('_') => "unit"
    _ => "unknown"
  }
}

///|
/// 浮点规范形式里“数值位 vs 格式化”哪一段不同。
///
/// `f<16hex>|<fmt>` 的差异如果落在 `|` 之前，是真正的数值/位模式分歧；
/// 落在之后则只是打印格式分歧——两者的严重程度和处理方式完全不同。
pub fn f64_divergence_side(a : String, b : String) -> String {
  let ia = a.find("|")
  let ib = b.find("|")
  if ia == None || ib == None {
    return "bits"
  }
  let ca = ia.unwrap()
  let cb = ib.unwrap()
  let pos = first_differing_char(a, b)
  if pos < ca && pos < cb {
    "bits"
  } else if pos >= ca && pos >= cb {
    "format"
  } else {
    "shape"
  }
}
