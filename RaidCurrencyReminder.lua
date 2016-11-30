---------------------
----- Constants -----
---------------------
local SEAL_CURRENCY_ID = 1273;
local MAX_SEALS_FROM_QUESTS = 3;
local MAX_SEALS_PER_CHARACTER = 6;
local MIN_CHARACTER_LEVEL_REQUIRED = 110;
local SEAL_TEXTURE = [[Interface\Icons\inv_misc_elvencoins]];
local SEAL_TEXTURE_BW = [[Interface\AddOns\RaidCurrencyReminder\media\inv_misc_elvencoins_bw.tga]];
local SEAL_LINK = GetCurrencyLink(SEAL_CURRENCY_ID);
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
	43892,	-- // 1000 class hall
	43893,	-- // 2000 class hall
	43894,	-- // 4000 class hall
	43895,	-- // 1000 gold
	43896,	-- // 2000 gold
	43897,	-- // 4000 gold
};

local holidayEvents = {
	["calendar_weekendburningcrusade"] = 	 44164,
	["calendar_weekendwrathofthelichking"] = 44166,
	["calendar_weekendcataclysm"] = 		 44167,
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

---------------------
---------------------

local function ShouldDeductOneSeal()
	local _, month, day, year = CalendarGetDate();
	local daysFromCivil = DaysFromCivil(year, month, day);
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
	
	local _, _, day = CalendarGetDate();
	local cHour, cMinute = GetGameTime();
	for eventIndex = 1, CalendarGetNumDayEvents(0, day) do
		local _, eventHour, eventMinute, calendarType, sequenceType, _, texture = CalendarGetDayEvent(0, day, eventIndex);
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
			if (numObtainable == 0) then
				if ((numFromHoliday + numFromQuests) == 0) then
					tooltip:AddLine("You have already got all possible "..SEAL_LINK);
				else
					local _, amount = GetCurrencyInfo(SEAL_CURRENCY_ID);
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

local c_static_popups_created = { };

local function GetStaticPopup()
  for _, frameName in pairs(c_static_popups_created) do
    if (StaticPopupDialogs[frameName] ~= nil and not StaticPopup_Visible(frameName)) then
      return frameName;
    end
  end
  local frameName = "RaidCurrencyReminder" .. tostring(#c_static_popups_created);
  StaticPopupDialogs[frameName] = {
    text = frameName,
    button1 = OKAY,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3 + #c_static_popups_created,
  };
  c_static_popups_created[#c_static_popups_created + 1] = frameName;
  return frameName;
end

local function msg(text)
  local frameName = GetStaticPopup();
  StaticPopupDialogs[frameName].text = text;
  StaticPopup_Show(frameName);
end

local function msgWithQuestion(text, funcOnAccept, funcOnCancel)
  local frameName = "RaidCurrencyReminder-newFrame-question";
  if (StaticPopupDialogs[frameName] == nil) then
    StaticPopupDialogs[frameName] = {
      text = frameName,
      button1 = "Yes",
	  button2 = "No",
	  OnAccept = funcOnAccept,
	  OnCancel = funcOnCancel,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    };
  end
  StaticPopupDialogs[frameName].text = text;
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
					local _, month, day, year = CalendarGetDate();
					db.LastDateAskedAboutClassOrderHall = DaysFromCivil(year, month, day);
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
		local _, month, day, year = CalendarGetDate();
		db.LastDateChecked = tostring(year) .. tostring(month) .. tostring(day);
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
				local _, month, day, year = CalendarGetDate();
				db.LastDateAskedAboutClassOrderHall = DaysFromCivil(year, month, day);
				UpdatePlugin();
			end,
			function() end);
	end
end

local function CheckInfo()
	local numQuestsCompleted = GetNumQuestsCompleted();
	if (GotNewSeal) then
		GotNewSeal = false;
		if (db.QuestsCompleted ~= numQuestsCompleted) then -- // we have completed quest in Dalaran
			UpdatePlugin();
		else -- // seems like we got seal from work order or mission
			ShowPopupAboutUnknownSeal();
		end
	end
	local obtainableSeals = GetNumObtainableSeals();
	if (LastAvailableSealsAmount ~= obtainableSeals) then
		UpdatePlugin();
		LastAvailableSealsAmount = obtainableSeals;
	end
	if (numQuestsCompleted < db.QuestsCompleted) then -- // seems like it's next raid week now
		db.LastDateAskedAboutClassOrderHall = 0;
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
	--print(format("Quests completed: %s; DB quest completed: %s; ObtainableSeals: %s; GetNumAvailableSeals: %s; ShouldDeductOneSeal: %s", numQuestsCompleted, db.QuestsCompleted, obtainableSeals, GetNumAvailableSeals(), tostring(ShouldDeductOneSeal())));
	db.QuestsCompleted = numQuestsCompleted;
	C_Timer.After(1.0, CheckInfo);
end

local newFrame = CreateFrame("frame");
newFrame:RegisterEvent("LOADING_SCREEN_DISABLED");
newFrame:SetScript("OnEvent", function(self, event, ...)
	if (event == "LOADING_SCREEN_DISABLED") then
		InitializeDB();
		self:UnregisterEvent("LOADING_SCREEN_DISABLED");
		self:RegisterEvent("CHAT_MSG_CURRENCY");
		UpdatePlugin();
		if (not CalendarOpened) then
			C_Timer.After(1.0, function()
				GameTimeFrame_OnClick(GameTimeFrame);
				GameTimeFrame_OnClick(GameTimeFrame);
			end);
			CalendarOpened = true;
		end
		local _, month, day, year = CalendarGetDate();
		local currentDate = tostring(year) .. tostring(month) .. tostring(day);
		if (currentDate ~= db.LastDateChecked) then
			LastTimerPopupDisplayed = -INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS;
		else
			LastTimerPopupDisplayed = db.LastTimeChecked;
		end
		C_Timer.After(1.0, CheckInfo);
	elseif (event == "CHAT_MSG_CURRENCY") then
		local msg = ...;
		if (msg:find(SEAL_LINK, 1, true)) then
			C_Timer.After(1.0, function() GotNewSeal = true; end);
		end
	end
end);
