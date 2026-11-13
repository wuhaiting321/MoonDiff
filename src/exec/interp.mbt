// 规格运行时：把直线程序解释执行成一份「转录」。
//
// 关键约定：解释器本身**不做任何算术**，它只是把每条指令转发给宿主的
// 核心原语（`/`、`to_double()`、`len()`、`compare()`……）。
// 这样同一份解释器代码在四个后端上跑，得到的差异必然来自后端本身，
// 而不是来自 MoonDiff 自己的实现——这是工具可信度的来源。

///|
/// 一次执行的产物。
pub struct ExecResult {
  trace : Array[String]
  coverage : Array[Int32]
}

///|
/// 覆盖位图。边编号 = 原语签名 * 2 + 分支（0 正常 / 1 特殊路径），
/// 用签名而不是枚举下标，是为了在新增指令时不破坏已有的语料。
pub struct Coverage {
  hits : Array[Bool]
}

///|
/// 新建一张空覆盖表。
pub fn Coverage::new() -> Coverage {
  { hits: Array::make(2048, false), }
}

///|
/// 标记一条边被走到。
pub fn Coverage::hit(self : Coverage, edge : Int32) -> Unit {
  if edge >= 0 && edge < self.hits.length() {
    self.hits[edge] = true
  }
}

///|
/// 已被覆盖的边编号（升序）。
pub fn Coverage::edges(self : Coverage) -> Array[Int32] {
  let out : Array[Int32] = []
  let mut i = 0
  while i < self.hits.length() {
    if self.hits[i] {
      out.push(i)
    }
    i = i + 1
  }
  out
}

///|
/// 已覆盖边数。
pub fn Coverage::count(self : Coverage) -> Int32 {
  let mut n = 0
  for h in self.hits {
    if h {
      n = n + 1
    }
  }
  n
}

///|
/// 原语签名的稳定散列（FNV-1a 变体）。
///
/// 覆盖表要在多次进程之间保持可比较，所以不能用任何宿主提供的哈希
/// （`hash()` 的随机化与实现细节本身就是后端差异）。
fn name_sig(s : String) -> Int32 {
  let mut h = 5381
  for ch in s.to_array() {
    h = (h * 33) ^ ch.to_int()
  }
  h
}

///|
/// 边编号。
fn edge_id(op_name : String, branch : Int32) -> Int32 {
  let m = name_sig(op_name) % 1023
  let mm = if m < 0 { -m } else { m }
  mm * 2 + branch
}

///|
/// 取整数寄存器。
fn get_int(regs : Array[@core.Value], r : Int32) -> Int32 {
  if r >= 0 && r < regs.length() {
    match regs[r] {
      @core.VInt(v) => v
      @core.VI64(v) => v.to_int()
      @core.VF64(v) => f2i_sat(v)
      _ => 0
    }
  } else {
    0
  }
}

///|
/// 取 64 位整数寄存器。
fn get_i64(regs : Array[@core.Value], r : Int32) -> Int64 {
  if r >= 0 && r < regs.length() {
    match regs[r] {
      @core.VI64(v) => v
      @core.VInt(v) => v.to_int64()
      @core.VF64(v) => f2l_sat(v)
      _ => 0L
    }
  } else {
    0L
  }
}

///|
/// 取浮点寄存器。
fn get_f64(regs : Array[@core.Value], r : Int32) -> Double {
  if r >= 0 && r < regs.length() {
    match regs[r] {
      @core.VF64(v) => v
      @core.VInt(v) => v.to_double()
      @core.VI64(v) => v.to_double()
      _ => 0.0
    }
  } else {
    0.0
  }
}

///|
/// 取字符串寄存器。
fn get_str(regs : Array[@core.Value], r : Int32) -> String {
  if r >= 0 && r < regs.length() {
    match regs[r] {
      @core.VStr(v) => v
      _ => ""
    }
  } else {
    ""
  }
}

///|
/// 取数组寄存器。
fn get_arr(regs : Array[@core.Value], r : Int32) -> Array[Int32] {
  if r >= 0 && r < regs.length() {
    match regs[r] {
      @core.VArr(v) => v
      _ => []
    }
  } else {
    []
  }
}

///|
/// 浮点 → 32 位整数，**饱和**而不是未定义。
///
/// 规格显式定义越界行为，是为了让“溢出/NaN 转换”这一整类差异可以被观测到：
/// 如果放任宿主自行处理，某个后端可能直接 trap，整个进程消失，
/// 连转录都拿不到，就没法定位。
pub fn f2i_sat(d : Double) -> Int32 {
  if d.is_nan() {
    0
  } else if d >= 2147483647.0 {
    2147483647
  } else if d <= -2147483648.0 {
    -2147483648
  } else {
    d.to_int()
  }
}

///|
/// 浮点 → 64 位整数，饱和语义，同 `f2i_sat`。
pub fn f2l_sat(d : Double) -> Int64 {
  if d.is_nan() {
    0L
  } else if d >= 9223372036854775807.0 {
    9223372036854775807L
  } else if d <= -9223372036854775808.0 {
    0x8000000000000000L
  } else {
    d.to_int64()
  }
}

///|
/// 写寄存器。
fn put(regs : Array[@core.Value], r : Int32, v : @core.Value) -> Unit {
  if r >= 0 && r < regs.length() {
    regs[r] = v
  }
}

///|
/// 执行一段程序，返回转录与覆盖。
///
/// 转录的每一行格式固定为 `#<step> <op> r<dst> <canonical>`：
/// 步骤号、原语名、目标寄存器、规范值。任何一列不同都算差异，
/// 因此报告能直接告诉人「第几步、哪个原语、哪种值」。
pub fn run_program(p : @spec.Program, prof : @core.Profile) -> ExecResult {
  let nregs = p.reg_count()
  let regs : Array[@core.Value] = []
  let mut i = 0
  while i < nregs {
    regs.push(@core.VUnit)
    i = i + 1
  }
  let cov = Coverage::new()
  let trace : Array[String] = []
  let mut step = 0
  for op in p.ops {
    let name = @spec.op_kind_name(op.kind)
    let branch = match op.kind {
      IDiv | IMod => if get_int(regs, op.b) == 0 { 1 } else { 0 }
      LDiv | LMod => if get_i64(regs, op.b) == 0L { 1 } else { 0 }
      FDiv | FRem => if get_f64(regs, op.b) == 0.0 { 1 } else { 0 }
      FSqrt => if get_f64(regs, op.a) < 0.0 { 1 } else { 0 }
      F2I | F2L => if get_f64(regs, op.a).is_nan() { 1 } else { 0 }
      SCmp | SCat => if get_str(regs, op.a) == "" { 1 } else { 0 }
      ALen | ASum | APush =>
        if get_arr(regs, op.a).length() == 0 {
          1
        } else {
          0
        }
      _ => 0
    }
    cov.hit(edge_id(name, branch))
    let v = eval_op(op, regs)
    put(regs, op.dst, v)
    trace.push("#\{step} \{name} r\{op.dst} \{@core.render_value(v, prof)}")
    step = step + 1
  }
  { trace, coverage: cov.edges(), }
}

///|
/// 单条指令的求值。所有算术都直接落到宿主原语上，不做二次实现。
fn eval_op(op : @spec.Op, regs : Array[@core.Value]) -> @core.Value {
  match op.kind {
    ISet => @core.VInt(op.imm_i)
    IAdd => @core.VInt(get_int(regs, op.a) + get_int(regs, op.b))
    ISub => @core.VInt(get_int(regs, op.a) - get_int(regs, op.b))
    IMul => @core.VInt(get_int(regs, op.a) * get_int(regs, op.b))
    IDiv => {
      let d = get_int(regs, op.b)
      if d == 0 {
        @core.VInt(0)
      } else {
        @core.VInt(get_int(regs, op.a) / d)
      }
    }
    IMod => {
      let d = get_int(regs, op.b)
      if d == 0 {
        @core.VInt(0)
      } else {
        @core.VInt(get_int(regs, op.a) % d)
      }
    }
    IShl => @core.VInt(get_int(regs, op.a) << (get_int(regs, op.b) & 31))
    IShr => @core.VInt(get_int(regs, op.a) >> (get_int(regs, op.b) & 31))
    IAnd => @core.VInt(get_int(regs, op.a) & get_int(regs, op.b))
    IOr => @core.VInt(get_int(regs, op.a) | get_int(regs, op.b))
    IXor => @core.VInt(get_int(regs, op.a) ^ get_int(regs, op.b))
    INeg => @core.VInt(-get_int(regs, op.a))
    LSet => @core.VI64(op.imm_l)
    LAdd => @core.VI64(get_i64(regs, op.a) + get_i64(regs, op.b))
    LSub => @core.VI64(get_i64(regs, op.a) - get_i64(regs, op.b))
    LMul => @core.VI64(get_i64(regs, op.a) * get_i64(regs, op.b))
    LDiv => {
      let d = get_i64(regs, op.b)
      if d == 0L {
        @core.VI64(0L)
      } else {
        @core.VI64(get_i64(regs, op.a) / d)
      }
    }
    LMod => {
      let d = get_i64(regs, op.b)
      if d == 0L {
        @core.VI64(0L)
      } else {
        @core.VI64(get_i64(regs, op.a) % d)
      }
    }
    LShl =>
      @core.VI64(get_i64(regs, op.a) << (get_i64(regs, op.b) & 63L).to_int())
    LShr =>
      @core.VI64(get_i64(regs, op.a) >> (get_i64(regs, op.b) & 63L).to_int())
    LAnd => @core.VI64(get_i64(regs, op.a) & get_i64(regs, op.b))
    LOr => @core.VI64(get_i64(regs, op.a) | get_i64(regs, op.b))
    LXor => @core.VI64(get_i64(regs, op.a) ^ get_i64(regs, op.b))
    LNeg => @core.VI64(-get_i64(regs, op.a))
    FSet => @core.VF64(op.imm_f)
    FAdd => @core.VF64(get_f64(regs, op.a) + get_f64(regs, op.b))
    FSub => @core.VF64(get_f64(regs, op.a) - get_f64(regs, op.b))
    FMul => @core.VF64(get_f64(regs, op.a) * get_f64(regs, op.b))
    FDiv => @core.VF64(get_f64(regs, op.a) / get_f64(regs, op.b))
    FRem => @core.VF64(get_f64(regs, op.a) % get_f64(regs, op.b))
    FMin => @core.VF64(get_f64(regs, op.a).min(get_f64(regs, op.b)))
    FMax => @core.VF64(get_f64(regs, op.a).max(get_f64(regs, op.b)))
    FPow => @core.VF64(@math.pow(get_f64(regs, op.a), get_f64(regs, op.b)))
    FNeg => @core.VF64(-get_f64(regs, op.a))
    FAbs => @core.VF64(get_f64(regs, op.a).abs())
    FSqrt => @core.VF64(get_f64(regs, op.a).sqrt())
    FFloor => @core.VF64(get_f64(regs, op.a).floor())
    FCeil => @core.VF64(get_f64(regs, op.a).ceil())
    FRound => @core.VF64(get_f64(regs, op.a).round())
    FTrunc => @core.VF64(get_f64(regs, op.a).trunc())
    F2I => @core.VInt(f2i_sat(get_f64(regs, op.a)))
    I2F => @core.VF64(get_int(regs, op.a).to_double())
    L2F => @core.VF64(get_i64(regs, op.a).to_double())
    F2L => @core.VI64(f2l_sat(get_f64(regs, op.a)))
    I2L => @core.VI64(get_int(regs, op.a).to_int64())
    L2I => @core.VInt(get_i64(regs, op.a).to_int())
    SSet => @core.VStr(op.imm_s)
    SCat => @core.VStr(get_str(regs, op.a) + get_str(regs, op.b))
    SLen => @core.VInt(get_str(regs, op.a).length())
    SCmp => @core.VInt(get_str(regs, op.a).compare(get_str(regs, op.b)))
    ASet => @core.VArr(op.imm_a)
    APush => {
      let arr = get_arr(regs, op.a)
      arr.push(get_int(regs, op.b))
      @core.VArr(arr)
    }
    ALen => @core.VInt(get_arr(regs, op.a).length())
    ASum => {
      let arr = get_arr(regs, op.a)
      let mut s = 0
      for v in arr {
        s = s + v
      }
      @core.VInt(s)
    }
  }
}
