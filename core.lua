-- Ignore some luacheck warnings about global vars, just use a ton of them in WoW Lua
-- luacheck: no global
-- luacheck: no self
local _, NotEvenClose = ...

NotEvenClose = LibStub("AceAddon-3.0"):NewAddon(NotEvenClose, "NotEvenClose", "AceConsole-3.0", "AceEvent-3.0")
LibRealmInfo = LibStub("LibRealmInfo")

-- Set up DataBroker for minimap button
NecLDB = LibStub("LibDataBroker-1.1"):NewDataObject("NotEvenClose", {
  type = "data source",
  text = "NotEvenClose",
  label = "NotEvenClose",
  icon = "Interface\\AddOns\\NotEvenClose\\logo",
  OnClick = function()
    if NecFrame and NecFrame:IsShown() then
      NecFrame:Hide()
    else
      NotEvenClose:PrintProfile(false)
    end
  end,
  OnTooltipShow = function(tt)
    tt:AddLine("NotEvenClose")
    tt:AddLine(" ")
    tt:AddLine("Click to show NotEvenClose input")
    tt:AddLine("To toggle minimap button, type '/nec minimap'")
  end
})

LibDBIcon = LibStub("LibDBIcon-1.0")

local NecFrame = nil

-- New talents for Dragonflight
local ClassTalents          = _G.C_ClassTalents
local Traits                = _G.C_Traits

-- GetAddOnMetadata was global until 10.1. It's now in C_AddOns. This line will use C_AddOns if available and work in either WoW build
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

-- Talent string export
local bitWidthHeaderVersion         = 8
local bitWidthSpecID                = 16
local bitWidthRanksPurchased        = 6

-- load stuff from extras.lua
-- local upgradeTable        = NotEvenClose.upgradeTable
local specNames           = NotEvenClose.SpecNames

-- Most of the guts of this addon were based on a variety of other ones, including
-- Statslog, AskMrRobot, and BonusScanner. And a bunch of hacking around with AceGUI.
-- Many thanks to the authors of those addons, and to reia for fixing my awful amateur
-- coding mistakes regarding objects and namespaces.

function NotEvenClose:OnInitialize()
  -- init databroker
  self.db = LibStub("AceDB-3.0"):New("NotEvenCloseDB", {
    profile = {
      minimap = {
        hide = false,
      },
      frame = {
        point = "CENTER",
        relativeFrame = nil,
        relativePoint = "CENTER",
        ofsx = 0,
        ofsy = 0,
        width = 750,
        height = 400,
      },
    },
  });
  LibDBIcon:Register("NotEvenClose", NecLDB, self.db.profile.minimap)
  NotEvenClose:UpdateMinimapButton()
  NotEvenClose:RegisterChatCommand('nec', 'HandleChatCommand')
  AddonCompartmentFrame:RegisterAddon({
    text = "NotEvenClose",
    icon = "Interface\\AddOns\\NotEvenClose\\logo",
    notCheckable = true,
    func = function()
      NotEvenClose:PrintProfile(false)
    end,
  })
end

function NotEvenClose:OnEnable()

end

function NotEvenClose:OnDisable()

end

function NotEvenClose:UpdateMinimapButton()
  if (self.db.profile.minimap.hide) then
    LibDBIcon:Hide("NotEvenClose")
  else
    LibDBIcon:Show("NotEvenClose")
  end
end

local function getLinks(input)
  local separatedLinks = {}
  for link in input:gmatch("|c.-|h|r") do
     separatedLinks[#separatedLinks + 1] = link
  end
  return separatedLinks
end

function NotEvenClose:HandleChatCommand(input)
  local args = {strsplit(' ', input)}

  local debugOutput = false
  local links = getLinks(input)

  for _, arg in ipairs(args) do
    if arg == 'debug' then
      debugOutput = true
    elseif arg == 'minimap' then
      self.db.profile.minimap.hide = not self.db.profile.minimap.hide
      DEFAULT_CHAT_FRAME:AddMessage(
        "NotEvenClose: Minimap button is now " .. (self.db.profile.minimap.hide and "hidden" or "shown")
      )
      NotEvenClose:UpdateMinimapButton()
      return
    end
  end

  self:PrintProfile(debugOutput, links)
end

-- method to add spaces to UnitRace names for proper tokenization
local function FormatRace(str)
  str = str or ""
  local matches = {}
  for match, _ in string.gmatch(str, '([%u][%l]*)') do
    matches[#matches+1] = match
  end
  return string.join(' ', unpack(matches))
end

local function GetBuffString()
  local buffs = {}
  AuraUtil.ForEachAura("player", "HELPFUL", 999999, function(...)
    local _, _, _, _, _, _, _, _, _, spellId, _, _, _, _, _ = ...;
    table.insert(buffs, spellId)
  end)
  return table.concat(buffs, ",")
end

function NotEvenClose:GetMainFrame(text)
  -- Frame code largely adapted from https://www.wowinterface.com/forums/showpost.php?p=323901&postcount=2
  if not NecFrame then
    -- Main Frame
    local frameConfig = self.db.profile.frame
    local f = CreateFrame("Frame", "NecFrame", UIParent, "DialogBoxFrame")
    f:ClearAllPoints()
    -- load position from local DB
    f:SetPoint(
      frameConfig.point,
      frameConfig.relativeFrame,
      frameConfig.relativePoint,
      frameConfig.ofsx,
      frameConfig.ofsy
    )
    f:SetSize(frameConfig.width, frameConfig.height)
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\PVPFrame\\UI-Character-PVP-Highlight",
      edgeSize = 16,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
      if button == "LeftButton" then
        self:StartMoving()
      end
    end)
    f:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
      self:StopMovingOrSizing()
      -- save position between sessions
      local point, relativeFrame, relativeTo, ofsx, ofsy = self:GetPoint()
      frameConfig.point = point
      frameConfig.relativeFrame = relativeFrame
      frameConfig.relativePoint = relativeTo
      frameConfig.ofsx = ofsx
      frameConfig.ofsy = ofsy
    end)

    -- scroll frame
    local sf = CreateFrame("ScrollFrame", "NecScrollFrame", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("LEFT", 16, 0)
    sf:SetPoint("RIGHT", -32, 0)
    sf:SetPoint("TOP", 0, -32)
    sf:SetPoint("BOTTOM", NecFrameButton, "TOP", 0, 0)

    -- edit box
    local eb = CreateFrame("EditBox", "NecEditBox", NecScrollFrame)
    eb:SetSize(sf:GetSize())
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject("ChatFontNormal")
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)

    -- resizing
    f:SetResizable(true)
    if f.SetMinResize then
      -- older function from shadowlands and before
      -- Can remove when Dragonflight is in full swing
      f:SetMinResize(150, 100)
    else
      -- new func for dragonflight
      f:SetResizeBounds(150, 100, nil, nil)
    end
    local rb = CreateFrame("Button", "SimcResizeButton", f)
    rb:SetPoint("BOTTOMRIGHT", -6, 7)
    rb:SetSize(16, 16)

    rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    rb:SetScript("OnMouseDown", function(self, button) -- luacheck: ignore
        if button == "LeftButton" then
            f:StartSizing("BOTTOMRIGHT")
            self:GetHighlightTexture():Hide() -- more noticeable
        end
    end)
    rb:SetScript("OnMouseUp", function(self, _) -- luacheck: ignore
        f:StopMovingOrSizing()
        self:GetHighlightTexture():Show()
        eb:SetWidth(sf:GetWidth())

        -- save size between sessions
        frameConfig.width = f:GetWidth()
        frameConfig.height = f:GetHeight()
    end)

    NecFrame = f
  end
  NecEditBox:SetText(text)
  NecEditBox:HighlightText()
  return NecFrame
end

-- Adapted from https://github.com/philanc/plc/blob/master/plc/checksum.lua
local function adler32(s)
  -- return adler32 checksum  (uint32)
  -- adler32 is a checksum defined by Mark Adler for zlib
  -- (based on the Fletcher checksum used in ITU X.224)
  -- implementation based on RFC 1950 (zlib format spec), 1996
  local prime = 65521 --largest prime smaller than 2^16
  local s1, s2 = 1, 0

  -- limit s size to ensure that modulo prime can be done only at end
  -- 2^40 is too large for WoW Lua so limit to 2^30
  if #s > (bit.lshift(1, 30)) then error("adler32: string too large") end

  for i = 1,#s do
    local b = string.byte(s, i)
    s1 = s1 + b
    s2 = s2 + s1
    -- no need to test or compute mod prime every turn.
  end

  s1 = s1 % prime
  s2 = s2 % prime

  return (bit.lshift(s2, 16)) + s1
end --adler32()

function NotEvenClose:GetNecProfile(debugOutput, links)
  -- addon metadata
  local versionComment = '# NotEvenClose Addon ' .. GetAddOnMetadata('NotEvenClose', 'Version')
  local wowVersion, wowBuild, _, wowToc = GetBuildInfo()
  local wowVersionComment = '# WoW ' .. wowVersion .. '.' .. wowBuild .. ', TOC ' .. wowToc

  -- Basic player info
  local stamina, _, _, _ = UnitStat("player", 3)
  local _, armor, _, _ = UnitArmor("player")
  local versatilityPercent = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
  local avoidancePercent = GetCombatRatingBonus(CR_AVOIDANCE)

  local playerName = UnitName('player')

  -- Race info
  local _, playerRace = UnitRace('player')

  -- fix some races to match SimC format
  if playerRace == 'Scourge' then --lulz
    playerRace = 'Undead'
  else
    playerRace = FormatRace(playerRace)
  end

  -- Spec info
  local className, _, _ = UnitClass("player")
  local role, globalSpecID
  local specId = GetSpecialization()
  if specId then
    globalSpecID,_,_,_,_,role = GetSpecializationInfo(specId)
  end
  local playerSpec = specNames[globalSpecID] or 'unknown'

  -- create a header comment with basic player info and a date
  local headerComment = (
    "# " .. playerName .. ' - ' .. playerSpec
    .. ' - ' .. date('%Y-%m-%d %H:%M') .. ' - '
 )

  -- Build the output string for the player (not including gear)
  local printError = nil
  local Profile = ''

  Profile = Profile .. headerComment .. '\n'
  Profile = Profile .. versionComment .. '\n'
  Profile = Profile .. wowVersionComment .. '\n'
  Profile = Profile .. '\n'

  Profile = Profile .. playerRace .. '\n'
  Profile = Profile .. "class=" .. className .. '\n'
  Profile = Profile .. 'spec=' .. playerSpec .. '\n'
  Profile = Profile .. "stamina=" .. stamina .. '\n'
  Profile = Profile .. "versatilityPercent=" .. versatilityPercent .. '\n'
  Profile = Profile .. "avoidancePercent=" .. avoidancePercent .. '\n'
  Profile = Profile .. "armor=" .. armor .. '\n'
  Profile = Profile .. '\n'
  Profile = Profile .. "buffs=" .. GetBuffString() .. '\n'
  Profile = Profile .. '\n'

  -- sanity checks - if there's anything that makes the output completely invalid, punt!
  if specId==nil then
    printError = "Error: You need to pick a spec!"
  end

  Profile = Profile .. '\n'

  -- Simple checksum to provide a lightweight verification that the input hasn't been edited/modified
  local checksum = adler32(Profile)

  Profile = Profile .. '# Checksum: ' .. string.format('%x', checksum)

  return Profile, printError
end

-- This is the workhorse function that constructs the profile
function NotEvenClose:PrintProfile(debugOutput, links)
  local NotEvenCloseProfile, necPrintError = NotEvenClose:GetNecProfile(debugOutput, links)

  local f = NotEvenClose:GetMainFrame(necPrintError or NotEvenCloseProfile)
  f:Show()
end
