English | [简体中文](README.md)

# mpv_luameta

An [EmmyLua](https://emmylua.github.io/) metadata package (type stubs) for mpv's built-in Lua API. It gives editors and language servers completion, signature help, hover docs, go-to-definition and type checking while you write [mpv](https://mpv.io/) Lua scripts.

The `mp/*.lua` files are annotated copies of mpv's Lua modules. They are **loaded by the language server at development time only and never take part in script execution**.

## Why this exists

Modules such as `mp`, `mp.utils`, `mp.options`, `mp.msg`, `mp.input` and `mp.assdraw` are injected by the host program at runtime, so there is no `mp.lua` on disk. As a result, editors typically:

- report `require "mp"` as `unresolved-require`;
- offer no completion for `mp.get_property(...)`, `mp.command_native{...}` and friends;
- cannot validate property or option names, so typos only surface at runtime.

This project collects those modules as annotated source files, and points the language server at this directory through `workspace.packages`, which restores all of the above.

## Layout

```
mpv_luameta/
├── .version                  # upstream mpv commit the annotations are based on
├── .emmyrc.json.example      # language server configuration example
└── mp/
    ├── init.lua              # mp module
    ├── utils.lua             # mp.utils
    ├── options.lua           # mp.options
    ├── msg.lua               # mp.msg
    ├── input.lua             # mp.input
    ├── assdraw.lua           # mp.assdraw
    ├── select.lua            # mpv's built-in select script (context menu, reference only)
    ├── fzy.lua               # Lua implementation of the fzy fuzzy matching algorithm (MIT)
    └── properties.meta.lua   # properties_t union of property names (290 entries)
```

## Modules

| File | `require` name | Contents |
| --- | --- | --- |
| `mp/init.lua` | `mp` | Core module: property access (`get_property*` / `set_property*`), `command` / `commandv` / `command_native`, events and hooks (`register_event`, `add_hook`), timers, key bindings (`add_key_binding`, `set_key_bindings`), OSD overlays, script messages and more |
| `mp/utils.lua` | `mp.utils` | `readdir`, `file_info`, `split_path` / `join_path`, `parse_json` / `format_json`, `subprocess` / `subprocess_detached`, `get_env_list`, `getcwd` / `getpid`, `format_bytes_humanized`, `to_string` / `format_table`, etc. |
| `mp/options.lua` | `mp.options` | `read_options`: reads options from `script-opts` and files named after the script, converting values according to the types of the defaults |
| `mp/msg.lua` | `mp.msg` | Logging: `fatal` / `error` / `warn` / `info` / `verbose` / `debug` / `trace` |
| `mp/input.lua` | `mp.input` | Input and selection API backed by console.lua: `get`, `select`, `terminate`, `log`, `set_log` |
| `mp/assdraw.lua` | `mp.assdraw` | ASS drawing: `new_event`, `draw_start` / `draw_stop`, `pos` / `an`, `move_to` / `line_to` / `bezier_curve`, `rect_*` / `hexagon_*` / `round_rect_*`, etc. |
| `mp/fzy.lua` | `fzy` | Fuzzy matching: `has_match`, `score`, `positions`, `filter`, plus the scoring constants |
| `mp/select.lua` | — | mpv's built-in `select.lua` (context menu); useful for reading how official scripts are written, not meant to be required |
| `mp/properties.meta.lua` | — | The `properties_t` type alias covering all mpv property names, used for completion and validation in `mp.get_property`, `mp.observe_property` and similar |

Annotations cover both halves of the API: the C side (signatures collected in `---@class mp` in `mp/init.lua`, e.g. `get_property_native`, `command_native`, `raw_hook_add`) and the Lua side (event loop, timers, key bindings, OSD, `mp.utils`, ...).

## Usage

### 1. Place the directory

The repository can live anywhere. Since these files are only read by the language server, putting them in a hidden subdirectory of your script workspace is recommended, for example `scripts/.meta/mpv_luameta` as in this checkout — mpv only loads top-level `*.lua` / `*.js` files inside `scripts` and subdirectories containing a `main.lua`, so nothing under `.meta/` is ever loaded as a script.

### 2. Configure the language server

Copy `.emmyrc.json.example` to `.emmyrc.json` in your workspace root (for example, your mpv configuration directory) and replace the two `path` values with real paths:

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

Each `packages` entry solves half of the problem:

- **the repository root** makes `require "mp"` resolve to `mp/init.lua`;
- **the `mp/` subdirectory**, used as a module root, makes `require "mp.utils"`, `require "mp.input"`, `require "fzy"` and so on resolve to the matching files under `mp/`.

`runtime.version` is set to `LuaJIT` because common mpv builds use LuaJIT; change it if your build uses Lua 5.2. The `unnecessary-if` entry under `diagnostics.disable` silences a diagnostic that is noisy on this annotation-heavy code. Restart the language server after changing the configuration and let it reindex.

### 3. Command line checking (optional)

With [emmylua_check](https://github.com/EmmyLuaLs/emmylua-analyzer-rust) installed, the same configuration can be reused to check scripts directly:

```sh
emmylua_check -c .emmyrc.json path/to/my_script.lua
```

Without `-c`, it looks for `.emmyrc.json` / `.luarc.json` in the workspace automatically.

## Staying in sync with upstream

- `.version` records the upstream mpv commit these annotations were checked against, so you can tell which parts to revisit after mpv changes.
- The authoritative reference for the API is mpv's own [Lua Scripting](https://mpv.io/manual/master/#lua-scripting) manual.

## License

All content originates from the mpv project and its dependencies. Each file keeps its original license header, which takes precedence:

- Lua modules taken from mpv (`init.lua`, `utils.lua`, `options.lua`, `msg.lua`, `select.lua`, ...): LGPL-2.1-or-later;
- `fzy.lua`: MIT, copyright Seth Warn.
