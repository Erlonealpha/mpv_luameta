---@meta

--[[
This file is part of mpv.

mpv is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

mpv is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
]]

local utils = require "mp.utils"

---@class mp_input
local input = {}

local handle_counter = 0
local latest_handler_id
local latest_log_id

local function get_non_callbacks(t)
    local non_callbacks = {}

    for key, value in pairs(t) do
        if type(value) ~= "function" then
            non_callbacks[key] = value
        end
    end

    return non_callbacks
end

local function register_event_handler(t)
    local handler_id = "input-event/"..handle_counter
    handle_counter = handle_counter + 1
    latest_handler_id = handler_id

    mp.register_script_message(handler_id, function (event, args)
        if event == "closed" then
            mp.unregister_script_message(handler_id)
        end

        -- do not process events (other than closed) for an input that has been overwritten
        if not t[event] or (latest_handler_id ~= handler_id and event ~= "closed") then
            return
        end

        args = utils.parse_json(args or "") or {}

        if event == "complete" then
            local function complete(completions, completion_pos, completion_append)
                if not completions then
                    return
                end

                mp.commandv("script-message-to", "console", "complete", utils.format_json({
                                client_name = mp.get_script_name(),
                                handler_id = handler_id,
                                original_line = args[1],
                                list = completions,
                                start_pos = completion_pos,
                                append = completion_append or "",
                            }))
            end

            args[2] = complete
            complete(t[event](unpack(args)))
        else
            t[event](unpack(args))
        end
    end)

    return handler_id
end

local function input_request(t)
    t.has_completions = t.complete ~= nil
    t.client_name = mp.get_script_name()
    t.handler_id = register_event_handler(t)

    mp.commandv("script-message-to", "console", "get-input",
                utils.format_json(get_non_callbacks(t)))
end

--[[
    prompt:
        要显示在输入框前的字符串。
    submit:
        当用户按下回车键时，会调用一个回调函数。第一个参数是控制台中显示的文本。
    keep_open:
        提交时是否保持控制台打开。默认为 false 。
    opened:
        控制台显示时调用的回调函数。可用于显示包含 input.set_log() 的选项列表。
    complete:
        当文本发生变化时，会调用此回调函数。第一个参数是控制台中显示的文本。
        当用户编辑文本或移动光标时，会调用此回调函数。第一个参数是光标之前的文本。
        回调函数应返回一个表格，其中包含字符串补全候选值以及从光标位置开始补全的起始位置（从 1 开始计数）。
        控制台将显示与光标位置和当前位置之间的文本大致匹配的补全结果，并允许用户选择它们。
        第三个可选返回值是一个字符串，该字符串将附加到输入行，但不会显示在自动补全中。
    autoselect_completion:
        提交时是否自动选择第一个自动完成选项（如果尚未手动选择）。默认值为 false 。
    closed:
        当控制台被隐藏时（可能是因为以下原因），会调用一个回调函数： input.terminate() 是由其他回调函数调用，
        或是因为用户使用快捷键关闭了它。第一个参数是控制台中的文本，第二个参数是光标位置。
    default_text:
        要预先填充输入字段的字符串。
    cursor_position:
        光标初始位置，从 1 开始。
    history_path:
        如果指定，则保存和加载输入行历史记录的路径。
    id:
        用于确定在为 input.get() 次调用存储的输入历史记录和日志缓冲区中，使用哪个缓冲区的标识符。
        默认值为调用脚本名称后附加 prompt 。
]]
---@alias input_get_table {
---     prompt: string,
---     submit: fun(text:string),
---     keep_open: boolean,
---     opened: fun(),
---     edited: fun(),
---     complete: fun(text:string):table,
---     autoselect_completion: boolean,
---     closed: fun(text:string,pos:int),
---     default_text: string,
---     cursor_position: int,
---     history_path: string?,
---     id: int?,
--- }

---@param t input_get_table
function input.get(t)
    t.prompt = tostring(t.prompt or "")

    -- input.select does not support log buffers, so cannot override the latest id.
    t.id = t.id or mp.get_script_name() .. t.prompt
    latest_log_id = t.id
    return input_request(t)
end

--[[
    prompt:
        要显示在输入框前的字符串。
    items:
        可供选择的条目表格。
    default_item:
        预选项的从 1 开始的整数索引。
    submit:
        当用户按下回车键时，会调用此回调函数。第一个参数是所选项目的从 1 开始的索引。
    keep_open:
        提交时是否保持控制台打开。默认为 false 。
]]
---@alias input_select_table {
---     prompt: string,
---     items: table[],
---     default_item: int,
---     submit: int,
---     keep_open: boolean,
--- }

-- 指定要向用户展示以供选择的项目列表。
---@param t input_select_table
function input.select(t)
    -- Ensures that console.lua treats this request as a select request.
    t.items = t.items or {}
    return input_request(t)
end

function input.terminate()
    mp.commandv("script-message-to", "console", "disable", utils.format_json({
                    client_name = mp.get_script_name(),
                }))
end

function input.log(message, style, terminal_style)
    mp.commandv("script-message-to", "console", "log", utils.format_json({
                    log_id = latest_log_id,
                    text = message,
                    style = style,
                    terminal_style = terminal_style,
                }))
end

function input.log_error(message)
    mp.msg.warn("log_error is deprecated and will be removed.")

    mp.commandv("script-message-to", "console", "log", utils.format_json({
                    log_id = latest_log_id,
                    text = message,
                    error = true,
                }))
end

function input.set_log(log)
    if latest_log_id then
        mp.commandv("script-message-to", "console", "set-log",
            latest_log_id, utils.format_json(log))
    end
end

return input
