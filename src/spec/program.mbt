// 规格程序：MoonDiff 的“源码”。
//
// 设计取向：**寄存器化的直线程序**，而不是任意 AST。
// 理由有三条：
//   1. 直线程序没有控制流，每一步的输入只由前面的步骤决定，
//      所以“删掉一条不影响结果的指令”是可判定的，收缩器因此不需要重跑后端；
//   2. 每条指令对应一个明确的宿主原语（整数除法、浮点开方、字符串比较……），
//      差异一出现就能立刻归因到具体原语；
//   3. 求值与后端无关，同一个程序在四个后端上必须产生同一份转录。

///|
/// 指令种类。命名规则：`I` 前缀是 32 位整数，`L` 是 64 位整数，
/// `F` 是双精度浮点，`S` 是字符串，`A` 是整数数组，其余是转换。
pub(all) enum OpKind {
  ISet
  IAdd
  ISub
  IMul
  IDiv
  IMod
  IShl
  IShr
  IAnd
  IOr
  IXor
  INeg
  LSet
  LAdd
  LSub
  LMul
  LDiv
  LMod
  LShl
  LShr
  LAnd
  LOr
  LXor
  LNeg
  FSet
  FAdd
  FSub
  FMul
  FDiv
  FRem
  FMin
  FMax
  FPow
  FNeg
  FAbs
  FSqrt
  FFloor
  FCeil
  FRound
  FTrunc
  F2I
  I2F
  L2F
  F2L
  I2L
  L2I
  SSet
  SCat
  SLen
  SCmp
  ASet
  APush
  ALen
  ASum
} derive(Eq)

///|
/// 显式提升 Eq 的两个方法，避免隐式提升在未来版本被移除。
pub extend OpKind with Eq::{not_equal, equal}

///|
/// 一条指令。
///
/// 采用统一记录而不是 50 个构造子，是为了让“寄存器分析”“收缩”“报告”
/// 这些通用逻辑只写一遍；类型信息由 `kind` 承担。
/// 立即数分四种槽位（`imm_i` / `imm_l` / `imm_s` / `imm_f`），
/// 用不到时保持默认值，构造只走 `Op` 上的辅助函数。
pub struct Op {
  kind : OpKind
  dst : Int32
  a : Int32
  b : Int32
  imm_i : Int32
  imm_l : Int64
  imm_f : Double
  imm_s : String
  imm_a : Array[Int32]
}

///|
/// 指令名（程序文件里的短标识，也是报告里的展示名）。
pub fn op_kind_name(k : OpKind) -> String {
  match k {
    ISet => "iset"
    IAdd => "iadd"
    ISub => "isub"
    IMul => "imul"
    IDiv => "idiv"
    IMod => "imod"
    IShl => "ishl"
    IShr => "ishr"
    IAnd => "iand"
    IOr => "ior"
    IXor => "ixor"
    INeg => "ineg"
    LSet => "lset"
    LAdd => "ladd"
    LSub => "lsub"
    LMul => "lmul"
    LDiv => "ldiv"
    LMod => "lmod"
    LShl => "lshl"
    LShr => "lshr"
    LAnd => "land"
    LOr => "lor"
    LXor => "lxor"
    LNeg => "lneg"
    FSet => "fset"
    FAdd => "fadd"
    FSub => "fsub"
    FMul => "fmul"
    FDiv => "fdiv"
    FRem => "frem"
    FMin => "fmin"
    FMax => "fmax"
    FPow => "fpow"
    FNeg => "fneg"
    FAbs => "fabs"
    FSqrt => "fsqrt"
    FFloor => "ffloor"
    FCeil => "fceil"
    FRound => "fround"
    FTrunc => "ftrunc"
    F2I => "f2i"
    I2F => "i2f"
    L2F => "l2f"
    F2L => "f2l"
    I2L => "i2l"
    L2I => "l2i"
    SSet => "sset"
    SCat => "scat"
    SLen => "slen"
    SCmp => "scmp"
    ASet => "aset"
    APush => "apush"
    ALen => "alen"
    ASum => "asum"
  }
}

///|
/// 由名字还原指令种类；未知名字返回 `None`（程序文件损坏时给出可诊断的失败）。
pub fn op_kind_of_name(s : String) -> OpKind? {
  match s {
    "iset" => Some(ISet)
    "iadd" => Some(IAdd)
    "isub" => Some(ISub)
    "imul" => Some(IMul)
    "idiv" => Some(IDiv)
    "imod" => Some(IMod)
    "ishl" => Some(IShl)
    "ishr" => Some(IShr)
    "iand" => Some(IAnd)
    "ior" => Some(IOr)
    "ixor" => Some(IXor)
    "ineg" => Some(INeg)
    "lset" => Some(LSet)
    "ladd" => Some(LAdd)
    "lsub" => Some(LSub)
    "lmul" => Some(LMul)
    "ldiv" => Some(LDiv)
    "lmod" => Some(LMod)
    "lshl" => Some(LShl)
    "lshr" => Some(LShr)
    "land" => Some(LAnd)
    "lor" => Some(LOr)
    "lxor" => Some(LXor)
    "lneg" => Some(LNeg)
    "fset" => Some(FSet)
    "fadd" => Some(FAdd)
    "fsub" => Some(FSub)
    "fmul" => Some(FMul)
    "fdiv" => Some(FDiv)
    "frem" => Some(FRem)
    "fmin" => Some(FMin)
    "fmax" => Some(FMax)
    "fpow" => Some(FPow)
    "fneg" => Some(FNeg)
    "fabs" => Some(FAbs)
    "fsqrt" => Some(FSqrt)
    "ffloor" => Some(FFloor)
    "fceil" => Some(FCeil)
    "fround" => Some(FRound)
    "ftrunc" => Some(FTrunc)
    "f2i" => Some(F2I)
    "i2f" => Some(I2F)
    "l2f" => Some(L2F)
    "f2l" => Some(F2L)
    "i2l" => Some(I2L)
    "l2i" => Some(L2I)
    "sset" => Some(SSet)
    "scat" => Some(SCat)
    "slen" => Some(SLen)
    "scmp" => Some(SCmp)
    "aset" => Some(ASet)
    "apush" => Some(APush)
    "alen" => Some(ALen)
    "asum" => Some(ASum)
    _ => None
  }
}

///|
/// 指令读取的操作数个数：常量类 0，单目 1，其余 2。
pub fn op_kind_arity(k : OpKind) -> Int32 {
  match k {
    ISet | LSet | FSet | SSet | ASet => 0
    INeg
    | LNeg
    | FNeg
    | FAbs
    | FSqrt
    | FFloor
    | FCeil
    | FRound
    | FTrunc
    | F2I
    | I2F
    | L2F
    | F2L
    | I2L
    | L2I
    | SLen
    | ALen
    | ASum => 1
    _ => 2
  }
}

///|
/// 指令所属的“值域”，用于统计与报告分组。
pub fn op_kind_domain(k : OpKind) -> String {
  match k {
    ISet
    | IAdd
    | ISub
    | IMul
    | IDiv
    | IMod
    | IShl
    | IShr
    | IAnd
    | IOr
    | IXor
    | INeg => "int"
    LSet
    | LAdd
    | LSub
    | LMul
    | LDiv
    | LMod
    | LShl
    | LShr
    | LAnd
    | LOr
    | LXor
    | LNeg => "i64"
    FSet
    | FAdd
    | FSub
    | FMul
    | FDiv
    | FRem
    | FMin
    | FMax
    | FPow
    | FNeg
    | FAbs
    | FSqrt
    | FFloor
    | FCeil
    | FRound
    | FTrunc => "f64"
    F2I | I2F | L2F | F2L | I2L | L2I => "cast"
    SSet | SCat | SLen | SCmp => "string"
    ASet | APush | ALen | ASum => "array"
  }
}

///|
/// 一条整型常量指令。
pub fn Op::const_i(dst : Int32, v : Int32) -> Op {
  {
    kind: ISet,
    dst,
    a: 0,
    b: 0,
    imm_i: v,
    imm_l: 0L,
    imm_f: 0.0,
    imm_s: "",
    imm_a: [],
  }
}

///|
/// 一条 64 位常量指令。
pub fn Op::const_l(dst : Int32, v : Int64) -> Op {
  {
    kind: LSet,
    dst,
    a: 0,
    b: 0,
    imm_i: 0,
    imm_l: v,
    imm_f: 0.0,
    imm_s: "",
    imm_a: [],
  }
}

///|
/// 一条浮点常量指令（用位模式传入，避免十进制文本在不同后端被解析成不同的值）。
pub fn Op::const_f(dst : Int32, bits : Int64) -> Op {
  {
    kind: FSet,
    dst,
    a: 0,
    b: 0,
    imm_i: 0,
    imm_l: 0L,
    imm_f: bits.reinterpret_as_double(),
    imm_s: "",
    imm_a: [],
  }
}

///|
/// 一条字符串常量指令。
pub fn Op::const_s(dst : Int32, v : String) -> Op {
  {
    kind: SSet,
    dst,
    a: 0,
    b: 0,
    imm_i: 0,
    imm_l: 0L,
    imm_f: 0.0,
    imm_s: v,
    imm_a: [],
  }
}

///|
/// 一条单目指令。
pub fn Op::unary(kind : OpKind, dst : Int32, a : Int32) -> Op {
  { kind, dst, a, b: 0, imm_i: 0, imm_l: 0L, imm_f: 0.0, imm_s: "", imm_a: [], }
}

///|
/// 一条双目指令。
pub fn Op::binary(kind : OpKind, dst : Int32, a : Int32, b : Int32) -> Op {
  { kind, dst, a, b, imm_i: 0, imm_l: 0L, imm_f: 0.0, imm_s: "", imm_a: [], }
}

///|
/// 一条数组常量指令。
pub fn Op::const_a(dst : Int32, v : Array[Int32]) -> Op {
  {
    kind: ASet,
    dst,
    a: 0,
    b: 0,
    imm_i: 0,
    imm_l: 0L,
    imm_f: 0.0,
    imm_s: "",
    imm_a: v,
  }
}

///|
/// 返回一份只替换了目标寄存器的新指令（结构体字段默认为只读，因此走重建）。
pub fn Op::with_dst(self : Op, dst : Int32) -> Op {
  {
    kind: self.kind,
    dst,
    a: self.a,
    b: self.b,
    imm_i: self.imm_i,
    imm_l: self.imm_l,
    imm_f: self.imm_f,
    imm_s: self.imm_s,
    imm_a: self.imm_a,
  }
}

///|
/// 规格程序：一段直线指令序列 + 生成参数。
pub struct Program {
  seed : Int32
  profile : String
  ops : Array[Op]
}

///|
/// 构造一个程序。
pub fn Program::new(seed : Int32, profile : String, ops : Array[Op]) -> Program {
  { seed, profile, ops, }
}

///|
/// 指令条数。
pub fn Program::op_count(self : Program) -> Int32 {
  self.ops.length()
}

///|
/// 程序里出现过的最大寄存器号 + 1。
pub fn Program::reg_count(self : Program) -> Int32 {
  let mut m = 0
  for op in self.ops {
    if op.dst + 1 > m {
      m = op.dst + 1
    }
    if op.a + 1 > m && op_kind_arity(op.kind) > 0 {
      m = op.a + 1
    }
    if op.b + 1 > m && op_kind_arity(op.kind) > 1 {
      m = op.b + 1
    }
  }
  m
}
