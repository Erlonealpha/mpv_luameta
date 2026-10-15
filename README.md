[English](README.en.md) | 简体中文

# mpv_luameta

为 [mpv](https://mpv.io/) 的内置 Lua API 提供 [EmmyLua](https://emmylua.github.io/) 注解（type stub）的元数据包，让编辑器与语言服务器在编写 mpv Lua 脚本时给出补全、参数提示、悬停文档、跳转定义和类型检查。

仓库中的 `mp/*.lua` 是 mpv Lua 模块源码的注解版副本；它们**只在开发期被语言服务器加载，不参与脚本运行**。

## 为什么需要

mpv 的 `mp`、`mp.utils`、`mp.options`、`mp.msg`、`mp.input`、`mp.assdraw` 等模块由宿主程序在运行时注入，磁盘上并不存在对应的 `mp.lua`。因此编辑器通常：

- 把 `require "mp"` 报为 `unresolved-require`；
- 对 `mp.get_property(...)`、`mp.command_native{...}` 等调用没有任何补全；
- 无法校验属性名、选项名，写错了只能等到运行时才发现。

本项目把这些模块整理成带注解的源码文件，再通过语言服务器的 `workspace.packages` 指向本目录，即可补齐上述能力。

## 目录结构

```
mpv_luameta/
├── .version                  # 注解所依据的上游 mpv 提交
├── .emmyrc.json.example      # 语言服务器配置示例
└── mp/
    ├── init.lua              # mp 模块
    ├── utils.lua             # mp.utils
    ├── options.lua           # mp.options
    ├── msg.lua               # mp.msg
    ├── input.lua             # mp.input
    ├── assdraw.lua           # mp.assdraw
    ├── select.lua            # mpv 内置 select 脚本（右键上下文菜单，参考用）
    ├── fzy.lua               # fzy 模糊匹配算法的 Lua 实现（MIT）
    └── properties.meta.lua   # properties_t 属性名联合类型（290 条）
```

## 包含的模块

| 文件 | 对应的 `require` | 内容 |
| --- | --- | --- |
| `mp/init.lua` | `mp` | 核心模块：属性读写（`get_property*` / `set_property*`）、`command` / `commandv` / `command_native`、事件与钩子（`register_event`、`add_hook`）、定时器、按键绑定（`add_key_binding`、`set_key_bindings`）、OSD overlay、脚本消息等 |
| `mp/utils.lua` | `mp.utils` | `readdir`、`file_info`、`split_path` / `join_path`、`parse_json` / `format_json`、`subprocess` / `subprocess_detached`、`get_env_list`、`getcwd` / `getpid`、`format_bytes_humanized`、`to_string` / `format_table` 等 |
| `mp/options.lua` | `mp.options` | `read_options`：从 `script-opts` 与脚本同名配置文件读取选项，并按默认值类型做转换 |
| `mp/msg.lua` | `mp.msg` | 日志接口：`fatal` / `error` / `warn` / `info` / `verbose` / `debug` / `trace` |
| `mp/input.lua` | `mp.input` | 通过 console.lua 实现的输入与选择接口：`get`、`select`、`terminate`、`log`、`set_log` |
| `mp/assdraw.lua` | `mp.assdraw` | ASS 绘图：`new_event`、`draw_start` / `draw_stop`、`pos` / `an`、`move_to` / `line_to` / `bezier_curve`、`rect_*` / `hexagon_*` / `round_rect_*` 等 |
| `mp/fzy.lua` | `fzy` | 模糊匹配：`has_match`、`score`、`positions`、`filter` 及相关评分常量 |
| `mp/select.lua` | — | mpv 内置的 `select.lua`（上下文菜单），用于阅读 mpv 官方脚本写法，不供 `require` |
| `mp/properties.meta.lua` | — | `properties_t` 类型别名，覆盖 mpv 全部属性名，用于 `mp.get_property`、`mp.observe_property` 等参数的补全与校验 |

注解覆盖了两部分 API：一部分是 mpv 侧的 C 实现（签名集中在 `mp/init.lua` 的 `---@class mp` 中，例如 `get_property_native`、`command_native`、`raw_hook_add`），另一部分是 Lua 侧实现（事件循环、定时器、按键绑定、OSD、`mp.utils` 等）。

## 使用方法

### 1. 放置目录

把本仓库放在任意固定位置即可。由于这些文件只能被语言服务器读取，建议放在脚本工作区的隐藏子目录中，例如本仓库当前的 `scripts/.meta/mpv_luameta`——mpv 只加载 `scripts` 目录第一层的 `*.lua` / `*.js` 以及包含 `main.lua` 的子目录，因此 `.meta/` 下的文件不会被当作脚本运行。

### 2. 配置语言服务器

把 `.emmyrc.json.example` 复制为 `.emmyrc.json`，放到工作区根目录（例如 mpv 的配置目录），并将其中两个 `path` 换成实际路径：

```json
{
  "diagnostics": {
    "disable": [
      "unnecessary-if"
    ]
  },
  "runtime": {
    "version": "LuaJIT"
  },
  "workspace": {
    "enableReindex": true,
    "encoding": "utf-8",
    "ignoreDir": [],
    "ignoreGlobs": ["**/hashlib/pure_sha.lua"],
    "library": [],
    "moduleMap": [],
    "packages": [
      {
        "path": "C:/path/to/mpv_luameta"
      },
      {
        "path": "C:/path/to/mpv_luameta/mp"
      }
    ],
    "preloadFileSize": 0,
    "reindexDuration": 10000,
    "workspaceRoots": []
  }
}
```

两条 `packages` 各自解决一半问题：

- **仓库根目录**：让 `require "mp"` 解析到 `mp/init.lua`；
- **`mp/` 子目录**：作为模块根，让 `require "mp.utils"`、`require "mp.input"`、`require "fzy"` 等解析到 `mp/` 下的对应文件。

`runtime.version` 设为 `LuaJIT` 是因为 mpv 的常见构建使用 LuaJIT；若你的构建使用 Lua 5.2，可改为对应版本。`diagnostics.disable` 里的 `unnecessary-if` 用于关闭在这批注解代码上噪声较大的诊断。改动配置后需要重启语言服务器并等待重新索引。

### 3. 命令行静态检查（可选）

装了 [emmylua_check](https://github.com/EmmyLuaLs/emmylua-analyzer-rust) 后，可以复用这份配置直接检查脚本：

```sh
emmylua_check -c .emmyrc.json path/to/my_script.lua
```

未指定 `-c` 时，它会自动在工作区中查找 `.emmyrc.json` / `.luarc.json`。

## 同步上游

- `.version` 记录这批注解校对时依据的上游 mpv 提交，便于对照 mpv 变动后需要更新哪些部分。
- mpv 官方 Lua API 文档见 [Lua Scripting](https://mpv.io/manual/master/#lua-scripting)，可作为注解的权威参照。

## 许可

仓库内容来自 mpv 项目及其依赖，各文件保留原始许可声明，具体以文件内声明为准：

- 来自 mpv 的 Lua 模块（如 `init.lua`、`utils.lua`、`options.lua`、`msg.lua`、`select.lua` 等）：LGPL-2.1-or-later；
- `fzy.lua`：MIT，版权归 Seth Warn。
