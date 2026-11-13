// 比较档位：同一份转录在不同严格度下会得出不同结论，
// 把“档位”显式建模，避免工具给出无法解释的红灯。

///|
/// 比较档位。
pub(all) enum Profile {
  BitExact
  Strict
  Semantic
}

///|
/// 从命令行/程序文件里的短名解析档位，未知名字回落到 `Strict`。
pub fn Profile::parse(s : String) -> Profile {
  match s {
    "bit" => BitExact
    "bit-exact" => BitExact
    "bit_exact" => BitExact
    "semantic" => Semantic
    "sem" => Semantic
    _ => Strict
  }
}

///|
/// 档位的规范名字，用于报告与程序文件回写。
pub fn Profile::name(self : Profile) -> String {
  match self {
    BitExact => "bit-exact"
    Strict => "strict"
    Semantic => "semantic"
  }
}

///|
/// 档位说明，出现在 `moondiff help` 与报告的图例里。
pub fn Profile::describe(self : Profile) -> String {
  match self {
    BitExact =>
      "只比较 IEEE-754 位模式，NaN 载荷与符号零都算差异（最严格，适合定位底层缺陷）"
    Strict =>
      "位模式 + 宿主格式化结果，能抓到“数值相同但打印不同”的缺陷（默认）"
    Semantic =>
      "折叠 NaN 载荷与 ±0，过滤规范允许的差异（噪声最低，适合大规模挖洞）"
  }
}
