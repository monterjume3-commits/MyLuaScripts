-- ThanonPhraKhrueang Hub v31 Loader
-- Ensure the repository and file path below match your GitHub upload.

local url = "https://raw.githubusercontent.com/monterjume3-commits/MyLuaScripts/main/ThanonPhraKhrueang_Hub_v34.lua"

local ok, source = pcall(function()
    return game:HttpGet(url)
end)

if not ok then
    warn("[ThanonPhraKhrueang Hub] Download failed: " .. tostring(source))
    return
end

if type(source) ~= "string" or source == "" then
    warn("[ThanonPhraKhrueang Hub] The downloaded file is empty.")
    return
end

local compileOk, chunk = pcall(loadstring, source)
if not compileOk or type(chunk) ~= "function" then
    warn("[ThanonPhraKhrueang Hub] Compile failed: " .. tostring(chunk))
    return
end

local runOk, err = pcall(chunk)
if not runOk then
    warn("[ThanonPhraKhrueang Hub] Runtime error: " .. tostring(err))
end
