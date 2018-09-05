﻿--[===[@non-debug@
local buildTimestamp = "@project-version@";
--@end-non-debug@]===]

---------------------
----- Constants -----
---------------------
local SEAL_CURRENCY_ID = 1580;
local MAX_SEALS_FROM_QUESTS = 2;
local MAX_SEALS_PER_CHARACTER = 5;
local MIN_CHARACTER_LEVEL_REQUIRED = 120;
local SEAL_TEXTURE = [[Interface\Icons\timelesscoin_yellow]];
local SEAL_TEXTURE_BW = [[Interface\AddOns\RaidCurrencyReminder\media\timelesscoin_yellow_bw.tga]];
local SEAL_LINK = GetCurrencyLink(SEAL_CURRENCY_ID, 0);
local INTERVAL_BETWEEN_PERIODIC_CHAT_NOTIFICATIONS = 900;
local MIN_INTERVAL_BETWEEN_PRINTS = 30;
---------------------
---------------------

local LDBPlugin;
local LastAvailableSealsAmount = -1;
local CalendarOpened = false;
local LastTimePrint = 0;
local db;
local GotNewSeal = false;

RaidCurrencyReminderDB = RaidCurrencyReminderDB or { };
local LocalPlayerFullName = UnitName("player").." - "..GetRealmName();
local INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS = 3600;
local LastTimerPopupDisplayed;

local quests = {
	52834, -- // 2000 gold
	52838, -- // 5000 gold
	52837, -- // 250 war resources
	52840, -- // 500 war resources
	52835, -- // 10 Marks of Honor
	52839, -- // 25 Marks of Honor
};

local holidayEvents = {
	[1129686] = 44166,	-- // LK
	[1304687] =	44167,	-- // Cata
	[1304688] = 44167,	-- // Cata
	[1530589] = 45799,	-- // MoP
	[1530590] = 45799,	-- // MoP
	[1129673] = 44164,	-- // BC
	[1129674] = 44164,	-- // BC
};

---------------------
------- Utils -------
---------------------

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

local function CompareDates(hourA, minuteA, hourB, minuteB)
	if (hourA < hourB) then
		return true;
	elseif (hourA == hourB and minuteA < minuteB) then
		return true;
	else
		return false;
	end
end

local function DaysFromCivil(y, m, d)
	if (m <= 2) then
		y = y - 1;
		m = m + 9;
    else
		m = m - 3;
    end
    local era = math.floor(y/400);
    local yoe = y - era * 400;     		                                   	-- [0, 399]
    local doy = math.modf((153*m + 2)/5) + d-1;              		     	-- [0, 365]
    local doe = yoe * 365 + math.modf(yoe/4) - math.modf(yoe/100) + doy;	-- [0, 146096]
    return era * 146097 + doe - 719468;
end

local function SafeCall(func)
	local frame;
	if (_G["OOC_SecureCall"] == nil) then
		_G["OOC_SecureCall"] = CreateFrame("frame");
		frame = _G["OOC_SecureCall"];
		frame.deferredCalls = { };
		frame:RegisterEvent("PLAYER_REGEN_ENABLED");
		frame:SetScript("OnEvent", function(self, event)
			for _, call in pairs(self.deferredCalls) do
				call();
			end
		end);
	end
	frame = frame or _G["OOC_SecureCall"];
	if (InCombatLockdown()) then
		tinsert(frame.deferredCalls, func);
	else
		func();
	end
end

---------------------
---------------------

local function ShouldDeductOneSeal()
	local date = C_Calendar.GetDate();
	local daysFromCivil = DaysFromCivil(date.year, date.month, date.monthDay);
	if (daysFromCivil - db.LastDateAskedAboutClassOrderHall > 5) then
		return false;
	else
		return true;
	end
end

local function GetNumAvailableSeals()
	local numQuestsAvailable;
	if (ShouldDeductOneSeal()) then
		numQuestsAvailable = MAX_SEALS_FROM_QUESTS - 1;
	else
		numQuestsAvailable = MAX_SEALS_FROM_QUESTS;
	end
	for _, questID in pairs(quests) do
		if (IsQuestFlaggedCompleted(questID)) then
			numQuestsAvailable = numQuestsAvailable - 1;
		end
	end
	if (numQuestsAvailable < 0) then
		-- Print("RCR: MAX_SEALS_FROM_QUESTS has incorrect value!");
		numQuestsAvailable = 0;
	end
	
	local date = C_Calendar.GetDate();
	local cHour, cMinute = GetGameTime();
	for eventIndex = 1, C_Calendar.GetNumDayEvents(0, date.monthDay) do
		local _, eventHour, eventMinute, calendarType, sequenceType, _, texture = C_Calendar.GetDayEvent(0, date.monthDay, eventIndex);
		if (calendarType == "HOLIDAY") then
			local questID = holidayEvents[texture];
			if (questID ~= nil) then
				if ((sequenceType == "END" and CompareDates(cHour, cMinute, eventHour, eventMinute)) or (sequenceType == "START" and CompareDates(eventHour, eventMinute, cHour, cMinute)) or (sequenceType == "ONGOING" or sequenceType == "INFO")) then
					if (not IsQuestFlaggedCompleted(questID)) then
						return numQuestsAvailable, 1;
					end
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
			local _, amount = GetCurrencyInfo(SEAL_CURRENCY_ID);
			tooltip:AddLine(format("You have %d %s", amount, SEAL_LINK));
			if (numObtainable == 0) then
				if ((numFromHoliday + numFromQuests) == 0) then
					tooltip:AddLine("You have already got all possible "..SEAL_LINK);
				else
					if (amount == MAX_SEALS_PER_CHARACTER) then
						tooltip:AddLine(format("You can't obtain more %s because you have reached the cap (%s)", SEAL_LINK, MAX_SEALS_PER_CHARACTER));
					else
						tooltip:AddLine(format("You can't obtain more %s because you have not reached %s level", SEAL_LINK, MIN_CHARACTER_LEVEL_REQUIRED));
					end
				end
			else
				if (numFromQuests > 0) then
					tooltip:AddLine(format("You can buy %s %s", numFromQuests, SEAL_LINK));
				end
				if (numFromHoliday > 0) then
					tooltip:AddLine(format("You can get %s %s from holiday event", numFromHoliday, SEAL_LINK));
				end
			end
			tooltip:AddLine(" ");
			tooltip:AddLine("|cffeda55fLeftClick:|r open currencies tab");
		end;
	end
end

local function GetNumQuestsCompleted()
	local num = 0;
	for _, questID in pairs(quests) do
		if (IsQuestFlaggedCompleted(questID)) then
			num = num + 1;
		end
	end
	return num;
end

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
		if (button == "LeftButton") then
			ToggleCharacter("TokenFrame");
		end
	end
end

local function msg(text)
	local frameName = "RCR_StaticPopup";
	if (not StaticPopupDialogs[frameName]) then
		StaticPopupDialogs[frameName] = {
			text = frameName,
			button1 = OKAY,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		};
	end
	StaticPopupDialogs[frameName].text = text;
	StaticPopup_Show(frameName);
end

local function msgWithQuestion(text, funcOnAccept, funcOnCancel)
  local frameName = "RaidCurrencyReminder-newFrame-question";
  if (StaticPopupDialogs[frameName] == nil) then
    StaticPopupDialogs[frameName] = {
      button1 = "Yes",
	  button2 = "No",
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    };
  end
  StaticPopupDialogs[frameName].text = text;
  StaticPopupDialogs[frameName].OnAccept = funcOnAccept;
  StaticPopupDialogs[frameName].OnCancel = funcOnCancel;
  StaticPopup_Show(frameName);
end

local function InitializeDB()
	local defaults = {
		LastDateAskedAboutClassOrderHall = 0,
		LastTimeChecked = 0,
		LastDateChecked = 0,
		QuestsCompleted = 0,
	};
	if (RaidCurrencyReminderDB[LocalPlayerFullName] == nil) then
		RaidCurrencyReminderDB[LocalPlayerFullName] = { };
	end
	for key, value in pairs(defaults) do
		if (RaidCurrencyReminderDB[LocalPlayerFullName][key] == nil) then
			RaidCurrencyReminderDB[LocalPlayerFullName][key] = value;
		end
	end
	db = RaidCurrencyReminderDB[LocalPlayerFullName];
end

local function ShowPopupAboutMissingSeals()
	local numObtainable = GetNumObtainableSeals();
	local numFromQuests, numFromHoliday = GetNumAvailableSeals();
	if (numObtainable > 0) then
		local message = "";
		if (numFromQuests == 1 and not ShouldDeductOneSeal()) then
			msgWithQuestion(format(
				"You can get 1 %s\n\n" ..
				"Unfortunately, RCR can't determine if you got seal in your class order hall. If you haven't corresponding class order hall advancement, you can get seal from Archmage Lan'dalock in Dalaran\n\n" ..
				"Have you got seal from work order this week?", SEAL_LINK),
				function()
					local date = C_Calendar.GetDate();
					db.LastDateAskedAboutClassOrderHall = DaysFromCivil(date.year, date.month, date.monthDay);
					UpdatePlugin();
				end,
				function() end);
		elseif (numFromQuests >= 1) then
			message = message .. format("You can get %s %s from Archmage Lan'dalock in Dalaran\n", numFromQuests, SEAL_LINK);
		end
		if (numFromHoliday > 0) then
			message = message .. format("You can get one %s from weekly event", SEAL_LINK);
		end
		if (message ~= "") then
			msg(message);
		end
		db.LastTimeChecked = GetTime();
		local date = C_Calendar.GetDate();
		db.LastDateChecked = tostring(date.year) .. tostring(date.month) .. tostring(date.monthDay);
	end
end

local function ShowPopupAboutUnknownSeal()
	local numObtainable = GetNumObtainableSeals();
	local numFromQuests, numFromHoliday = GetNumAvailableSeals();
	if (numFromQuests > 0 and not ShouldDeductOneSeal()) then -- numObtainable > 0 and 
		msgWithQuestion(format(
			"You have just got %s from unknown source\n\n" ..
			"Unfortunately, RCR can't determine if you got seal in your class order hall. If you haven't corresponding class order hall advancement, you can get seal from Archmage Lan'dalock in Dalaran\n\n" ..
			"Have you got seal from work order?", SEAL_LINK),
			function()
				local date = C_Calendar.GetDate();
				db.LastDateAskedAboutClassOrderHall = DaysFromCivil(date.year, date.month, date.monthDay);
				UpdatePlugin();
			end,
			function() end);
	end
end

local function CheckInfo()
	local numQuestsCompleted = GetNumQuestsCompleted();
	local obtainableSeals = GetNumObtainableSeals();
	if (numQuestsCompleted < db.QuestsCompleted) then -- // seems like it's next raid week now
		db.LastDateAskedAboutClassOrderHall = 0;
		db.QuestsCompleted = numQuestsCompleted;
		UpdatePlugin();
	end
	if (obtainableSeals > 0) then
		if (GetTime() - LastTimerPopupDisplayed > INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS) then
			if (IsResting()) then
				ShowPopupAboutMissingSeals();
				LastTimerPopupDisplayed = GetTime();
			end
		end
	end
	UpdatePlugin();
	--print(format("1: Quests completed: %s; DB quest completed: %s; ObtainableSeals: %s; GetNumAvailableSeals: %s; ShouldDeductOneSeal: %s", numQuestsCompleted, db.QuestsCompleted, obtainableSeals, GetNumAvailableSeals(), tostring(ShouldDeductOneSeal())));
	C_Timer.After(1.0, CheckInfo);
end

local function OnNewSealReceived()
	local numQuestsCompleted = GetNumQuestsCompleted();
	if (db.QuestsCompleted ~= numQuestsCompleted) then
		-- // we have completed quest in Dalaran
		UpdatePlugin();
	else
		-- // seems like we got seal from work order or mission
		ShowPopupAboutUnknownSeal();
	end
	--print(format("2: Quests completed: %s; DB quest completed: %s; GetNumAvailableSeals: %s; ShouldDeductOneSeal: %s", numQuestsCompleted, db.QuestsCompleted, GetNumAvailableSeals(), tostring(ShouldDeductOneSeal())));
	db.QuestsCompleted = numQuestsCompleted;
end

-- // todo: delete-start
function y123()
	local numQuestsCompleted = GetNumQuestsCompleted();
	local obtainableSeals = GetNumObtainableSeals();
	print(format("1: Quests completed: %s;\nDB quest completed: %s;\nObtainableSeals: %s;\nGetNumAvailableSeals: %s;\nShouldDeductOneSeal: %s", numQuestsCompleted, db.QuestsCompleted, obtainableSeals, GetNumAvailableSeals(), tostring(ShouldDeductOneSeal())));
end
-- // todo: delete-end

local newFrame = CreateFrame("frame");
newFrame:RegisterEvent("LOADING_SCREEN_DISABLED");
newFrame:SetScript("OnEvent", function(self, event, ...)
	if (event == "LOADING_SCREEN_DISABLED") then
		InitializeDB();
		self:UnregisterEvent("LOADING_SCREEN_DISABLED");
		self:RegisterEvent("CHAT_MSG_CURRENCY");
		UpdatePlugin();
		if (not CalendarOpened) then
			SafeCall(function()
				C_Timer.After(1.0, function()
					GameTimeFrame_OnClick(GameTimeFrame);
					GameTimeFrame_OnClick(GameTimeFrame);
				end);
				CalendarOpened = true;
			end);
		end
		local date = C_Calendar.GetDate();
		local currentDate = tostring(date.year) .. tostring(date.month) .. tostring(date.monthDay);
		if (currentDate ~= db.LastDateChecked) then
			LastTimerPopupDisplayed = -INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS;
		else
			LastTimerPopupDisplayed = db.LastTimeChecked;
		end
		C_Timer.After(1.0, function()
			UpdatePlugin();
			CheckInfo();
		end);
	elseif (event == "CHAT_MSG_CURRENCY") then
		local msg = ...;
		if (msg:find(SEAL_LINK, 1, true)) then
			C_Timer.After(1.0, OnNewSealReceived);
		end
	end
end);
