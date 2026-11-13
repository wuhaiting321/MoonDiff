// 最小反例收缩。
//
// 这里是整个项目在算法上最值得说的一块：**收缩不需要重跑后端**。
//
// 因为规格程序是直线代码、每条指令的输入只由前驱决定，
// 所以“删掉一条当前分歧不依赖的指令”在语义上是**可判定的空操作**：
// 保留下来的每条指令读到的东西一个字节都没变，转录自然也一个字节都不变。
// 于是收缩退化为一次反向可达性分析（O(n·k)），
// 而不是 delta-debugging 那种 O(n log n) 次重新执行——
// 后者在四后端场景下意味着同一段程序要被编译并执行几十次。

///|
/// 收缩结果统计。
pub struct ShrinkStats {
  before : Int32
  after : Int32
  kept_cone : Int32
}

///|
/// 第 `idx` 条指令之前，最后一次写 `reg` 的指令下标；没有则 -1。
fn last_writer(ops : Array[@spec.Op], idx : Int32, reg : Int32) -> Int32 {
  let mut i = idx - 1
  while i >= 0 {
    if ops[i].dst == reg {
      return i
    }
    i = i - 1
  }
  -1
}

///|
/// 第 `idx` 条指令读取的寄存器。
fn reads_of(op : @spec.Op) -> Array[Int32] {
  let arity = @spec.op_kind_arity(op.kind)
  let out : Array[Int32] = []
  if arity > 0 {
    out.push(op.a)
  }
  if arity > 1 {
    out.push(op.b)
  }
  out
}

///|
/// 反向依赖闭包：从 `target` 出发，收集所有（直接或间接）喂养它的指令。
///
/// 返回与 `ops` 等长的标记数组。闭包之外的指令对这条分歧没有任何影响，
/// 可以安全删除。
pub fn dependency_cone(p : @spec.Program, target : Int32) -> Array[Bool] {
  let n = p.ops.length()
  let mark : Array[Bool] = Array::make(n, false)
  if target < 0 || target >= n {
    return mark
  }
  // 显式栈，避免深递归在后端栈空间上出现差异
  let stack : Array[Int32] = [target]
  while stack.length() > 0 {
    let cur = match stack.pop() {
      Some(v) => v
      None => -1
    }
    if cur >= 0 && cur < n && !mark[cur] {
      mark[cur] = true
      for reg in reads_of(p.ops[cur]) {
        let w = last_writer(p.ops, cur, reg)
        if w >= 0 && !mark[w] {
          stack.push(w)
        }
      }
    }
  }
  mark
}

///|
/// 收缩：只保留“分歧点及其依赖锥”，并丢掉分歧点之后的一切。
///
/// 反例的可读性完全取决于这一步：几百条随机指令里，
/// 真正构成 bug 的通常只有 3–5 条。
pub fn shrink(p : @spec.Program, target : Int32) -> @spec.Program {
  let mark = dependency_cone(p, target)
  let ops : Array[@spec.Op] = []
  let mut i = 0
  while i < p.ops.length() && i <= target {
    if mark[i] {
      ops.push(p.ops[i])
    }
    i = i + 1
  }
  @spec.Program::new(p.seed, p.profile, ops)
}

///|
/// 收缩前后对比。
pub fn shrink_stats(
  before : @spec.Program,
  after : @spec.Program,
) -> ShrinkStats {
  {
    before: before.ops.length(),
    after: after.ops.length(),
    kept_cone: after.ops.length(),
  }
}

///|
/// 把收缩后的程序渲染成人类可读的伪代码，用于 issue 与报告。
pub fn render_pseudo(p : @spec.Program) -> String {
  let mut out = ""
  let mut i = 0
  while i < p.ops.length() {
    out = out + "  r\{p.ops[i].dst} <- " + @spec.op_kind_name(p.ops[i].kind)
    let arity = @spec.op_kind_arity(p.ops[i].kind)
    if arity == 0 {
      if p.ops[i].kind == @spec.SSet {
        out = out + " \"" + @core.escape_str(p.ops[i].imm_s) + "\""
      } else if p.ops[i].kind == @spec.LSet {
        out = out + " " + p.ops[i].imm_l.to_string()
      } else if p.ops[i].kind == @spec.FSet {
        out = out + " 0x" + @core.hex16(p.ops[i].imm_f.reinterpret_as_int64())
      } else {
        out = out + " " + p.ops[i].imm_i.to_string()
      }
    } else if arity == 1 {
      out = out + " r" + p.ops[i].a.to_string()
    } else {
      out = out + " r" + p.ops[i].a.to_string() + ", r" + p.ops[i].b.to_string()
    }
    out = out + "\n"
    i = i + 1
  }
  out
}
