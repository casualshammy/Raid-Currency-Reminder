---------------------
----- Constants -----
---------------------
local sealCurrencyID = 1129;
local maxSealsFromQuests = 3;
local maxSealsPerCharacter = 10;
local sealTexture = [[Interface\Icons\achievement_battleground_templeofkotmogu_02_green]];
local sealTextureBW = [[Interface\AddOns\RaidCurrencyReminder\media\achievement_battleground_templeofkotmogu_02_green_bw.tga]];
local intervalBetweenPeriodicNotifications = 900;
---------------------
---------------------

local LDBPlugin;
local LastAvailableSealsAmount = 0;

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

local function Print(...)
	local text = "";
	for i = 1, select("#", ...) do
		text = text..tostring(select(i, ...)).." "
	end
	DEFAULT_CHAT_FRAME:AddMessage(format("%s", text), 1, 0.5, 0);
end

local function PlayerOwnsBunker()
	local t = C_Garrison.GetPlots();
	if (t ~= nil and #t > 0) then
		for _, value in pairs(t) do
			if (value.size == 3) then
				local buildingID, buildingName, _, _, _, rank = C_Garrison.GetOwnedBuildingInfo(value.id);
				if (buildingID == 10) then
					return true;
				end
			end
		end
	end
	return false;
end

local function PrintInfo(amount)
	Print("-----------------------------------");
	Print("You can buy "..tostring(amount).." "..GetCurrencyLink(sealCurrencyID));
	if (PlayerOwnsBunker() and not IsQuestFlaggedCompleted(36058)) then
		Print("Don't forget about Bunker/Mill in your garrison!");
	end
	Print("-----------------------------------");
end

local function UpdatePlugin(amount)
	if (LDBPlugin ~= nil) then
		if (amount == 0) then
			LDBPlugin.text = nil;
			LDBPlugin.icon = sealTextureBW;
			LDBPlugin.OnTooltipShow = function(tooltip)
				tooltip:AddLine("Raid Currency Reminder");
				tooltip:AddLine(" ");
				tooltip:AddLine("You have already bought all possible "..GetCurrencyLink(sealCurrencyID));
			end;
		else
			LDBPlugin.text = tostring(amount).." "..GetCurrencyLink(sealCurrencyID);
			LDBPlugin.icon = sealTexture;
			LDBPlugin.OnTooltipShow = function(tooltip)
				tooltip:AddLine("Raid Currency Reminder");
				tooltip:AddLine(" ");
				tooltip:AddLine("You can buy "..tostring(amount).." "..GetCurrencyLink(sealCurrencyID));
			end;
		end
	end
end

local function GetAvailableSeals()
	local _, amount = GetCurrencyInfo(sealCurrencyID);
	local possible = min(maxSealsFromQuests, maxSealsPerCharacter - amount);
	local numQuestsAvailable = maxSealsFromQuests;
	for _, questID in pairs(quests) do
		if (IsQuestFlaggedCompleted(questID)) then
			numQuestsAvailable = numQuestsAvailable - 1;
		end
	end
	return min(numQuestsAvailable, possible);
end

local function LOADING_SCREEN_DISABLED()
	local availableSeals = GetAvailableSeals();
	UpdatePlugin(availableSeals);
	if (availableSeals > 0) then
		C_Timer.After(3, function()
			PrintInfo(availableSeals);
		end);
	end
end

local function eFrame_OnElapsed()
	local availableSeals = GetAvailableSeals();
	if (LastAvailableSealsAmount ~= availableSeals) then
		UpdatePlugin(availableSeals);
		LastAvailableSealsAmount = availableSeals;
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
			icon = sealTexture,
			tocname = "RaidCurrencyReminder",
		}
	);
end

local function OnTimerElapsed()
	local availableSeals = GetAvailableSeals();
	if (availableSeals > 0) then
		PrintInfo(availableSeals);
	end
	C_Timer.After(intervalBetweenPeriodicNotifications, OnTimerElapsed);
end

C_Timer.After(intervalBetweenPeriodicNotifications, OnTimerElapsed);