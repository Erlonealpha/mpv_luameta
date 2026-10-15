---@meta

local mp = require "mp"

---@class mp_msg
local mp_msg = {}

mp_msg.log = mp.log
mp_msg.fatal = function(...) return mp.log("fatal", ...) end,
mp_msg.error = function(...) return mp.log("error", ...) end,
mp_msg.warn = function(...) return mp.log("warn", ...) end,
mp_msg.info = function(...) return mp.log("info", ...) end,
mp_msg.verbose = function(...) return mp.log("v", ...) end,
mp_msg.debug = function(...) return mp.log("debug", ...) end,
mp_msg.trace = function(...) return mp.log("trace", ...) end,

return mp_msg