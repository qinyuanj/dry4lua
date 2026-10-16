# dry4lua

> 「4lua 系列」：[acceptance4lua](http://lzxsvn:3000/eggy/acceptance4lua) · [crap4lua](http://lzxsvn:3000/eggy/crap4lua) · [dry4lua](http://lzxsvn:3000/eggy/dry4lua) · [mutate4lua](http://lzxsvn:3000/eggy/mutate4lua)

Lua 源码的结构性重复检测器。

与 [dry4go](https://github.com/unclebob/dry4go) 和 [dry4clj](https://github.com/unclebob/dry4clj) 对应的 Lua 版本。

## 工作原理（How it works）

1. 使用 [luacheck](https://github.com/lunarmodules/luacheck) 解析每个 Lua 源文件
2. 从 AST 中提取函数作用域
3. 对每个函数的子树做归一化：标识符变为 `ident`，字面量变为
   `literal/<KIND>`，函数调用的被调用者变为 `callee`，运算符保留在
   标签中（如 `op/add`），关键字标签不变
4. 构建结构指纹：所有序列化后的归一化子树集合
   （S 表达式风格：`(tag child1 child2 ...)`）
5. 对所有候选对做指纹集合的 Jaccard 相似度比较
6. 报告超过阈值的配对

嵌套函数在归一化期间折叠为 `(function)` 叶节点，这样父函数的指纹
不会包含子函数的体细节；同一文件中行号范围重叠的条目（父函数和其
嵌套子函数）从成对比较中排除，对齐 dry4java 的 `overlaps` 语义。

基于大小的剪枝在 Jaccard 比较前排除了约 80% 的配对。

## 对齐上游（Upstream Alignment）

`dry4lua` 遵循"上游规格的 Lua 忠实实现"教义：dry4clj / dry4go / dry4java
三者一致的部分即为规格，逐字照抄；任何不同均为有意偏离，在此记录并
附理由。跨仓库决策以 ADR 形式存放在 luatools notes 仓库
（`projects/luatools/docs/adr/`）。

**对齐不变量（Aligned invariants）**

- 默认参数 `threshold 0.82 / min-lines 4 / min-nodes 20` 及选项集。
- 指纹 = 序列化后的归一化子树集合；相似度 = Jaccard。
- 检测单位 = 函数作用域（结构与 dry4go 的 `FuncDecl` 一致）。
- 文本输出骨架（`DUPLICATE score=%.2f` + 两行 `file:start-end`，
  无候选时输出 `No duplicate candidates found.`）以及未知格式时的
  退出码 2。
- 归一化将运算符/关键字保留在标签中，同时剥离标识符和字面量（与
  dry4go 最接近）。

**有意偏离（Deliberate deviations）**

- JSON 输出带函数 `name` 字段（dry4go 同样输出 JSON；clj/java 输出
  EDN）—— 供 CI/工具链消费。
- 文本输出额外提供 `--limit` 选项。
- 文件收集用 luafilesystem 纯 Lua 递归遍历（语义同 `find -name '*.lua' -type f`：
  只取普通 `.lua` 文件、不跟随符号链接），不依赖外部 `find` / shell，原生 Windows
  可用；路径不存在时显式报错（CLI 退 1），不会静默当作空扫描。
- 嵌套函数在父级指纹中折叠为 `(function)` 叶节点（在 upstream-aligned
  的 `overlaps` 对排除之上额外增加）。上游 dry4java 将子函数体留在
  父级指纹中，仅依赖 `overlaps`，这可能使结构不同的父级仅因为共享
  相同的内部函数而被匹配；折叠消除了这种跨文件误报（参见"工作原理"）。

## 用法（Usage）

```
bin/dry4lua [options] [file-or-directory ...]
lua5.4 bin/dry4lua [options] [file-or-directory ...]
```

`bin/dry4lua` 是一个自包含的入口点：它只将 `package.path` 设置为
仓库的 `src/`，然后调用 `dry4lua.cli`。本项目工具链统一使用
Lua 5.4。

## 在新项目中使用（Using dry4lua in a new project）

1. 安装 luacheck（运行时依赖）：

   ```
   luarocks install luacheck
   ```

2. 将本仓库引入你的项目，如作为 git submodule 或固定版本的
   toolcache 检出到 `eggy/vendor/dry4lua/`。
3. 对你的源码运行入口点：

   ```
   lua5.4 vendor/dry4lua/bin/dry4lua src
   ```

   或将入口点放到你的 `PATH` 上
   （`export PATH="$PWD/vendor/dry4lua/bin:$PATH"`），然后直接调用
   `dry4lua src`。
4. 或者，从你自己的工具链中作为库使用：

   ```lua
   package.path = "vendor/dry4lua/src/?.lua;" .. package.path
   local cli = require("dry4lua.cli")
   os.exit(cli.run(arg))
   ```

三种模式下的选项、默认值和输出格式完全一致。

## 选项（Options）

| Flag | 默认值 | 说明 |
|------|--------|------|
| `--threshold N` | 0.82 | 结构性相似度的最低阈值 (0.0-1.0) |
| `--min-lines N` | 4 | 候选函数的最少源码行数 |
| `--min-nodes N` | 20 | 候选函数的最少 AST 节点数 |
| `--limit N` | 无限制 | 文本输出最多打印的重复行数；`0` 表示无限制 |
| `--json` | | 以 JSON 格式输出 |
| `--text` | | 以文本格式输出（默认） |

## 输出（Output）

```
DUPLICATE score=0.89
  src/gameplay/dice.lua:12-25  roll_dice
  src/gameplay/movement.lua:30-44  advance_player
```

## 开发（Development）

安装运行时依赖：

```
luarocks install luacheck
```

安装测试依赖（测试套件基于 luaunit，见 ADR-0005）：

```
luarocks install luaunit
```

运行测试套件（发现 `tests/test_*.lua`，经 luaunit 执行）：

```
lua5.4 tests/run.lua
```

运行完整行为检查——单元测试、与 `tests/baseline/` 中基准的 CLI
输出差异对比，以及所有源文件的语法检查：

```
sh tests/check.sh
```

运行基准测试（在 `tests/corpus/` 和 `tests/fixtures/` 中的冻结
语料上反复执行 `find_duplicates`）：

```
lua5.4 tests/bench.lua 500
```

基准文件记录了实现代码在冻结语料上的 CLI 输出。当指纹策略从
token 滑动窗口切换到序列化归一化 AST 子树时重新生成；在该语料
中，报告的重复对和得分保持不变。
