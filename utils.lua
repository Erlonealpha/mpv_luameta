---@meta

---@alias mp_utils_file_info {
---     mode: int,
---     size: int,
---     atime: int,
---     mtime: int,
---     ctime: int,
---     is_file: boolean,
---     is_dir: boolean,
--- }

---@class mp_utils
local mp_utils = {}

---@param path string
---@param filter? "files" | "dirs" | "normal" | "all"
---@return_overload string[]
---@return_overload nil, string
function mp_utils.readdir(path, filter)
end

---@param path string
---@return string, string
function mp_utils.split_path(path)
end

---@param path string
---@return_overload mp_utils_file_info
---@return_overload nil, string
function mp_utils.file_info(path)
end

---@param path0 string
---@param path1 string
---@return string
function mp_utils.join_path(path0, path1)
end

---@return string[]
function mp_utils.get_env_list()
end

---@param str string
---@param trail? boolean
---@return_overload table, nil, string?
---@return_overload nil, string, string?
function mp_utils.parse_json(str, trail)
end

-- ---@param str string
-- ---@param trail true
-- ---@return table?, nil, string
-- function mp_utils.parse_json(str, trail)
-- end

---@param v any
---@return_overload string
---@return_overload nil, string
function mp_utils.format_json(v)
end

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

---Return res?, err?
---@return string?, string?
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

return mp_utils