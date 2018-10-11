--[===[@non-debug@
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
local INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS = 3600;
---------------------
---------------------

local LDBPlugin;
local LastAvailableSealsAmount = -1;
local CalendarOpened = false;
local LastTimePrint = 0;
local db;
local GotNewSeal = false;
local TimerNotifications;

RaidCurrencyReminderDB = RaidCurrencyReminderDB or { };
local LocalPlayerFullName = UnitName("player").." - "..GetRealmName();

local LastTimerPopupDisplayed;

local C_Timer_After = C_Timer.After;

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

local function GetNumAvailableSeals()
	local numQuestsAvailable = MAX_SEALS_FROM_QUESTS;
	for _, questID in pairs(quests) do
		if (IsQuestFlaggedCompleted(questID)) then
			numQuestsAvailable = numQuestsAvailable - 1;
		end
	end
	if (numQuestsAvailable < 0) then
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
	-- // remove obsolete entries
	for _, key in pairs({ "LastDateAskedAboutClassOrderHall" }) do
		RaidCurrencyReminderDB[LocalPlayerFullName][key] = nil;
	end
	db = RaidCurrencyReminderDB[LocalPlayerFullName];
end

local function ShowPopupAboutMissingSeals()
	local numObtainable = GetNumObtainableSeals();
	local numFromQuests, numFromHoliday = GetNumAvailableSeals();
	if (numObtainable > 0) then
		local message = "";
		if (numFromQuests > 0) then
			message = message .. format("You can get %s %s from your faction vendor\n", numFromQuests, SEAL_LINK);
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

local function CheckInfo()
	local numQuestsCompleted = GetNumQuestsCompleted();
	local obtainableSeals = GetNumObtainableSeals();
	if (numQuestsCompleted < db.QuestsCompleted) then -- // seems like it's next raid week now
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
end

local function StartTimerNotifications()
	local date = C_Calendar.GetDate();
	local currentDate = tostring(date.year) .. tostring(date.month) .. tostring(date.monthDay);
	if (currentDate ~= db.LastDateChecked) then
		LastTimerPopupDisplayed = -INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS;
	else
		LastTimerPopupDisplayed = db.LastTimeChecked;
	end
	TimerNotifications = C_Timer.NewTicker(INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS, CheckInfo);
end

-- // frame for events
do
	
	local eFrame = CreateFrame("frame");
	eFrame:SetScript("OnEvent", function(self, event, ...) self[event](...); end);
	eFrame:RegisterEvent("LOADING_SCREEN_DISABLED");
	
	eFrame.LOADING_SCREEN_DISABLED = function()
		eFrame:UnregisterEvent("LOADING_SCREEN_DISABLED");
		InitializeDB();
		eFrame:RegisterEvent("CHAT_MSG_CURRENCY");
		eFrame:RegisterEvent("BONUS_ROLL_RESULT");
		if (not CalendarOpened) then
			SafeCall(function()
				C_Timer_After(1.0, function()
					GameTimeFrame_OnClick(GameTimeFrame);
					GameTimeFrame_OnClick(GameTimeFrame);
				end);
				CalendarOpened = true;
			end);
		end
		StartTimerNotifications(); -- // call it before 'CheckInfo' on startup
		C_Timer_After(1.0, CheckInfo);
	end
	
	local function OnNewSealReceived()
		local numQuestsCompleted = GetNumQuestsCompleted();
		if (db.QuestsCompleted ~= numQuestsCompleted) then
			-- // we have completed quest in Dalaran
			UpdatePlugin();
		else
			-- // seems like we got seal from work order or mission
		end
		db.QuestsCompleted = numQuestsCompleted;
	end
	
	eFrame.CHAT_MSG_CURRENCY = function(message)
		if (message:find(SEAL_LINK, 1, true)) then
			C_Timer_After(1.0, OnNewSealReceived);
		end
	end
	
	eFrame.BONUS_ROLL_RESULT = CheckInfo; -- [11:33:09] BONUS_ROLL_RESULT item [Исторгнутый пламенный посох очистителя] 1 264 2 false nil
	
end
