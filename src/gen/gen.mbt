// 程序生成与变异。
//
// 生成器的目标不是“随机撞 bug”，而是**让每个原语都被喂到边界值**：
// 常量池里刻意放进 0、-0、±inf、NaN、次正规数、Int 上下界、空串、增补平面字符，
// 因为这些正是各后端实现最容易分道扬镳的地方。
//
// 寄存器带类型标记：每条指令只读写与本域匹配的寄存器。
// 这样收缩出来的最小反例读起来像正常代码，
// 而不是一堆跨域乱读、靠兜底值才勉强跑通的噪声。

///|
/// 寄存器“无类型”标记。
let tag_none : Int32 = -1

///|
/// 32 位整数寄存器。
let tag_int : Int32 = 0

///|
/// 64 位整数寄存器。
let tag_i64 : Int32 = 1

///|
/// 双精度浮点寄存器。
let tag_f64 : Int32 = 2

///|
/// 字符串寄存器。
let tag_str : Int32 = 3

///|
/// 整数数组寄存器。
let tag_arr : Int32 = 4

///|
/// 生成参数。
pub struct GenConfig {
  seed : Int32
  ops : Int32
  regs : Int32
  profile : String
}

///|
/// 构造生成参数（结构体默认为只读类型，跨包构造走这个入口）。
pub fn gen_config(
  seed : Int32,
  ops : Int32,
  regs : Int32,
  profile : String,
) -> GenConfig {
  { seed, ops, regs, profile, }
}

///|
/// 32 位整数常量池（含上下界与常见边界）。
fn int_pool() -> Array[Int32] {
  [
    0, 1, -1, 2, 7, -7, 3, 31, 32, 255, 256, 65535, 1000000, 2147483647, -2147483648,
  ]
}

///|
/// 64 位整数常量池（含位宽边界与下界）。
fn i64_pool() -> Array[Int64] {
  [
    0L, 1L, -1L, 2L, 31L, 32L, 63L, 64L, 4294967296L, 9223372036854775807L, 0x8000000000000000L,
    0x7FFFFFFFFFFFFFFFL,
  ]
}

///|
/// 浮点常量池，用**位模式**表示，避免十进制文本在解析阶段就失真。
fn f64_bits_pool() -> Array[Int64] {
  [
    0x0000000000000000L, // +0
     0x8000000000000000L, // -0
     0x3FF0000000000000L, // 1.0
     0xBFF0000000000000L, // -1.0
     0x3FE0000000000000L, // 0.5
     0x400921FB54442D18L, // pi
     0x7FEFFFFFFFFFFFFFL, // max
     0xFFEFFFFFFFFFFFFFL, // -max
     0x7FF0000000000000L, // +inf
     0xFFF0000000000000L, // -inf
     0x7FF8000000000001L, // qNaN
     0x0010000000000000L, // min normal
     0x0000000000000001L, // min subnormal
     0x4340000000000000L, // 2^53
  ]
}

///|
/// 字符串常量池（空串、单字节、多字节、增补平面、混合）。
fn str_pool() -> Array[String] {
  ["", "a", "Z", "0", "中文", "😀", "a中😀", "ab", "\u{0000}x"]
}

///|
/// 数组常量池。
fn arr_pool() -> Array[Array[Int32]] {
  [[], [0], [1, 2, 3], [-1, 0, 1], [2147483647, 1], [7, 7, 7, 7], [100, -100]]
}

///|
/// 从带指定标记的寄存器里随机取一个；没有则返回 -1。
fn pick_reg(r : Rng, tags : Array[Int32], tag : Int32) -> Int32 {
  let cands : Array[Int32] = []
  let mut i = 0
  while i < tags.length() {
    if tags[i] == tag {
      cands.push(i)
    }
    i = i + 1
  }
  match r.pick(cands) {
    Some(v) => v
    None => -1
  }
}

///|
/// 目标寄存器：任取一个，并立刻更新它的类型标记。
fn pick_dst(r : Rng, tags : Array[Int32], tag : Int32) -> Int32 {
  let dst = r.below(tags.length())
  tags[dst] = tag
  dst
}

///|
/// 随机一条整数指令。读不到同类型寄存器时退化为常量指令。
fn random_int(r : Rng, tags : Array[Int32]) -> @spec.Op {
  let a = pick_reg(r, tags, tag_int)
  let b = pick_reg(r, tags, tag_int)
  if a < 0 || b < 0 || r.below(100) < 16 {
    let dst = pick_dst(r, tags, tag_int)
    match r.pick(int_pool()) {
      Some(v) => @spec.Op::const_i(dst, v)
      None => @spec.Op::const_i(dst, 0)
    }
  } else if r.below(100) < 12 {
    let dst = pick_dst(r, tags, tag_int)
    @spec.Op::unary(@spec.INeg, dst, a)
  } else {
    let dst = pick_dst(r, tags, tag_int)
    let bins : Array[@spec.OpKind] = [
      @spec.IAdd,
      @spec.ISub,
      @spec.IMul,
      @spec.IDiv,
      @spec.IMod,
      @spec.IShl,
      @spec.IShr,
      @spec.IAnd,
      @spec.IOr,
      @spec.IXor,
    ]
    match r.pick(bins) {
      Some(k) => @spec.Op::binary(k, dst, a, b)
      None => @spec.Op::binary(@spec.IAdd, dst, a, b)
    }
  }
}

///|
/// 随机一条 64 位整数指令。
fn random_i64(r : Rng, tags : Array[Int32]) -> @spec.Op {
  let a = pick_reg(r, tags, tag_i64)
  let b = pick_reg(r, tags, tag_i64)
  if a < 0 || b < 0 || r.below(100) < 16 {
    let dst = pick_dst(r, tags, tag_i64)
    match r.pick(i64_pool()) {
      Some(v) => @spec.Op::const_l(dst, v)
      None => @spec.Op::const_l(dst, 0L)
    }
  } else if r.below(100) < 12 {
    let dst = pick_dst(r, tags, tag_i64)
    @spec.Op::unary(@spec.LNeg, dst, a)
  } else {
    let dst = pick_dst(r, tags, tag_i64)
    let bins : Array[@spec.OpKind] = [
      @spec.LAdd,
      @spec.LSub,
      @spec.LMul,
      @spec.LDiv,
      @spec.LMod,
      @spec.LShl,
      @spec.LShr,
      @spec.LAnd,
      @spec.LOr,
      @spec.LXor,
    ]
    match r.pick(bins) {
      Some(k) => @spec.Op::binary(k, dst, a, b)
      None => @spec.Op::binary(@spec.LAdd, dst, a, b)
    }
  }
}

///|
/// 随机一条浮点指令。
fn random_f64(r : Rng, tags : Array[Int32]) -> @spec.Op {
  let a = pick_reg(r, tags, tag_f64)
  let b = pick_reg(r, tags, tag_f64)
  if a < 0 || b < 0 || r.below(100) < 40 {
    let dst = pick_dst(r, tags, tag_f64)
    match r.pick(f64_bits_pool()) {
      Some(v) => @spec.Op::const_f(dst, v)
      None => @spec.Op::const_f(dst, 0L)
    }
  } else if r.below(100) < 30 {
    let dst = pick_dst(r, tags, tag_f64)
    let uns : Array[@spec.OpKind] = [
      @spec.FNeg,
      @spec.FAbs,
      @spec.FSqrt,
      @spec.FFloor,
      @spec.FCeil,
      @spec.FRound,
      @spec.FTrunc,
    ]
    match r.pick(uns) {
      Some(k) => @spec.Op::unary(k, dst, a)
      None => @spec.Op::unary(@spec.FNeg, dst, a)
    }
  } else {
    let dst = pick_dst(r, tags, tag_f64)
    let bins : Array[@spec.OpKind] = [
      @spec.FAdd,
      @spec.FSub,
      @spec.FMul,
      @spec.FDiv,
      @spec.FRem,
      @spec.FMin,
      @spec.FMax,
      @spec.FPow,
    ]
    match r.pick(bins) {
      Some(k) => @spec.Op::binary(k, dst, a, b)
      None => @spec.Op::binary(@spec.FAdd, dst, a, b)
    }
  }
}

///|
/// 随机一条转换指令。转换是跨域的，因此源寄存器按目标类型挑。
fn random_cast(r : Rng, tags : Array[Int32]) -> @spec.Op {
  let choice = r.below(6)
  if choice == 0 {
    let a = pick_reg(r, tags, tag_f64)
    let dst = pick_dst(r, tags, tag_int)
    if a < 0 {
      @spec.Op::const_i(dst, 0)
    } else {
      @spec.Op::unary(@spec.F2I, dst, a)
    }
  } else if choice == 1 {
    let a = pick_reg(r, tags, tag_int)
    let dst = pick_dst(r, tags, tag_f64)
    if a < 0 {
      @spec.Op::const_f(dst, 0L)
    } else {
      @spec.Op::unary(@spec.I2F, dst, a)
    }
  } else if choice == 2 {
    let a = pick_reg(r, tags, tag_i64)
    let dst = pick_dst(r, tags, tag_f64)
    if a < 0 {
      @spec.Op::const_f(dst, 0L)
    } else {
      @spec.Op::unary(@spec.L2F, dst, a)
    }
  } else if choice == 3 {
    let a = pick_reg(r, tags, tag_f64)
    let dst = pick_dst(r, tags, tag_i64)
    if a < 0 {
      @spec.Op::const_l(dst, 0L)
    } else {
      @spec.Op::unary(@spec.F2L, dst, a)
    }
  } else if choice == 4 {
    let a = pick_reg(r, tags, tag_int)
    let dst = pick_dst(r, tags, tag_i64)
    if a < 0 {
      @spec.Op::const_l(dst, 0L)
    } else {
      @spec.Op::unary(@spec.I2L, dst, a)
    }
  } else {
    let a = pick_reg(r, tags, tag_i64)
    let dst = pick_dst(r, tags, tag_int)
    if a < 0 {
      @spec.Op::const_i(dst, 0)
    } else {
      @spec.Op::unary(@spec.L2I, dst, a)
    }
  }
}

///|
/// 随机一条字符串指令。
fn random_str(r : Rng, tags : Array[Int32]) -> @spec.Op {
  let a = pick_reg(r, tags, tag_str)
  let choice = r.below(100)
  if a < 0 || choice < 30 {
    let dst = pick_dst(r, tags, tag_str)
    match r.pick(str_pool()) {
      Some(v) => @spec.Op::const_s(dst, v)
      None => @spec.Op::const_s(dst, "")
    }
  } else if choice < 50 {
    let dst = pick_dst(r, tags, tag_int)
    @spec.Op::unary(@spec.SLen, dst, a)
  } else if choice < 75 {
    let b = pick_reg(r, tags, tag_str)
    let dst = pick_dst(r, tags, tag_str)
    if b < 0 {
      @spec.Op::const_s(dst, "")
    } else {
      @spec.Op::binary(@spec.SCat, dst, a, b)
    }
  } else {
    let b = pick_reg(r, tags, tag_str)
    let dst = pick_dst(r, tags, tag_int)
    if b < 0 {
      @spec.Op::const_i(dst, 0)
    } else {
      @spec.Op::binary(@spec.SCmp, dst, a, b)
    }
  }
}

///|
/// 随机一条数组指令。
fn random_arr(r : Rng, tags : Array[Int32]) -> @spec.Op {
  let a = pick_reg(r, tags, tag_arr)
  let choice = r.below(100)
  if a < 0 || choice < 30 {
    let dst = pick_dst(r, tags, tag_arr)
    match r.pick(arr_pool()) {
      Some(v) => @spec.Op::const_a(dst, v)
      None => @spec.Op::const_a(dst, [])
    }
  } else if choice < 55 {
    let dst = pick_dst(r, tags, tag_int)
    @spec.Op::unary(@spec.ALen, dst, a)
  } else if choice < 75 {
    let dst = pick_dst(r, tags, tag_int)
    @spec.Op::unary(@spec.ASum, dst, a)
  } else {
    let v = pick_reg(r, tags, tag_int)
    let dst = pick_dst(r, tags, tag_arr)
    if v < 0 {
      @spec.Op::const_a(dst, [])
    } else {
      @spec.Op::binary(@spec.APush, dst, a, v)
    }
  }
}

///|
/// 按域均匀抽一条指令。
pub fn random_op(r : Rng, tags : Array[Int32]) -> @spec.Op {
  let d = r.below(6)
  if d == 0 {
    random_int(r, tags)
  } else if d == 1 {
    random_i64(r, tags)
  } else if d == 2 {
    random_f64(r, tags)
  } else if d == 3 {
    random_cast(r, tags)
  } else if d == 4 {
    random_str(r, tags)
  } else {
    random_arr(r, tags)
  }
}

///|
/// 生成一个程序：先把五个种子寄存器种成不同类型，再追加随机指令。
pub fn generate(cfg : GenConfig) -> @spec.Program {
  let r = Rng::new(cfg.seed)
  let regs = if cfg.regs < 5 { 5 } else { cfg.regs }
  let tags : Array[Int32] = Array::make(regs, tag_none)
  let ops : Array[@spec.Op] = []
  let mut i = 0
  while i < 5 {
    if i == 0 {
      match r.pick(int_pool()) {
        Some(v) => ops.push(@spec.Op::const_i(0, v))
        None => ops.push(@spec.Op::const_i(0, 0))
      }
      tags[0] = tag_int
    } else if i == 1 {
      match r.pick(i64_pool()) {
        Some(v) => ops.push(@spec.Op::const_l(1, v))
        None => ops.push(@spec.Op::const_l(1, 0L))
      }
      tags[1] = tag_i64
    } else if i == 2 {
      match r.pick(f64_bits_pool()) {
        Some(v) => ops.push(@spec.Op::const_f(2, v))
        None => ops.push(@spec.Op::const_f(2, 0L))
      }
      tags[2] = tag_f64
    } else if i == 3 {
      match r.pick(str_pool()) {
        Some(v) => ops.push(@spec.Op::const_s(3, v))
        None => ops.push(@spec.Op::const_s(3, ""))
      }
      tags[3] = tag_str
    } else {
      match r.pick(arr_pool()) {
        Some(v) => ops.push(@spec.Op::const_a(4, v))
        None => ops.push(@spec.Op::const_a(4, []))
      }
      tags[4] = tag_arr
    }
    i = i + 1
  }
  let mut n = 0
  while n < cfg.ops {
    ops.push(random_op(r, tags))
    n = n + 1
  }
  @spec.Program::new(cfg.seed, cfg.profile, ops)
}

///|
/// 变异：在已有程序上做 1–3 处小改动，保留原有结构。
///
/// 结构保留很重要——完全随机的程序很难触发“深层但精确”的边界，
/// 而在一个已经跑出异常的程序基础上做小改，命中率会高一个数量级。
pub fn mutate(p : @spec.Program, seed : Int32) -> @spec.Program {
  let r = Rng::new(seed)
  let ops : Array[@spec.Op] = []
  for op in p.ops {
    ops.push(op)
  }
  let n = 1 + r.below(3)
  let mut k = 0
  while k < n && ops.length() > 6 {
    let i = r.below(ops.length())
    let kind = r.below(4)
    if kind == 0 && ops.length() > 6 {
      let _ = ops.remove(i)
    } else if kind == 1 {
      ops.insert(i, ops[i])
    } else {
      let dst = ops[i].dst
      ops[i] = random_op(r, Array::make(8, tag_none)).with_dst(dst)
    }
    k = k + 1
  }
  @spec.Program::new(p.seed, p.profile, ops)
}

///|
/// 语料项：程序 + 它覆盖到的边。
struct CorpusItem {
  prog : @spec.Program
  edges : Array[Int32]
}

///|
/// 覆盖引导语料库。
pub struct Corpus {
  items : Array[CorpusItem]
}

///|
/// 空语料库。
pub fn Corpus::new() -> Corpus {
  { items: [], }
}

///|
/// 新边数量：`cur` 里不在 `seen` 中的边。
fn novel_edges(seen : Array[Int32], cur : Array[Int32]) -> Int32 {
  let mut n = 0
  for e in cur {
    let mut found = false
    for s in seen {
      if s == e {
        found = true
      }
    }
    if !found {
      n = n + 1
    }
  }
  n
}

///|
/// 若程序带来了新边则收入语料库，返回是否新增。
///
/// 这是覆盖引导的核心：只有“让我看到新行为”的输入才值得留下，
/// 否则语料会在几百次迭代后膨胀成几十万条重复样本。
pub fn Corpus::add(
  self : Corpus,
  prog : @spec.Program,
  edges : Array[Int32],
) -> Bool {
  let seen : Array[Int32] = []
  for item in self.items {
    for e in item.edges {
      seen.push(e)
    }
  }
  if novel_edges(seen, edges) > 0 || self.items.length() == 0 {
    self.items.push({ prog, edges, })
    true
  } else {
    false
  }
}

///|
/// 语料项数。
pub fn Corpus::size(self : Corpus) -> Int32 {
  self.items.length()
}

///|
/// 取第 i 个程序。
pub fn Corpus::at(self : Corpus, i : Int32) -> @spec.Program? {
  if i >= 0 && i < self.items.length() {
    Some(self.items[i].prog)
  } else {
    None
  }
}
