--- ErrorHandler.lua Class for logging errors to the log.
-- @author Potdisc
-- Create Date: 16/04/2020
--- @type RCLootCouncil
local addon = select(2, ...)
---@class Services.ErrorHandler : AceEvent-3.0
local ErrorHandler = addon.Init "Services.ErrorHandler"
LibStub("AceEvent-3.0"):Embed(ErrorHandler)

local Log = addon.Require("Utils.Log"):Get()

local issecretvalue = issecretvalue or function() return false end -- Classic protection

local private = {
   MAX_STACK_DEPTH = 10,
}

local MAX_ERROR_TIME = 60 * 60 * 24 * 7 -- 1 week

function ErrorHandler:OnInitialize ()
   self:RegisterEvent("ADDON_ACTION_BLOCKED", "OnEvent")
   self:RegisterEvent("ADDON_ACTION_FORBIDDEN", "OnEvent")
   self:RegisterEvent("LUA_WARNING", "OnEvent")
	self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
   private.log = addon.db.global.errors or {}
   private:ClearOldErrors()
end

local eventsToSupress = {
	["ADDON_ACTION_BLOCKED"] = true,
	["ADDON_ACTION_FORBIDDEN"] = true,
	["LUA_WARNING"] = true,
}

local supressedEvents = {}

function ErrorHandler:OnEvent(...)
	local args = { ..., }
	if eventsToSupress[args[1]] then
		local msg = strjoin(", ", ...)
		if not supressedEvents[msg] then
			supressedEvents[msg] = 1
		else
			supressedEvents[msg] = supressedEvents[msg] + 1
			return
		end
	end
	addon.Log:W(...)
end

function ErrorHandler:OnLogout()
	addon.Log:D("Supressed events count:")
	for k, v in pairs(supressedEvents) do
		addon.Log:W(k, v)
	end
end

function ErrorHandler:LogError (msg)
   msg = private:SanitizeLine(msg)
   Log:e(msg)
   local errObj = private:DoesErrorExist(msg)
   if errObj then -- This is not the first
      private:IncrementErrorCount(errObj)
   else -- new error
      private:NewError(msg)
   end
end

--- Silently throws an error
function ErrorHandler:ThrowSilentError (message)
   local _, err = pcall(function ()
      private.ThrowError(message)
   end)
   self:LogError(err)
end

function private.ThrowError (message)
   error(message or "", 3)
end

function private:NewError (err)
   -- Build Call stack
   local stack = {}
   local i = 5 -- Skips those lines that caused by this class
   while true do
      local line = debugstack(i, 1, 0)
      if not line or line == "" then break end
      -- Exclude a few things from the code
      if not strmatch(line, "CallbackHandler%-1%.0")
      and not strmatch(line, "BugGrabber")
      and not strmatch(line, "%(tail call%)")
      and not strmatch(line, "(=%[C%])") then
         tinsert(stack, (self:SanitizeLine(line)))
         if #stack > self.MAX_STACK_DEPTH then
            break
         end
      end
      i = i + 1
   end
   self.log[#self.log + 1] = {
      msg = err,
      stack = stack,
      count = 1,
      time = GetServerTime()
   }
	if addon.DumpDebugVariables then
		addon:DumpDebugVariables() -- REVIEW: Consider make new errors subscribable to avoid this binding.
	end
end

function private:IncrementErrorCount (errObj)
   assert(type(errObj) == "table", "errObj must be an error object.")
   errObj.time = GetServerTime()
   errObj.count = errObj.count + 1
end

function private:SanitizeLine (line)
	if issecretvalue(line) then return line end
   	return line and line:gsub("Interface\\AddOns\\", "") or ""
end

function private:DoesErrorExist (err)
	if issecretvalue(err) then return false	end
	for _, v in ipairs(self.log or {}) do
		if v.msg == err then return v end
	end
	return false
end

function private:IsRCLootCouncilError (line)
   if not line then return false end
   -- Don't track lines related to the error handler
   if strfind(line, "ErrorHandler.lua") then
      return false

   elseif strmatch(line, "RCLootCouncil")
      or strmatch(line, "RCDebugger")
      then
         return true
      end
      return false
   end

   function private:ClearOldErrors ()
      local curTime = GetServerTime()
      for i = #self.log, 1, - 1 do
         if self.log[i].time + MAX_ERROR_TIME < curTime then
            tremove(self.log, i)
         end
      end
   end

   function private:ErrorHandler (msg)
      local msg = strtrim(tostring(msg or ""))
      -- Determine if it's an RCLootCouncil related error
      if not self:IsRCLootCouncilError(msg) then
         local found = false
         -- Check lower stack levels
         for i = 2, self.MAX_STACK_DEPTH do
            local line = debugstack(i, 1, 0)
            if self:IsRCLootCouncilError(line) then
               found = true
               break
            end
         end
         if not found then return end -- Not ours
      end
      -- We should handle it
      ErrorHandler:LogError(msg)
   end

   -- Setup error handler
   do
      local orig_errorhandler = geterrorhandler()
      -- Special case for buggrabber
      if BugGrabber and BugGrabber.RegisterCallback then
         BugGrabber.RegisterCallback({}, "BugGrabber_BugGrabbed", function(_, errObj)
            private:ErrorHandler(errObj.message)
         end)
      else
         seterrorhandler(function(...)
            -- WotLK re-entrancy guard: if our handler (or the original
            -- Blizzard handler it calls) throws, we must NOT recurse into
            -- ourselves — that produces a C stack overflow and a hard client
            -- crash on 3.3.5a. Guard with a flag and pcall both calls.
            if private._inErrorHandler then return end
            private._inErrorHandler = true
            local ok = pcall(private.ErrorHandler, private, ...)
            -- On 3.3.5a the stock Blizzard_DebugTools ScriptErrorsFrame often
            -- chokes ("bad argument #6 to 'format'") on errors that our own
            -- handler already captured, then that choke is itself reported,
            -- spamming the screen. Only forward to Blizzard's frame if OUR
            -- handler did NOT recognize/handle the error as ours.
            local msg = ...
            local isOurs = false
            if ok and msg and private.IsRCLootCouncilError then
               local okCheck, result = pcall(function()
                  return private:IsRCLootCouncilError(tostring(msg))
               end)
               isOurs = okCheck and result
            end
            if not isOurs then
               pcall(orig_errorhandler, ...)
            end
            private._inErrorHandler = false
         end)
      end
   end
