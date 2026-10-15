---@meta

---@alias observe_property_type ("none" | "native" | "bool" | "string" | "number")?

---@class mp
---@field UNKNOWN_TYPE table
---@field ARRAY table
---@field MAP table
---@field script_name string
---@field find_config_file              fun(conf:string):string
---@field get_script_directory          fun():string
---@field get_property                  fun(n:properties_t|string, default:any):any
---@field get_property_number           fun(n:properties_t|string, default:number?):number
---@field get_property_bool             fun(n:properties_t|string, default:boolean?):boolean
---@field get_property_native           fun(n:properties_t|string, default:any?):any
---@field set_property                  fun(n:properties_t|string, v:any):any
---@field set_property_bool             fun(n:properties_t|string, v:boolean):any
---@field set_property_number           fun(n:properties_t|string, v:number):any
---@field set_property_native           fun(n:properties_t|string, v:any|table<string, any>):any
---@field del_property                  fun(n:properties_t|string)
---@field enable_messages               fun(n:string)
---@field input_set_section_mouse_area  fun(section:string, x0:number, y0:number, x1:number, y1:number):any
---@field raw_observe_property          fun(id:integer, n:string, t:observe_property_type):any
---@field raw_unobserve_property        fun(n:string):any
---@field raw_wait_event                fun(timeout:number):table
---@field raw_hook_continue             fun(id:integer):any
---@field raw_hook_add                  fun(id:integer, n:string, priority:integer)
---@field raw_command_native_async      fun(id:integer, node:table)
---@field raw_abort_async_command       fun(id:integer)
---@field wait_event                    fun(n:number):any
---@field request_event                 fun(n:string, enabled:boolean):any
---@field log                           fun(level:string, ...:any):any
---@field get_time                      fun():number
---@field command                       fun(i:string):boolean?,string?
---@field commandv                      fun(i:string,...):boolean?,string?
---@field command_native                fun(cmd:table):any?,string?
local mp = {}


-- Compatibility shim for lua 5.2/5.3
-- luacheck: globals unpack
local unpack = unpack or table.unpack -- luacheck: globals table.unpack

-- these are used internally by lua.c
mp.UNKNOWN_TYPE.info = "this value is inserted if the C type is not supported"
mp.UNKNOWN_TYPE.type = "UNKNOWN_TYPE"

mp.ARRAY.info = "native array"
mp.ARRAY.type = "ARRAY"

mp.MAP.info = "native map"
mp.MAP.type = "MAP"

---@return string
function mp.get_script_name()
    return mp.script_name
end

---@param key string
---@param def any?
function mp.get_opt(key, def)
    local opts = mp.get_property_native("options/script-opts")
    local val = opts[key]
    if val == nil then
        val = def
    end
    return val
end

---@alias define_section_flags "default" | "force"

---@param section string
---@param contents string
---@param flags define_section_flags?
function mp.input_define_section(section, contents, flags)
    if flags == nil or flags == "" then
        flags = "default"
    end
    mp.commandv("define-section", section, contents, flags)
end

---@alias enable_section_flags 
--- | ""
--- | "exclusive"
--- | "allow-hide-cursor"
--- | "allow-vo-dragging"
--- | "exclusive+allow-hide-cursor"
--- | "allow-hide-cursor+exclusive"
--- | "exclusive+allow-vo-dragging"
--- | "allow-vo-dragging+exclusive"
--- | "allow-hide-cursor+allow-vo-dragging"
--- | "allow-vo-dragging+allow-hide-cursor"
--- | "exclusive+allow-hide-cursor+allow-vo-dragging"
--- | "exclusive+allow-vo-dragging+allow-hide-cursor"
--- | "allow-hide-cursor+allow-vo-dragging+exclusive"
--- | "allow-hide-cursor+exclusive+allow-vo-dragging"
--- | "allow-vo-dragging+allow-hide-cursor+exclusive"
--- | "allow-vo-dragging+exclusive+allow-hide-cursor"

---@param section string
---@param flags enable_section_flags?
function mp.input_enable_section(section, flags)
    if flags == nil then
        flags = ""
    end
    mp.commandv("enable-section", section, flags)
end

---@param section string
function mp.input_disable_section(section)
    mp.commandv("disable-section", section)
end

---@return int, int
function mp.get_mouse_pos()
    local m = mp.get_property_native("mouse-pos")
    return m.x, m.y
end

-- For dispatching script-binding. This is sent as:
--      script-message-to $script_name $binding_name $keystate
-- The array is indexed by $binding_name, and has functions like this as value:
--      fn($binding_name, $keystate)
local dispatch_key_bindings = {}

local message_id = 0
local function reserve_binding()
    message_id = message_id + 1
    return "__keybinding" .. tostring(message_id)
end

local function dispatch_key_binding(name, state, key_name, key_text, scale, arg)
    local fn = dispatch_key_bindings[name]
    if fn then
        fn(name, state, key_name, key_text, scale, arg)
    end
end

-- "Old", deprecated API

-- each script has its own section, so that they don't conflict
local default_section = "input_dispatch_" .. mp.script_name

-- Set the list of key bindings. These will override the user's bindings, so
-- you should use this sparingly.
-- A call to this function will remove all bindings previously set with this
-- function. For example, set_key_bindings({}) would remove all script defined
-- key bindings.
-- Note: the bindings are not active by default. Use enable_key_bindings().
--
-- list is an array of key bindings, where each entry is an array as follow:
--      {key, callback_press, callback_down, callback_up}
-- key is the key string as used in input.conf, like "ctrl+a"
--
-- callback can be a string too, in which case the following will be added like
-- an input.conf line: key .. " " .. callback
-- (And callback_down is ignored.)
---@param list [string, fun()?, fun()?, fun()?][] <key, cb, cb_down, cb_up>[]
---@param section string?
---@param flags define_section_flags?
function mp.set_key_bindings(list, section, flags)
    local cfg = ""
    for i = 1, #list do
        local entry = list[i]
        local key = entry[1]
        local cb = entry[2]
        local cb_down = entry[3]
        local cb_up = entry[4]
        if type(cb) ~= "string" then
            local mangle = reserve_binding()
            dispatch_key_bindings[mangle] = function(_, state)
                local event = state:sub(1, 1)
                local is_mouse = state:sub(2, 2) == "m"
                local def = (is_mouse and "u") or "d"
                if event == "r" then
                    return
                end
                if event == "p" and cb then
                    cb()
                elseif event == "d" and cb_down then
                    cb_down()
                elseif event == "u" and cb_up then
                    cb_up()
                elseif event == def and cb then
                    cb()
                end
            end
            cfg = cfg .. key .. " script-binding " ..
                  mp.script_name .. "/" .. mangle .. "\n"
        else
            cfg = cfg .. key .. " " .. cb .. "\n"
        end
    end
    mp.input_define_section(section or default_section, cfg, flags)
end

---@param section string?
---@param flags enable_section_flags?
function mp.enable_key_bindings(section, flags)
    mp.input_enable_section(section or default_section, flags)
end

---@param section string?
function mp.disable_key_bindings(section)
    mp.input_disable_section(section or default_section)
end

---@param x0 int
---@param y0 int
---@param x1 int
---@param y1 int
---@param section string?
function mp.set_mouse_area(x0, y0, x1, y1, section)
    mp.input_set_section_mouse_area(section or default_section, x0, y0, x1, y1)
end

-- "Newer" and more convenient API

local key_bindings = {}
local key_binding_counter = 0
local key_bindings_dirty = false

function mp.flush_keybindings()
    if not key_bindings_dirty then
        return
    end
    key_bindings_dirty = false

    for i = 1, 2 do
        local section, flags
        local def = i == 1
        if def then
            section = "input_" .. mp.script_name
            flags = "default"
        else
            section = "input_forced_" .. mp.script_name
            flags = "force"
        end
        local bindings = {}
        for _, v in pairs(key_bindings) do
            if v.bind and v.forced ~= def then
                bindings[#bindings + 1] = v
            end
        end
        table.sort(bindings, function(a, b)
            return a.priority < b.priority
        end)
        local cfg = ""
        for _, v in ipairs(bindings) do
            cfg = cfg .. v.bind .. "\n"
        end
        mp.input_define_section(section, cfg, flags)
        mp.input_enable_section(section, "allow-hide-cursor+allow-vo-dragging")
    end
end

---@alias key_binding_attrs {
---     forced?: boolean,
---     bind?: string,
---     name?: string,
---     priority?: integer,
--- }

---@alias binding_callback_event {
---     event: string,
---     is_mouse: boolean,
---     canceled: boolean?,
---     key_name: string?,
---     key_text: string?,
---     scale: number?,
---     arg: table?,
--- }

---@alias binding_callback fun(ev:binding_callback_event?):any

---@param attrs key_binding_attrs
---@param key string?
---@param name string?
---@param fn binding_callback?
---@param rp (string|table)?
---@overload fun(
---     attrs: key_binding_attrs,
---     key: string?,
---     fn: binding_callback?,
---     rp: (string|table)?
--- )
local function add_binding(attrs, key, name, fn, rp)
    if type(name) ~= "string" and name ~= nil then
        ---@diagnostic disable-next-line: assign-type-mismatch
        rp = fn
        ---@diagnostic disable-next-line: assign-type-mismatch
        fn = name
        name = nil
    end

    ---@cast name string?
    ---@cast fn binding_callback?
    ---@cast rp (string|table)?

    rp = rp or ""
    if name == nil then
        name = reserve_binding()
    end
    local repeatable = rp == "repeatable" or rp["repeatable"]
    local scalable = rp == "scalable" or rp["scalable"]
    if rp["forced"] then
        attrs.forced = true
    end
    local key_cb, msg_cb
    if not fn then
        fn = function() end
    end
    if rp["complex"] then
        local key_states = {
            ["u"] = "up",
            ["d"] = "down",
            ["r"] = "repeat",
            ["p"] = "press",
        }
        key_cb = function(_, state, key_name, key_text, scale, arg)
            if key_text == "" then
                key_text = nil
            end
            fn({
                event = key_states[state:sub(1, 1)] or "unknown",
                is_mouse = state:sub(2, 2) == "m",
                canceled = state:sub(3, 3) == "c",
                key_name = key_name,
                key_text = key_text,
                scale = tonumber(scale),
                arg = arg,
            })
        end
        msg_cb = function()
            fn({event = "press", is_mouse = false})
        end
    else
        key_cb = function(_, state)
            -- Emulate the same semantics as input.c uses for most bindings:
            -- For keyboard, "down" runs the command, "up" does nothing;
            -- for mouse, "down" does nothing, "up" runs the command.
            -- Also, key repeat triggers the binding again.
            local event = state:sub(1, 1)
            local is_mouse = state:sub(2, 2) == "m"
            local canceled = state:sub(3, 3) == "c"
            if canceled or event == "r" and not repeatable then
                return
            end
            if is_mouse and (event == "u" or event == "p") then
                fn()
            elseif not is_mouse and (event == "d" or event == "r" or event == "p") then
                fn()
            end
        end
        msg_cb = fn
    end
    local prefix = scalable and "" or " nonscalable"
    if key and #key > 0 then
        attrs.bind = key .. prefix .. " script-binding " .. mp.script_name .. "/" .. name
    end
    attrs.name = name
    -- new bindings override old ones (but do not overwrite them)
    key_binding_counter = key_binding_counter + 1
    attrs.priority = key_binding_counter
    key_bindings[name] = attrs
    key_bindings_dirty = true
    dispatch_key_bindings[name] = key_cb
    mp.register_script_message(name, msg_cb)
end

---@param key string?
---@param name string?
---@param fn binding_callback?
---@param rp (string|table)?
---@overload fun(
---     key: string?,
---     fn: binding_callback?,
---     rp: (string|table)?
--- )
function mp.add_key_binding(key, name, fn, rp)
    add_binding({forced=false}, key, name, fn, rp)
end

---@param key string?
---@param name string?
---@param fn binding_callback?
---@param rp (string|table)?
---@overload fun(
---     key: string?,
---     fn: binding_callback?,
---     rp: (string|table)?
--- )
function mp.add_forced_key_binding(key, name, fn, rp)
    add_binding({forced=true}, key, name, fn, rp)
end

---@param name string
function mp.remove_key_binding(name)
    key_bindings[name] = nil
    dispatch_key_bindings[name] = nil
    key_bindings_dirty = true
    mp.unregister_script_message(name)
end

---@class mp_timer : _mp_timer_mt
---@field timeout number
---@field cb fun()
---@field oneshot boolean

---@type table<mp_timer, mp_timer>
local timers = {}

---@class _mp_timer_mt
---@field next_deadline number
local timer_mt = {}
timer_mt.__index = timer_mt

---@param seconds number
---@param cb fun()
---@param disabled boolean?
---@return mp_timer
function mp.add_timeout(seconds, cb, disabled)
    local t = mp.add_periodic_timer(seconds, cb, disabled)
    t.oneshot = true
    return t
end

---@param seconds number
---@param cb fun()
---@param disabled boolean?
---@return mp_timer
function mp.add_periodic_timer(seconds, cb, disabled)
    local t = {
        timeout = seconds,
        cb = cb,
        oneshot = false,
    }
    setmetatable(t, timer_mt)
    if not disabled then
        t:resume()
    end
    ---@cast t mp_timer
    return t
end

function timer_mt.stop(t)
    if timers[t] then
        timers[t] = nil
        t.next_deadline = t.next_deadline - mp.get_time()
    end
end

function timer_mt.kill(t)
    timers[t] = nil
    t.next_deadline = nil
end
mp.cancel_timer = timer_mt.kill

function timer_mt.resume(t)
    if not timers[t] then
        local timeout = t.next_deadline
        if timeout == nil then
            timeout = t.timeout
        end
        t.next_deadline = mp.get_time() + timeout
        timers[t] = t
    end
end

---@return boolean
function timer_mt.is_enabled(t)
    return timers[t] ~= nil
end

-- Return the timer that expires next.
---@return mp_timer?
local function get_next_timer()
    local best = nil
    for t, _ in pairs(timers) do
        if best == nil or t.next_deadline < best.next_deadline then
            best = t
        end
    end
    return best
end

---@return number?
function mp.get_next_timeout()
    local timer = get_next_timer()
    if not timer then
        return
    end
    local now = mp.get_time()
    return timer.next_deadline - now
end

-- Run timers that have met their deadline at the time of invocation.
-- Return: time>0 in seconds till the next due timer, 0 if there are due timers
--         (aborted to avoid infinite loop), or nil if no timers
local function process_timers()
    local t0 = nil
    while true do
        local timer = get_next_timer()
        if not timer then
            return
        end
        local now = mp.get_time()
        local wait = timer.next_deadline - now
        if wait > 0 then
            return wait
        else
            if not t0 then
                t0 = now  -- first due callback: always executes, remember t0
            elseif timer.next_deadline > t0 then
                -- don't block forever with slow callbacks and endless timers.
                -- we'll continue right after checking mpv events.
                return 0
            end

            if timer.oneshot then
                timer:kill()
            else
                timer.next_deadline = now + timer.timeout
            end
            timer.cb()
        end
    end
end

local messages = {}

---@param name string
---@param fn fun(...)
function mp.register_script_message(name, fn)
    messages[name] = fn
end

---@param name string
function mp.unregister_script_message(name)
    messages[name] = nil
end

local function message_dispatch(ev)
    if #ev.args > 0 then
        local handler = messages[ev.args[1]]
        if handler then
            handler(unpack(ev.args, 2))
        end
    end
end

local property_id = 0
local properties = {}

---@param name properties_t|string
---@param t observe_property_type
---@param cb fun(name:properties_t|string, data?:any)
---@overload fun(name:properties_t|string, t:"native", cb:fun(name:string, data:table|string|number|boolean))
---@overload fun(name:properties_t|string, t:"number", cb:fun(name:string, data:number|int))
---@overload fun(name:properties_t|string, t:"string", cb:fun(name:string, data:string))
---@overload fun(name:properties_t|string, t:"bool",   cb:fun(name:string, data:boolean))
function mp.observe_property(name, t, cb)
    local id = property_id + 1
    property_id = id
    properties[id] = cb
    mp.raw_observe_property(id, name, t)
end

---@param cb fun(name:string)
function mp.unobserve_property(cb)
    for prop_id, prop_cb in pairs(properties) do
        if cb == prop_cb then
            properties[prop_id] = nil
            mp.raw_unobserve_property(prop_id)
        end
    end
end

local function property_change(ev)
    local prop = properties[ev.id]
    if prop then
        prop(ev.name, ev.data)
    end
end

-- used by default event loop (mp_event_loop()) to decide when to quit
mp.keep_running = true

function _G.exit()
    mp.keep_running = false
end

local event_handlers = {}


---@alias mp_ev_start_file         {id:int, event:string, error:string?,
---                                 playlist_entry_id: int}
---@alias mp_ev_end_file           {id:int, event:string, error:string?,
---                                 reason: "eof"|"stop"|"quit"|"error"|"redirect"|"unknown",
---                                 playlist_entry_id: int,
---                                 playlist_insert_id: int?,
---                                 playlist_insert_num_entries: table[]?}
---@alias mp_ev_file_loaded        {id:int, event:string, error:string?}
---@alias mp_ev_seek               {id:int, event:string, error:string?}
---@alias mp_ev_playback_restart   {id:int, event:string, error:string?}
---@alias mp_ev_shutdown           {id:int, event:string, error:string?}
---@alias mp_ev_log_message        {id:int, event:string, error:string?,
---                                 prefix: string, level: string, text: string}
---@alias mp_ev_hook               {id:int, event:string, error:string?, 
---                                 hook_id:int}
---@alias mp_ev_command_reply      {id:int, event:string, error:string?, 
---                                 result:string}
---@alias mp_ev_client_message     {id:int, event:string, error:string?,
---                                 args: any[]}
---@alias mp_ev_video_reconfig     {id:int, event:string, error:string?}
---@alias mp_ev_audio_reconfig     {id:int, event:string, error:string?}
---@alias mp_ev_property_change    {id:int, event:string, error:string?,
---                                 name:string, data:any}

---@param name string
---@param cb fun(ev:table)
---@overload fun(name:"start-file",          cb:fun(ev:mp_ev_start_file))
---@overload fun(name:"end-file",            cb:fun(ev:mp_ev_end_file))
---@overload fun(name:"file-loaded",         cb:fun(ev:mp_ev_file_loaded))
---@overload fun(name:"seek",                cb:fun(ev:mp_ev_seek))
---@overload fun(name:"playback-restart",    cb:fun(ev:mp_ev_playback_restart))
---@overload fun(name:"shutdown",            cb:fun(ev:mp_ev_shutdown))
---@overload fun(name:"log-message",         cb:fun(ev:mp_ev_log_message))
---@overload fun(name:"hook",                cb:fun(ev:mp_ev_hook))
---@overload fun(name:"command-reply",       cb:fun(ev:mp_ev_command_reply))
---@overload fun(name:"client-message",      cb:fun(ev:mp_ev_client_message))
---@overload fun(name:"video-reconfig",      cb:fun(ev:mp_ev_video_reconfig))
---@overload fun(name:"audio-reconfig",      cb:fun(ev:mp_ev_audio_reconfig))
---@overload fun(name:"property-change",     cb:fun(ev:mp_ev_property_change))
function mp.register_event(name, cb)
    local list = event_handlers[name]
    if not list then
        list = {}
        event_handlers[name] = list
    end
    list[#list + 1] = cb
    return mp.request_event(name, true)
end

---@param cb fun(ev:table)
function mp.unregister_event(cb)
    for name, sub in pairs(event_handlers) do
        local found = false
        for _, e in ipairs(sub) do
            if e == cb then
                found = true
                break
            end
        end
        if found then
            -- create a new array, just in case this function was called
            -- from an event handler
            local new = {}
            for i = 1, #sub do
                if sub[i] ~= cb then
                    new[#new + 1] = sub[i]
                end
            end
            event_handlers[name] = new
            if #new == 0 then
                mp.request_event(name, false)
            end
        end
    end
end

-- default handlers
mp.register_event("shutdown", exit)
mp.register_event("client-message", message_dispatch)
mp.register_event("property-change", property_change)

-- called before the event loop goes back to sleep
local idle_handlers = {}

---@param cb fun()
function mp.register_idle(cb)
    idle_handlers[#idle_handlers + 1] = cb
end

---@param cb fun()
function mp.unregister_idle(cb)
    local new = {}
    for _, handler in ipairs(idle_handlers) do
        if handler ~= cb then
            new[#new + 1] = handler
        end
    end
    idle_handlers = new
end

-- sent by "script-binding"
mp.register_script_message("key-binding", dispatch_key_binding)

mp.msg = {
    log = mp.log,
    fatal = function(...) return mp.log("fatal", ...) end,
    error = function(...) return mp.log("error", ...) end,
    warn = function(...) return mp.log("warn", ...) end,
    info = function(...) return mp.log("info", ...) end,
    verbose = function(...) return mp.log("v", ...) end,
    debug = function(...) return mp.log("debug", ...) end,
    trace = function(...) return mp.log("trace", ...) end,
}

_G.print = mp.msg.info

package.loaded["mp"] = mp
package.loaded["mp.msg"] = mp.msg

_G.mp_event_loop = function()
    mp.dispatch_events(true)
end

local function call_event_handlers(e)
    local handlers = event_handlers[e.event]
    if handlers then
        for _, handler in ipairs(handlers) do
            handler(e)
        end
    end
end

---@param allow_wait boolean
function mp.dispatch_events(allow_wait)
    local more_events = true
    while mp.keep_running do
        local wait = 0
        if not more_events then
            wait = process_timers() or 1e20 -- infinity for all practical purposes
            if wait ~= 0 then
                local idle_called = nil
                for _, handler in ipairs(idle_handlers) do
                    idle_called = true
                    handler()
                end
                if idle_called then
                    -- handlers don't complete in 0 time, and may modify timers
                    wait = mp.get_next_timeout() or 1e20
                    if wait < 0 then
                        wait = 0
                    end
                end
            end
            if allow_wait ~= true then
                return
            end
        end
        local e = mp.wait_event(wait)
        more_events = false
        if e.event ~= "none" then
            call_event_handlers(e)
            more_events = true
        end
    end
end

mp.register_idle(mp.flush_keybindings)

-- additional helpers

---@param text string
---@param duration number?
function mp.osd_message(text, duration)
    ---@type string
    local dur
    if not duration then
        dur = "-1"
    else
        dur = tostring(math.floor(duration * 1000))
    end
    mp.commandv("show-text", text, dur)
end

local hook_table = {}

---@class _mp_hook_event_mt
local hook_mt = {}
hook_mt.__index = hook_mt

function hook_mt.cont(t)
    if t._id == nil then
        mp.msg.error("hook already continued")
    else
        mp.raw_hook_continue(t._id)
        t._id = nil
    end
end

function hook_mt.defer(t)
    t._defer = true
end

mp.register_event("hook", function(ev)
    local fn = hook_table[tonumber(ev.id)]
    local hookobj = {
        _id = ev.hook_id,
        _defer = false,
    }
    setmetatable(hookobj, hook_mt)
    if fn then
        fn(hookobj)
    end
    if not hookobj._defer and hookobj._id ~= nil then
        hookobj:cont()
    end
end)

---@class mp_hook_event : _mp_hook_event_mt

--[[
    on_load:
        在打开文件时调用，在实际执行任何操作之前调用。
        例如，您可以读取和写入 stream-open-filename 用于将 URL 重定向到其他位置的属性
        （考虑支持 （很少向用户提供直接媒体 URL 的流媒体网站），或者 您可以通过设置属性来为每个文件设置选项。
        file-local-options/<option name> 玩家将等待所有钩子都运行完毕。
        排序在 start-file 之后， playback-restart 之前。

    on_load_fail:
        文件打开后调用，但失败。这可能是 用于在原生解复用器无法识别时提供备用方案 该文件，而不是始终在原生解复用器之前运行，
        例如 on_load 仅当 stream-open-filename 时才会重试解复用。 已更改。如果再次失败，则不会再次调用此钩子，并且 加载肯定失败了。
        排序在 on_load 之后， playback-restart 和 end-file 之前。

    on_preloaded:
        此方法在文件打开后、选择音轨和创建解码器之前调用。如果 API 用户希望根据可用音轨集手动选择音轨，这将非常有用。
        此外，它还允许 API 以特定方式初始化 --lavfi-complex ，而无需事先“探测”可用流。
        请注意，这尚未应用默认曲目选择。具体哪些操作可以执行、哪些操作不能执行，以及哪些信息可用、哪些信息尚不可用，所有这些都可能发生变化。
        按 on_load_fail 等之后、 playback-restart 之前排序。

    on_unload:
        在关闭文件之前，以及在实际取消初始化所有内容之前运行此命令。在此状态下无法恢复播放。
        排序在 end-file 之前。错误情况下也会发生（然后是之后）。 on_load_fail ).

    on_before_start_file:
        在发送 start-file 事件之前运行。（如果任何客户端更改了当前播放列表条目，或向播放器发送了退出命令，
        则在钩子返回后，相应的事件实际上不会发生。）这有助于在加载新文件之前清除属性更改。
    on_after_end_file:
        在 end-file 事件发生后运行。可用于在文件执行完毕后清除属性更改。
]]
---@alias mp_hooks "on_load"|"on_load_fail"|"on_preloaded"|"on_unload"|"on_before_start_file"|"on_after_end_file"

---@param name mp_hooks
---@param pri int
---@param cb fun(ev:mp_hook_event):never
function mp.add_hook(name, pri, cb)
    local id = #hook_table + 1
    hook_table[id] = cb
    -- The C API suggests using 0 for a neutral priority, but lua.rst suggests
    -- 50 (?), so whatever.
    mp.raw_hook_add(id, name, pri - 50)
end

local async_call_table = {}
local async_next_id = 1

---@param node table
---@param cb fun(success: boolean, result: any?, error: string?)
---@overload fun(
---    node: table,
---    cb: fun(success: boolean, result: any?, error: string?)
--- ):nil,string
---@return table, string?
function mp.command_native_async(node, cb)
    local id = async_next_id
    async_next_id = async_next_id + 1
    cb = cb or function() end
    local res, err = mp.raw_command_native_async(id, node)
    if not res then
        mp.add_timeout(0, function() cb(false, nil, err) end)
        return res, err
    end
    local t = {cb = cb, id = id}
    async_call_table[id] = t
    return t
end

mp.register_event("command-reply", function(ev)
    local id = tonumber(ev.id)
    local t = async_call_table[id]
    local cb = t.cb
    t.id = nil
    async_call_table[id] = nil
    if ev.error then
        cb(false, nil, ev.error)
    else
        cb(true, ev.result, nil)
    end
end)

---@param t table
function mp.abort_async_command(t)
    if t.id ~= nil then
        mp.raw_abort_async_command(t.id)
    end
end


---@class _mp_overlay_mt
---@field format "ass-events" | string
---@field id int
---@field data string
---@field res_x int
---@field res_y int
---@field z number DEF: 0
---@field compute_bounds boolean DEF: FALSE
---@field hidden boolean DEF: FALSE
local overlay_mt = {}
overlay_mt.__index = overlay_mt
local overlay_new_id = 0

---@class mp_osd_overlay : _mp_overlay_mt

---@param format "ass-events" | string
---@return mp_osd_overlay
function mp.create_osd_overlay(format)
    overlay_new_id = overlay_new_id + 1
    local overlay = {
        format = format,
        id = overlay_new_id,
        data = "",
        res_x = 0,
        res_y = 720,
    }
    setmetatable(overlay, overlay_mt)
    return overlay
end

---@param ov mp_osd_overlay
function overlay_mt.update(ov)
    local cmd = {}
    for k, v in pairs(ov) do
        cmd[k] = v
    end
    cmd._name = "osd-overlay"
    cmd.res_x = math.floor(cmd.res_x)
    cmd.res_y = math.floor(cmd.res_y)
    return mp.command_native(cmd)
end

---@param ov mp_osd_overlay
function overlay_mt.remove(ov)
    mp.command_native {
        _name = "osd-overlay",
        id = ov.id,
        format = "none",
        data = "",
    }
end

-- legacy API
---@param res_x int
---@param res_y int
---@param data string
function mp.set_osd_ass(res_x, res_y, data)
    if not mp._legacy_overlay then
        mp._legacy_overlay = mp.create_osd_overlay("ass-events")
    end
    if mp._legacy_overlay.res_x ~= res_x or
       mp._legacy_overlay.res_y ~= res_y or
       mp._legacy_overlay.data ~= data
    then
        mp._legacy_overlay.res_x = res_x
        mp._legacy_overlay.res_y = res_y
        mp._legacy_overlay.data = data
        mp._legacy_overlay:update()
    end
end

---@return int, int, number
function mp.get_osd_size()
    local prop = mp.get_property_native("osd-dimensions")
    return prop.w, prop.h, prop.aspect
end

---@return int, int ,int, int
function mp.get_osd_margins()
    local prop = mp.get_property_native("osd-dimensions")
    return prop.ml, prop.mt, prop.mr, prop.mb
end

---@type mp_utils
local mp_utils = package.loaded["mp.utils"]


---@param t table
---@param set table?
function mp_utils.format_table(t, set)
    if not set then
        set = { [t] = true }
    end
    local res = "{"
    -- pretty expensive but simple way to distinguish array and map parts of t
    local keys = {}
    local vals = {}
    local arr = 0
    for i = 1, #t do
        if t[i] == nil then
            break
        end
        keys[i] = i
        vals[i] = t[i]
        arr = i
    end
    for k, v in pairs(t) do
        if not (type(k) == "number" and k >= 1 and k <= arr and keys[k]) then
            keys[#keys + 1] = k
            vals[#keys] = v
        end
    end
    for i = 1, #keys do
        if #res > 1 then
            res = res .. ", "
        end
        if i > arr then
            res = res .. mp_utils.to_string(keys[i], set) .. " = "
        end
        res = res .. mp_utils.to_string(vals[i], set)
    end
    res = res .. "}"
    return res
end

---@param v any
---@param set table?
function mp_utils.to_string(v, set)
    if type(v) == "string" then
        return "\"" .. v .. "\""
    elseif type(v) == "table" then
        if set then
            if set[v] then
                return "[cycle]"
            end
            set[v] = true
        end
        return mp_utils.format_table(v, set)
    else
        return tostring(v)
    end
end

---@return string
function mp_utils.getcwd()
    return mp.get_property("working-directory")
end

---@return int
function mp_utils.getpid()
    return mp.get_property_number("pid")
end

---@param b int
function mp_utils.format_bytes_humanized(b)
    local d = {"Bytes", "KiB", "MiB", "GiB", "TiB", "PiB"}
    local i = 1
    while b >= 1024 do
        b = b / 1024
        i = i + 1
    end
    return string.format("%0.2f %s", b, d[i] and d[i] or "*1024^" .. (i-1))
end

---@param t table
function mp_utils.subprocess(t)
    local cmd = {}
    cmd._name = "subprocess"
    cmd.capture_stdout = true
    for k, v in pairs(t) do
        if k == "cancellable" then
            k = "playback_only"
        elseif k == "max_size" then
            k = "capture_size"
        end
        cmd[k] = v
    end
    local res, err = mp.command_native(cmd)
    if res == nil then
        -- an error usually happens only if parsing failed (or no args passed)
        res = {error_string = err, status = -1}
    end
    if res.error_string ~= "" then
        res.error = res.error_string
    end
    return res
end

---@param t table
function mp_utils.subprocess_detached(t)
    mp.commandv("run", unpack(t.args))
end

mp.utils = mp_utils

-- mount ok
---@type mp_options?
mp.options = nil

return mp