local MAJOR, MINOR = "LibElvUIPlugin-1.0", 42
local lib = _G.LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
-- GLOBALS: ElvUI

--[[----------------------------
Plugin Table Format:  (for reference only).
	{
		name		- name of the plugin
		callback	- callback to call when ElvUI_OptionsUI is loaded
		isLib		- plugin is a library
		version		- version of the plugin (pulls version info from metadata, libraries can define their own)

	-- After new version recieved from another user:
		old			- plugin is old version
		newversion	- newer version number
	}

LibElvUIPlugin API:
	RegisterPlugin(name, callback, isLib, libVersion)
	-- Registers a module with the given name and option callback:
		name		- name of plugin
		verion		- version number
		isLib		- plugin is a library
		libVersion	- plugin library version (optional, defaults to 1)

	HookInitialize(table, function)
	-- Posthook ElvUI Initialize function:
		table		- addon table
		function	- function to call after Initialize (may be a string, that exists on the addons table: table['string'])
----------------------------]]--

local tonumber, strmatch, strsub, tinsert, strtrim = tonumber, strmatch, strsub, tinsert, strtrim
local unpack, assert, pairs, ipairs, strlen, pcall, xpcall = unpack, assert, pairs, ipairs, strlen, pcall, xpcall
local format, wipe, type, gmatch, gsub, ceil = format, wipe, type, gmatch, gsub, ceil

local geterrorhandler = geterrorhandler
local hooksecurefunc = hooksecurefunc
local GetAddOnMetadata = GetAddOnMetadata
local GetNumPartyMembers, GetNumRaidMembers = GetNumPartyMembers, GetNumRaidMembers
local GetLocale, IsInGuild = GetLocale, IsInGuild
local CreateFrame, IsAddOnLoaded = CreateFrame, IsAddOnLoaded
local IsInInstance = IsInInstance
local SendAddonMessage = SendAddonMessage
local UNKNOWN = UNKNOWN

lib.prefix = "ElvUIPluginVC"
lib.plugins = {}
lib.groupSize = 0
lib.index = 0

local MSG_OUTDATED = "Your version of %s %s is out of date (latest is version %s). You can download the latest version from https://github.com/ElvUI-WotLK"
local HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - Plugins Loaded  (Green means you have current version, Red means out of date)"
local INFO_BY = "by"
local INFO_VERSION = "Version:"
local INFO_NEW = "Newest:"
local LIBRARY = "Library"

local locale = GetLocale()
if locale == "deDE" then
	MSG_OUTDATED = "Deine Version von %s %s ist veraltet (akutelle Version ist %s). Du kannst die aktuelle Version von https://github.com/ElvUI-WotLK herunterrladen."
	HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - Plugins geladen (Grün bedeutet du hast die aktuelle Version, Rot bedeutet es ist veraltet)"
	INFO_BY = "von"
	INFO_VERSION = "Version:"
	INFO_NEW = "Neuste:"
	LIBRARY = "Bibliothek"
elseif locale == "ruRU" then
	MSG_OUTDATED = "Ваша версия %s %s устарела (последняя версия %s). Вы можете скачать последнюю версию на https://github.com/ElvUI-WotLK"
	HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - загруженные плагины (зеленый означает, что у вас последняя версия, красный - устаревшая)"
	INFO_BY = "от"
	INFO_VERSION = "Версия:"
	INFO_NEW = "Последняя:"
	LIBRARY = "Библиотека"
elseif locale == "zhCN" then
	MSG_OUTDATED = "你的 %s %s 版本已经过期 (最新版本是 %s)。你可以从 https://github.com/ElvUI-WotLK 下载最新版本"
	HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - 载入的插件 (绿色表示拥有当前版本, 红色表示版本已经过期)"
	INFO_BY = "作者"
	INFO_VERSION = "版本:"
	INFO_NEW = "最新:"
	LIBRARY = "库"
elseif locale == "zhTW" then
	MSG_OUTDATED = "你的 %s %s 版本已經過期 (最新版本為 %s)。你可以透過 https://github.com/ElvUI-WotLK 下載最新的版本"
	HDR_INFORMATION = "LibElvUIPlugin-1.0.%d - 載入的插件 (綠色表示擁有當前版本, 紅色表示版本已經過期)"
	INFO_BY = "作者"
	INFO_VERSION = "版本:"
	INFO_NEW = "最新:"
	LIBRARY = "庫"
end

local E, L
local function checkElvUI()
	if not E then
		if ElvUI then
			E, L = unpack(ElvUI)
		end

		assert(E, "ElvUI not found.")
	end
end

function lib:RegisterPlugin(name, callback, isLib, libVersion)
	checkElvUI()

	local plugin = {
		name = name,
		callback = callback,
		title = GetAddOnMetadata(name, "Title"),
		author = GetAddOnMetadata(name, "Author")
	}

	if plugin.title then plugin.title = strtrim(plugin.title) end
	if plugin.author then plugin.author = strtrim(plugin.author) end

	if isLib then
		plugin.isLib = true
		plugin.version = libVersion or 1
	else
		plugin.version = (name == MAJOR and MINOR) or GetAddOnMetadata(name, "Version") or UNKNOWN
	end

	lib.plugins[name] = plugin

	if not lib.registeredPrefix then
		lib.VCFrame:RegisterEvent("CHAT_MSG_ADDON")
		lib.VCFrame:RegisterEvent("RAID_ROSTER_UPDATE")
		lib.VCFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
		lib.VCFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		lib.registeredPrefix = true
	end

	local loaded = IsAddOnLoaded("ElvUI_OptionsUI")
	if not loaded then
		lib.CFFrame:RegisterEvent("ADDON_LOADED")
	elseif loaded then
		if name ~= MAJOR then
			E.Options.args.plugins.args.plugins.name = lib:GeneratePluginList()
		end

		if callback then
			pcall(callback)
		end
	end

	return plugin
end

local function SendVersionCheckMessage()
	lib:SendPluginVersionCheck(lib:GenerateVersionCheckMessage())
end

function lib:DelayedSendVersionCheck(delay)
	if not E.SendPluginVersionCheck then
		E.SendPluginVersionCheck = SendVersionCheckMessage
	end

	if not lib.SendMessageWaiting then
		lib.SendMessageWaiting = E:Delay(delay or 10, E.SendPluginVersionCheck)
	end
end

local function errorhandler(err)
	return geterrorhandler()(err)
end

function lib:OptionsLoaded(_, addon)
	if addon == "ElvUI_OptionsUI" then
		lib:GetPluginOptions()

		for _, plugin in pairs(lib.plugins) do
			if plugin.callback then
				xpcall(plugin.callback, errorhandler)
			end
		end

		lib.CFFrame:UnregisterEvent("ADDON_LOADED")
	end
end

function lib:GenerateVersionCheckMessage()
	local list = ""
	for _, plugin in pairs(lib.plugins) do
		if plugin.name ~= MAJOR then
			list = list .. plugin.name .. "=" .. plugin.version .. ";"
		end
	end
	return list
end

function lib:GetPluginOptions()
	E.Options.args.plugins = E.Libs.ACH:Group(L["Plugins"], nil, 5)
	E.Options.args.plugins.args.pluginheader = E.Libs.ACH:Header(format(HDR_INFORMATION, MINOR), 1)
	E.Options.args.plugins.args.plugins = E.Libs.ACH:Description(lib:GeneratePluginList(), 2)
end

do	-- this will handle `8.1.5.0015` into `8.150015` etc
	local verStrip = function(a, b) return a..gsub(b,"%.", "") end
	function lib:StripVersion(version)
		local ver = gsub(version, "(%d-%.)([%d%.]+)", verStrip)
		return tonumber(ver)
	end
end

function lib:VersionCheck(event, prefix, msg, _, senderOne, senderTwo)
	if event == "CHAT_MSG_ADDON" and prefix == lib.prefix then
		local sender = strfind(senderOne, "-") and senderOne or senderTwo
		if sender and msg and not strmatch(msg, "%s-$") then
			if not lib.myName then lib.myName = format("%s-%s", E.myname, E:ShortenRealm(E.myrealm)) end
			if sender == lib.myName then return end

			if not E.pluginRecievedOutOfDateMessage then
				for name, version in gmatch(msg, "([^=]+)=([%d%p]+);") do
					local plugin = (version and name) and lib.plugins[name]
					if plugin and plugin.version then
						local Pver, ver = lib:StripVersion(plugin.version), lib:StripVersion(version)
						if (ver and Pver) and (ver > Pver) then
							plugin.old, plugin.newversion = true, version
							E:Print(format(MSG_OUTDATED, plugin.title or plugin.name, plugin.version, plugin.newversion))
							E.pluginRecievedOutOfDateMessage = true
						end
					end
				end
			end
		end
	elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
		local numRaid, numParty = GetNumRaidMembers(), GetNumPartyMembers() + 1
		local num = numRaid > 0 and numRaid or numParty
		if num ~= lib.groupSize then
			if num > 1 and num > lib.groupSize then
				lib:DelayedSendVersionCheck()
			end
			lib.groupSize = num
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		lib:DelayedSendVersionCheck()
	end
end

function lib:GeneratePluginList()
	local list = ""
	for _, plugin in pairs(lib.plugins) do
		if plugin.name ~= MAJOR then
			local color = (plugin.old and E:RGBToHex(1, 0, 0)) or E:RGBToHex(0, 1, 0)
			list = list .. (plugin.title or plugin.name)
			if plugin.author then list = list .. " " .. INFO_BY .. " " .. plugin.author end
			list = list .. color .. (plugin.isLib and " " .. LIBRARY or " - " .. INFO_VERSION .. " " .. plugin.version)
			if plugin.old then list = list .. " (" .. INFO_NEW .. plugin.newversion .. ")" end
			list = list .. "|r\n"
		end
	end
	return list
end

function lib:ClearSendMessageWait()
	lib.SendMessageWaiting = nil
end

function lib:SendPluginVersionCheck(message)
	if (not message) or strmatch(message, "^%s-$") then
		lib.ClearSendMessageWait()
		return
	end

	local ChatType
	if GetNumRaidMembers() > 1 then
		local _, instanceType = IsInInstance()
		ChatType = instanceType == "pvp" and "BATTLEGROUND" or "RAID"
	elseif GetNumPartyMembers() > 0 then
		ChatType = "PARTY"
	elseif IsInGuild() then
		ChatType = "GUILD"
	end

	if not ChatType then
		lib.ClearSendMessageWait()
		return
	end

	local delay, maxChar, msgLength = 0, 250, strlen(message)
	if msgLength > maxChar then
		local splitMessage
		for _ = 1, ceil(msgLength / maxChar) do
			splitMessage = strmatch(strsub(message, 1, maxChar), ".+;")
			if splitMessage then -- incase the string is over 250 but doesn't contain `;`
				message = gsub(message, "^" .. E:EscapeString(splitMessage), "")
				E:Delay(delay, SendAddonMessage, lib.prefix, splitMessage, ChatType)
				delay = delay + 1
			end
		end

		E:Delay(delay, lib.ClearSendMessageWait)
	else
		SendAddonMessage(lib.prefix, message, ChatType)
		lib.ClearSendMessageWait()
	end
end

function lib.Initialized()
	if not lib.inits then return end

	for _, initTbl in ipairs(lib.inits) do
		initTbl[2](initTbl[1])
	end

	wipe(lib.inits)
end

function lib:HookInitialize(tbl, func)
	if not (tbl and func) then return end

	if type(func) == "string" then
		func = tbl[func]
	end

	if not self.inits then
		self.inits = {}
		checkElvUI()
		hooksecurefunc(E, "Initialize", self.Initialized)
	end

	tinsert(lib.inits, { tbl, func })
end

lib.VCFrame = CreateFrame("Frame")
lib.VCFrame:SetScript("OnEvent", lib.VersionCheck)

lib.CFFrame = CreateFrame("Frame")
lib.CFFrame:SetScript("OnEvent", lib.OptionsLoaded)