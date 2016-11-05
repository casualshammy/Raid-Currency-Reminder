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

local ShouldDeductOneSeal;

local LDBPlugin;
local LastAvailableSealsAmount = -1;
local CalendarOpened = false;
local LastTimePrint = 0;
local DisablePrintUntilReload = false;
local db;

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
	-- ["calendar_weekendwrathofthelichking"] = 39021,
	-- ["calendar_weekendcataclysm"] = 		 40792,
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

local function CompareDates(hourA, minuteA, hourB, minuteB)
	if (hourA < hourB) then
		return true;
	elseif (hourA == hourB and minuteA < minuteB) then
		return true;
	else
		return false;
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
		Print("RCR: MAX_SEALS_FROM_QUESTS has incorrect value!");
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
				tooltip:AddLine(format("You can buy %s %s in Dalaran", numFromQuests, SEAL_LINK));
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
			-- PrintInfo();
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

local function GetNumQuestsCompleted()
	local num = 0;
	for _, questID in pairs(quests) do
		if (IsQuestFlaggedCompleted(questID)) then
			num = num + 1;
		end
	end
	return num;
end

local function eFrame_OnElapsed()
	local obtainableSeals = GetNumObtainableSeals();
	if (LastAvailableSealsAmount ~= obtainableSeals) then
		UpdatePlugin();
		LastAvailableSealsAmount = obtainableSeals;
	end
	
	local numQuestsCompleted = GetNumQuestsCompleted();
	if (numQuestsCompleted < db.QuestsCompleted) then -- // seems like it's next raid week now
		db.LastDateAskedAboutClassOrderHall = 0;
	end
	db.QuestsCompleted = numQuestsCompleted;
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
		-- PrintInfo();
		LastTimePrint = GetTime();
	end
	C_Timer.After(INTERVAL_BETWEEN_PERIODIC_CHAT_NOTIFICATIONS, OnTimerElapsed);
end

C_Timer.After(INTERVAL_BETWEEN_PERIODIC_CHAT_NOTIFICATIONS, OnTimerElapsed);



RaidCurrencyReminderDB = RaidCurrencyReminderDB or { };
local LocalPlayerFullName = UnitName("player").." - "..GetRealmName();

local INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS = 3600;

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

local function msg(text)
  local frameName = "RaidCurrencyReminder-newFrame";
  if (StaticPopupDialogs[frameName] == nil) then
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

function ShouldDeductOneSeal()
	local _, month, day, year = CalendarGetDate();
	local daysFromCivil = DaysFromCivil(year, month, day);
	if (daysFromCivil - db.LastDateAskedAboutClassOrderHall > 5) then
		return false;
	else
		return true;
	end
end

local function NewChecker()
	if (IsResting()) then
		local numObtainable = GetNumObtainableSeals();
		local numFromQuests, numFromHoliday = GetNumAvailableSeals();
		if (numObtainable > 0) then
			if (numFromQuests == 1) then
				if (not ShouldDeductOneSeal()) then
					msgWithQuestion(format(
						"You can still get 1 %s\n\n" ..
						"Unfortunately, RCR can't determine if you got seal in your class order hall. If you haven't corresponding class order hall advancement, you can get seal from Archmage Lan'dalock in Dalaran\n\n" ..
						"Have you got seal from work order this week?", SEAL_LINK),
						function()
							local _, month, day, year = CalendarGetDate();
							db.LastDateAskedAboutClassOrderHall = DaysFromCivil(year, month, day);
						end,
						function() end);
				end
			elseif (numFromQuests > 1) then
				msg(format("You can still get %s %s from Archmage Lan'dalock in Dalaran", numFromQuests, SEAL_LINK));
			end
			if (numFromHoliday > 0) then
				msg(format("You can still get one %s from weekly event\nVisit Archmage Timear in Dalaran to start quest", SEAL_LINK));
			end
			db.LastTimeChecked = GetTime();
			local _, month, day, year = CalendarGetDate();
			db.LastDateChecked = tostring(year) .. tostring(month) .. tostring(day);
		end
		C_Timer.After(INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS, NewChecker);
	else
		C_Timer.After(15, NewChecker);
	end
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

local newFrame = CreateFrame("frame");
newFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
newFrame:SetScript("OnEvent", function(self, event, ...)
	InitializeDB();
	local _, month, day, year = CalendarGetDate();
	local currentDate = tostring(year) .. tostring(month) .. tostring(day);
	if (currentDate ~= db.LastDateChecked) then
		C_Timer.After(10, NewChecker);
	else
		if (GetTime() - db.LastTimeChecked > INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS) then
			C_Timer.After(10, NewChecker);
		else
			C_Timer.After(INTERVAL_BETWEEN_PERIODIC_POPUP_NOTIFICATIONS - GetTime() + db.LastTimeChecked, NewChecker);
		end
	end
	self:UnregisterEvent("PLAYER_ENTERING_WORLD");
end);
