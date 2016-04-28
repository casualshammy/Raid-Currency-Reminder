---------------------
----- Constants -----
---------------------
local SEAL_CURRENCY_ID = 1129;
local MAX_SEALS_FROM_QUESTS = 3;
local MAX_SEALS_PER_CHARACTER = 10;
local MIN_CHARACTER_LEVEL_REQUIRED = 100;
local SEAL_TEXTURE = [[Interface\Icons\achievement_battleground_templeofkotmogu_02_green]];
local SEAL_TEXTURE_BW = [[Interface\AddOns\RaidCurrencyReminder\media\achievement_battleground_templeofkotmogu_02_green_bw.tga]];
local SEAL_LINK = GetCurrencyLink(SEAL_CURRENCY_ID);
local INTERVAL_BETWEEN_PERIODIC_NOTIFICATIONS = 900;
local MIN_INTERVAL_BETWEEN_PRINTS = 30;
---------------------
---------------------

local LDBPlugin;
local LastAvailableSealsAmount = -1;
local CalendarOpened = false;
local LastTimePrint = 0;
local DisablePrintUntilReload = false;

local quests = {
	36054, -- // gold
	37454, -- // 2x gold
	37455, -- // 4x gold
	36055, -- // apexis
	37452, -- // 2x apexis
	37453, -- // 4x apexis
	36057, -- // honor
	37458, -- // 2x honor
	37459, -- // 4x honor
	36056, -- // g_res
	37456, -- // 2x g_res
	37457, -- // 4x g_res
	36058, -- // Bunker/Mill
};

local holidayEvents = {
	["calendar_weekendburningcrusade"] = 	 39020,
	["calendar_weekendwrathofthelichking"] = 39021,
	["calendar_weekendcataclysm"] = 		 40792,
};

local function ColorizeText(text, r, g, b)
	return format("|cff%02x%02x%02x%s|r", r*255, g*255, b*255, text);
end

local function Print(...)
	local text = "";
	for i = 1, select("#", ...) do
		text = text..tostring(select(i, ...)).." "
	end
	DEFAULT_CHAT_FRAME:AddMessage(text, 1, 0.5, 0);
end

local function PlayerOwnsBunker()
	local t = C_Garrison.GetPlots();
	if (t ~= nil and #t > 0) then
		for _, value in pairs(t) do
			if (value.size == 3) then
				local buildingID = C_Garrison.GetOwnedBuildingInfo(value.id);
				if (buildingID == 10) then
					return true;
				end
			end
		end
	end
	return false;
end

local function GetNumAvailableSeals()
	local numQuestsAvailable = MAX_SEALS_FROM_QUESTS;
	for _, questID in pairs(quests) do
		if (IsQuestFlaggedCompleted(questID)) then
			numQuestsAvailable = numQuestsAvailable - 1;
		end
	end
	if (numQuestsAvailable < 0) then
		Print("RCR: MAX_SEALS_FROM_QUESTS has incorrect value!");
		numQuestsAvailable = 0;
	end
	
	local _, _, day = CalendarGetDate();
	for eventIndex = 1, CalendarGetNumDayEvents(0, day) do
		local _, _, _, calendarType, _, _, texture = CalendarGetDayEvent(0, day, eventIndex);
		if (calendarType == "HOLIDAY") then
			local questID = holidayEvents[texture];
			if (questID ~= nil) then
				if (not IsQuestFlaggedCompleted(questID)) then
					return numQuestsAvailable, 1;
				end
			end
		end
	end
	return numQuestsAvailable, 0;
end

local function GetNumObtainableSeals()
	if (UnitLevel("player") >= MIN_CHARACTER_LEVEL_REQUIRED) then
		local _, amount = GetCurrencyInfo(SEAL_CURRENCY_ID);
		local amountFromRegularQuests, amountFromHoliday = GetNumAvailableSeals();
		return min(amountFromRegularQuests + amountFromHoliday, MAX_SEALS_PER_CHARACTER - amount);
	else
		return 0;
	end
end

local function PrintInfo()
	if (not DisablePrintUntilReload) then
		Print("-----------------------------------");
		local numFromQuests, numFromHoliday = GetNumAvailableSeals();
		if (numFromQuests > 0) then
			Print(format("You can buy %s %s", numFromQuests, SEAL_LINK));
		end
		if (numFromHoliday > 0) then
			Print(format("You can get %s %s from holiday event", numFromHoliday, SEAL_LINK));
		end
		if (PlayerOwnsBunker() and not IsQuestFlaggedCompleted(36058)) then
			Print("Don't forget about Bunker/Mill in your garrison!");
		end
		Print("-----------------------------------");
	end
end

local function UpdatePlugin()
	if (LDBPlugin ~= nil) then
		local numObtainable = GetNumObtainableSeals();
		local numFromQuests, numFromHoliday = GetNumAvailableSeals();
		if (numObtainable == 0) then
			LDBPlugin.text = nil;
			LDBPlugin.icon = SEAL_TEXTURE_BW;
		else
			if (numFromHoliday > 0) then
				LDBPlugin.text = format("Seals: %s|cff228b22+%s|r", numFromQuests, numFromHoliday);
			else
				LDBPlugin.text = format("Seals: %s", numFromQuests);
			end
			LDBPlugin.icon = SEAL_TEXTURE;
		end
		LDBPlugin.OnTooltipShow = function(tooltip)
			tooltip:AddLine("Raid Currency Reminder");
			tooltip:AddLine(" ");
			if (numFromQuests > 0) then
				tooltip:AddLine(format("You can buy %s %s in Ashran", numFromQuests, SEAL_LINK));
			end
			if (numFromHoliday > 0) then
				tooltip:AddLine(format("You can get %s %s from holiday event", numFromHoliday, SEAL_LINK));
			end
			if ((numFromHoliday + numFromQuests) == 0) then
				tooltip:AddLine("You have already got all possible "..SEAL_LINK);
			end
			tooltip:AddLine(" ");
			tooltip:AddLine("|cffeda55fLeftClick:|r open currencies tab");
			if (DisablePrintUntilReload) then
				tooltip:AddLine(ColorizeText("Chat notifications are disabled for this game session", 1, 0, 0));
			else
				tooltip:AddLine("|cffeda55fRightClick:|r disable chat notifications for this session");
			end
		end;
	end
end

local function LOADING_SCREEN_DISABLED()
	UpdatePlugin();
	if (GetTime() - LastTimePrint > MIN_INTERVAL_BETWEEN_PRINTS and GetNumObtainableSeals() > 0) then
		C_Timer.After(3, function()
			PrintInfo();
		end);
		LastTimePrint = GetTime();
	end
	if (not CalendarOpened) then
		C_Timer.After(1.0, function()
			GameTimeFrame_OnClick(GameTimeFrame);
			GameTimeFrame_OnClick(GameTimeFrame);
		end);
		CalendarOpened = true;
	end
end

local function eFrame_OnElapsed()
	local obtainableSeals = GetNumObtainableSeals();
	if (LastAvailableSealsAmount ~= obtainableSeals) then
		UpdatePlugin();
		LastAvailableSealsAmount = obtainableSeals;
	end
end

local eFrame = CreateFrame("frame");
eFrame.elapsed = 0;
eFrame:RegisterEvent("LOADING_SCREEN_DISABLED");
eFrame:SetScript("OnEvent", function(this, event, ...)
	if (event == "LOADING_SCREEN_DISABLED") then
		LOADING_SCREEN_DISABLED();
	end
end);
eFrame:SetScript("OnUpdate", function(this, elapsed)		-- // -------------------------------------------------------------------------------------------------------------------------
	this.elapsed = this.elapsed + elapsed;					-- // -------------------------------------------------------------------------------------------------------------------------
	if (this.elapsed >= 1.0) then							-- // CURRENCY_DISPLAY_UPDATE, QUEST_TURNED_IN don't work. IsQuestFlaggedCompleted returns irrelevant info during this events.
		eFrame_OnElapsed();									-- // So I'm using timer to solve it.
		this.elapsed = 0;									-- // -------------------------------------------------------------------------------------------------------------------------
	end														-- // -------------------------------------------------------------------------------------------------------------------------
end);														-- // -------------------------------------------------------------------------------------------------------------------------

local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true);
if (ldb ~= nil) then
	LDBPlugin = ldb:NewDataObject("Raid Currency Reminder",
		{
			type = "data source",
			text = "N/A",
			icon = SEAL_TEXTURE,
			tocname = "RaidCurrencyReminder",
		}
	);
	LDBPlugin.OnClick = function(display, button)
		if (button == "RightButton" and not DisablePrintUntilReload) then
			DisablePrintUntilReload = true;
			Print("Chat notifications are disabled for this game session");
		end
		if (button == "LeftButton") then
			ToggleCharacter("TokenFrame");
		end
	end
end

local function OnTimerElapsed()
	if (GetTime() - LastTimePrint > MIN_INTERVAL_BETWEEN_PRINTS and GetNumObtainableSeals() > 0) then
		PrintInfo();
		LastTimePrint = GetTime();
	end
	C_Timer.After(INTERVAL_BETWEEN_PERIODIC_NOTIFICATIONS, OnTimerElapsed);
end

C_Timer.After(INTERVAL_BETWEEN_PERIODIC_NOTIFICATIONS, OnTimerElapsed);
