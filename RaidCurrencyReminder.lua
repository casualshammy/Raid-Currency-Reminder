---------------------
----- Constants -----
---------------------
local sealCurrencyID = 1129;
local maxSealsFromQuests = 3;
local sealTexture = [[Interface\Icons\achievement_battleground_templeofkotmogu_02_green]];
local intervalBetweenPeriodicNotifications = 900;
---------------------

local LDBPlugin;

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
};

local function Print(...)
	local text = "";
	for i = 1, select("#", ...) do
		text = text..tostring(select(i, ...)).." "
	end
	DEFAULT_CHAT_FRAME:AddMessage(format("%s", text), 1, 0.5, 0);
end

local function ReportToUser(sealsAvailable)
	if (LDBPlugin ~= nil) then
		if (sealsAvailable == 0) then
			LDBPlugin.text = nil;
			LDBPlugin.OnTooltipShow = function(tooltip)
				tooltip:AddLine("Raid Currency Reminder");
				tooltip:AddLine(" ");
				tooltip:AddLine("You have already obtained all possible "..GetCurrencyLink(sealCurrencyID));
			end;
		else
			LDBPlugin.text = "You can obtain "..tostring(sealsAvailable).." "..GetCurrencyLink(sealCurrencyID);
			LDBPlugin.OnTooltipShow = function(tooltip)
				tooltip:AddLine("Raid Currency Reminder");
				tooltip:AddLine(" ");
				tooltip:AddLine("You can obtain "..tostring(sealsAvailable).." "..GetCurrencyLink(sealCurrencyID));
			end;
		end
	else
		
	end
	if (sealsAvailable > 0) then
		C_Timer.After(2, function()
			Print("-----------------------------------");
			Print("You can obtain "..tostring(sealsAvailable).." "..GetCurrencyLink(sealCurrencyID));
			Print("-----------------------------------");
		end);
	end
end

local function OnQuestStateChanged()
	local counter = maxSealsFromQuests;
	for _, questID in pairs(quests) do
		if (IsQuestFlaggedCompleted(questID)) then
			counter = counter - 1;
		end
	end
	ReportToUser(counter);
end

local eFrame = CreateFrame("frame");
eFrame:RegisterEvent("QUEST_TURNED_IN");
eFrame:RegisterEvent("LOADING_SCREEN_DISABLED");
eFrame:SetScript("OnEvent", function(this, event, ...)
	if (event == "QUEST_TURNED_IN") then
		local questID = ...;
		if (tContains(quests, questID)) then
			C_Timer.After(1, OnQuestStateChanged); -- // because it lags
		end
	elseif (event == "LOADING_SCREEN_DISABLED") then
		C_Timer.After(3, OnQuestStateChanged);
	end
end);

local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true);
if (ldb ~= nil) then
	LDBPlugin = ldb:NewDataObject("RCR_LDB",
		{
			type = "data source",
			text = "Test",
			icon = sealTexture,
			tocname = "RaidCurrencyReminder",
		}
	);
end

local function OnTimerElapsed()
	OnQuestStateChanged();
	C_Timer.After(intervalBetweenPeriodicNotifications, OnTimerElapsed);
end

C_Timer.After(intervalBetweenPeriodicNotifications, OnTimerElapsed);