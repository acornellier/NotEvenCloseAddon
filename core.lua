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

local OFFSET_ITEM_ID = 1
local OFFSET_ENCHANT_ID = 2
local OFFSET_GEM_ID_1 = 3
-- local OFFSET_GEM_ID_2 = 4
-- local OFFSET_GEM_ID_3 = 5
local OFFSET_GEM_ID_4 = 6
local OFFSET_GEM_BASE = OFFSET_GEM_ID_1
local OFFSET_SUFFIX_ID = 7
-- local OFFSET_FLAGS = 11
-- local OFFSET_CONTEXT = 12
local OFFSET_BONUS_ID = 13

local OFFSET_GEM_BONUS_FROM_MODS = 2

local ITEM_MOD_TYPE_DROP_LEVEL = 9
-- 28 shows frequently but is currently unknown
local ITEM_MOD_TYPE_CRAFT_STATS_1 = 29
local ITEM_MOD_TYPE_CRAFT_STATS_2 = 30

local WeeklyRewards         = _G.C_WeeklyRewards

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
local slotNames           = NotEvenClose.slotNames
local simcSlotNames       = NotEvenClose.simcSlotNames
local specNames           = NotEvenClose.SpecNames
local profNames           = NotEvenClose.ProfNames
local regionString        = NotEvenClose.RegionString
local zandalariLoaBuffs   = NotEvenClose.zandalariLoaBuffs

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


local function GetItemSplit(itemLink)
  local itemString = string.match(itemLink, "item:([%-?%d:]+)")
  local itemSplit = {}

  -- Split data into a table
  for _, v in ipairs({strsplit(":", itemString)}) do
    if v == "" then
      itemSplit[#itemSplit + 1] = 0
    else
      itemSplit[#itemSplit + 1] = tonumber(v)
    end
  end

  return itemSplit
end

local function GetItemName(itemLink)
  local name = string.match(itemLink, '|h%[(.*)%]|')
  local removeIcons = gsub(name, '|%a.+|%a', '')
  local trimmed = string.match(removeIcons, '^%s*(.*)%s*$')
  -- check for empty string or only spaces
  if string.match(trimmed, '^%s*$') then
    return nil
  end

  return trimmed
end

-- char size for utf8 strings
local function ChrSize(char)
  if not char then
      return 0
  elseif char > 240 then
      return 4
  elseif char > 225 then
      return 3
  elseif char > 192 then
      return 2
  else
      return 1
  end
end

-- SimC tokenize function
local function Tokenize(str)
  str = str or ""
  -- convert to lowercase and remove spaces
  str = string.lower(str)
  str = string.gsub(str, ' ', '_')

  -- keep stuff we want, dumpster everything else
  local s = ""
  for i=1,str:len() do
    local b = str:byte(i)
    -- keep digits 0-9
    if b >= 48 and b <= 57 then
      s = s .. str:sub(i,i)
      -- keep lowercase letters
    elseif b >= 97 and b <= 122 then
      s = s .. str:sub(i,i)
      -- keep %, +, ., _
    elseif b == 37 or b == 43 or b == 46 or b == 95 then
      s = s .. str:sub(i,i)
      -- save all multibyte chars
    elseif ChrSize(b) > 1 then
      local offset = ChrSize(b) - 1
      s = s .. str:sub(i, i + offset)
      i = i + offset -- luacheck: no unused
    end
  end
  -- strip trailing spaces
  if string.sub(s, s:len())=='_' then
    s = string.sub(s, 0, s:len()-1)
  end
  return s
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

-- =================== Item Information =========================

local function GetItemStringFromItemLink(slotNum, itemLink, debugOutput)
  local itemSplit = GetItemSplit(itemLink)
  local simcItemOptions = {}
  local gems = {}
  local gemBonuses = {}

  -- Item id
  local itemId = itemSplit[OFFSET_ITEM_ID]
  simcItemOptions[#simcItemOptions + 1] = ',id=' .. itemId

  -- Enchant
  if itemSplit[OFFSET_ENCHANT_ID] > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'enchant_id=' .. itemSplit[OFFSET_ENCHANT_ID]
  end

  -- Gems
  for gemOffset = OFFSET_GEM_ID_1, OFFSET_GEM_ID_4 do
    local gemIndex = (gemOffset - OFFSET_GEM_BASE) + 1
    gems[gemIndex] = 0
    gemBonuses[gemIndex] = 0
    if itemSplit[gemOffset] > 0 then
      local gemId = itemSplit[gemOffset]
      if gemId > 0 then
        gems[gemIndex] = gemId
      end
    end
  end

  -- Remove any trailing zeros from the gems array
  while #gems > 0 and gems[#gems] == 0 do
    table.remove(gems, #gems)
  end

  if #gems > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'gem_id=' .. table.concat(gems, '/')
  end

  -- New style item suffix, old suffix style not supported
  if itemSplit[OFFSET_SUFFIX_ID] ~= 0 then
    simcItemOptions[#simcItemOptions + 1] = 'suffix=' .. itemSplit[OFFSET_SUFFIX_ID]
  end

  local bonuses = {}

  for index=1, itemSplit[OFFSET_BONUS_ID] do
    bonuses[#bonuses + 1] = itemSplit[OFFSET_BONUS_ID + index]
  end

  if #bonuses > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'bonus_id=' .. table.concat(bonuses, '/')
  end

  -- Shadowlands looks like it changed the item string
  -- There's now a variable list of additional data after bonus IDs, looks like some kind of type/value pairs
  local linkOffset = OFFSET_BONUS_ID + #bonuses + 1

  local craftedStats = {}
  local numPairs = itemSplit[linkOffset]
  for index=1, numPairs do
    local pairOffset = 1 + linkOffset + (2 * (index - 1))
    local pairType = itemSplit[pairOffset]
    local pairValue = itemSplit[pairOffset + 1]
    if pairType == ITEM_MOD_TYPE_DROP_LEVEL then
      simcItemOptions[#simcItemOptions + 1] = 'drop_level=' .. pairValue
    elseif pairType == ITEM_MOD_TYPE_CRAFT_STATS_1 or pairType == ITEM_MOD_TYPE_CRAFT_STATS_2 then
      craftedStats[#craftedStats + 1] = pairValue
    end
  end

  if #craftedStats > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'crafted_stats=' .. table.concat(craftedStats, '/')
  end

  -- gem bonuses
  local gemBonusOffset = linkOffset + (2 * numPairs) + OFFSET_GEM_BONUS_FROM_MODS
  local numGemBonuses = itemSplit[gemBonusOffset]
  local gemBonuses = {}
  for index=1, numGemBonuses do
    local offset = gemBonusOffset + index
    gemBonuses[index] = itemSplit[offset]
  end

  if #gemBonuses > 0 then
    simcItemOptions[#simcItemOptions + 1] = 'gem_bonus_id=' .. table.concat(gemBonuses, '/')
  end

  local craftingQuality = C_TradeSkillUI.GetItemCraftedQualityByItemInfo(itemLink);
  if craftingQuality then
    simcItemOptions[#simcItemOptions + 1] = 'crafting_quality=' .. craftingQuality
  end

  local itemStr = ''
  itemStr = itemStr .. (simcSlotNames[slotNum] or 'unknown') .. "=" .. table.concat(simcItemOptions, ',')
  if debugOutput then
    itemStr = itemStr .. '\n# ' .. gsub(itemLink, "\124", "\124\124") .. '\n'
  end

  return itemStr
end

function NotEvenClose:GetItemStrings(debugOutput)
  local items = {}
  for slotNum=1, #slotNames do
    local slotId = GetInventorySlotInfo(slotNames[slotNum])
    local itemLink = GetInventoryItemLink('player', slotId)

    -- if we don't have an item link, we don't care
    if itemLink then
      -- In theory, this should always be loaded/cached
      local name = GetItemName(itemLink)

      -- get correct level for scaling gear
      local level, _, _ = GetDetailedItemLevelInfo(itemLink)

      local itemComment
      if name and level then
        itemComment = name .. ' (' .. level .. ')'
      end

      items[slotNum] = {
        string = GetItemStringFromItemLink(slotNum, itemLink, debugOutput),
        name = itemComment
      }
    end
  end

  return items
end

-- Iterate through all container slots looking for gear that can be equipped.
-- Item name and item level may not be available if other addons are causing lookups to be throttled but
-- item links and IDs should always be available
function NotEvenClose:GetBagItemStrings(debugOutput)
  local bagItems = {}

  -- https://wowpedia.fandom.com/wiki/BagID
  -- Bag indexes are a pain, need to start in the negatives to check everything (like the default bank container)
  for bag=BACKPACK_CONTAINER - ITEM_INVENTORY_BANK_BAG_OFFSET, NUM_TOTAL_EQUIPPED_BAG_SLOTS + NUM_BANKBAGSLOTS do
    for slot=1, C_Container.GetContainerNumSlots(bag) do
      local itemId = C_Container.GetContainerItemID(bag, slot)

      -- something is in the bag slot
      if itemId then
        local _, _, _, itemEquipLoc = GetItemInfoInstant(itemId)
        local slotNum = NotEvenClose.invTypeToSlotNum[itemEquipLoc]

        -- item can be equipped
        if slotNum then
          local info = C_Container.GetContainerItemInfo(bag, slot)
          local itemLink = C_Container.GetContainerItemLink(bag, slot)
          bagItems[#bagItems + 1] = {
            string = GetItemStringFromItemLink(slotNum, itemLink, debugOutput),
            slotNum = slotNum
          }
          local itemName = GetItemName(itemLink)
          local level, _, _ = GetDetailedItemLevelInfo(itemLink)
          if itemName and level then
            bagItems[#bagItems].name = itemName .. ' (' .. level .. ')'
          end
        end
      end
    end
  end

  -- order results by paper doll slot, not bag slot
  table.sort(bagItems, function (a, b) return a.slotNum < b.slotNum end)

  return bagItems
end

-- Scan buffs to determine which loa racial this player has, if any
function NotEvenClose:GetZandalariLoa()
  local zandalariLoa = nil
  for index = 1, 32 do
    local _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", index)
    if spellId == nil then
      break
    end
    if zandalariLoaBuffs[spellId] then
      zandalariLoa = zandalariLoaBuffs[spellId]
      break
    end
  end
  return zandalariLoa
end

function NotEvenClose:GetSlotHighWatermarks()
  if C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkForSlot then
    local slots = {}
    -- These are not normal equipment slots, they are Enum.ItemRedundancySlot
    for slot = 0, 16 do
      local characterHighWatermark, accountHighWatermark = C_ItemUpgrade.GetHighWatermarkForSlot(slot)
      if characterHighWatermark or accountHighWatermark then
        slots[#slots + 1] = table.concat({  slot, characterHighWatermark, accountHighWatermark }, ':')
      end
    end
    return table.concat(slots, '/')
  end
end

function NotEvenClose:GetUpgradeCurrencies()
  local upgradeCurrencies = {}
  -- Collect actual currencies
  for currencyId, currencyName in pairs(NotEvenClose.upgradeCurrencies) do
    local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyId)
    if currencyInfo and currencyInfo.quantity > 0 then
      upgradeCurrencies[#upgradeCurrencies + 1] = table.concat({ "c", currencyId, currencyInfo.quantity }, ':')
    end
  end

  -- Collect items that get used as currencies
  for itemId, itemName in pairs(NotEvenClose.upgradeItems) do
    local count = GetItemCount(itemId, true, true, true)
    if count > 0 then
      upgradeCurrencies[#upgradeCurrencies + 1] = table.concat({ "i", itemId, count }, ':')
    end
  end

  return table.concat(upgradeCurrencies, '/')
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
  local versatility = GetCombatRating(29)
  local avoidance = GetCombatRating(21)

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
  Profile = Profile .. "versatility=" .. versatility .. '\n'
  Profile = Profile .. "avoidance=" .. avoidance .. '\n'
  Profile = Profile .. "armor=" .. armor .. '\n'
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
