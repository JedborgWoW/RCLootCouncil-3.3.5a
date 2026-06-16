--- @type RCLootCouncil
local addon = select(2, ...)

local name = "RCButton"
--- @class RCButton  : BackdropTemplate, Button, UI.embeds
local Object = {}

function Object:New(parent, name)
   local b = addon.UI.CreateFrame("Button", parent:GetName()..name, parent, "UIPanelButtonTemplate")
	b:SetText("")
	b:SetSize(100,25)
	-- ASCENSION FIX: on 3.3.5a, UIPanelButtonTemplate buttons don't have a
	-- .Text property (retail-only); expose the font string as .Text so
	-- code like `button.Text:SetTextColor(...)` works.
	if not b.Text then
		b.Text = b:GetFontString() or _G[b:GetName().."Text"]
	end
	return b
end

addon.UI:RegisterElement(Object, name)
