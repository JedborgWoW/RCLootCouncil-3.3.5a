--- RCLootCouncil_Debug.lua
--- OPTIONAL diagnostic helper for the WotLK 3.3.5a backport.
--- Adds a single slash command, /rcdbg, that dumps the gear/diff/response
--- state of the current voting-frame session so you can verify cross-client
--- gear propagation without guessing.
---
--- To remove: delete this file and its line in RCLootCouncil.toc.
--- It is purely read-only and never alters addon behaviour.

local addon = select(2, ...)

local function GetVF()
	return addon.GetActiveModule and addon:GetActiveModule("votingframe")
end

SLASH_RCDBG1 = "/rcdbg"
SlashCmdList["RCDBG"] = function()
	local vf = GetVF()
	if not vf or not vf.GetLootTable then
		print("|cffff0000[RCDBG]|r voting frame not active (start/receive a session first).")
		return
	end
	local lt = vf:GetLootTable()
	if type(lt) ~= "table" or #lt == 0 then
		print("|cffff0000[RCDBG]|r no active loot table.")
		return
	end
	print("|cff66ccff[RCDBG]|r loot table: " .. #lt .. " session(s)")
	for ses, data in ipairs(lt) do
		print(("|cffffd100session %d|r  item=%s"):format(ses, tostring(data.link or data.string or "?")))
		local cands = data.candidates
		if type(cands) ~= "table" then
			print("    |cffff0000(no candidates table)|r")
		else
			for name, c in pairs(cands) do
				print(("    cand='%s'  resp=%s  diff=%s  g1=%s  g2=%s"):format(
					tostring(name),
					tostring(c.response),
					tostring(c.diff),
					tostring(c.gear1),
					tostring(c.gear2)))
			end
		end
	end
	print("|cff66ccff[RCDBG]|r If every cand now shows g1/diff (not just you), the fix is working.")
end
