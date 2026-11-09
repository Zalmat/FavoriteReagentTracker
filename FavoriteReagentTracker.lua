local FavoriteReagentTracker = CreateFrame("Frame")
FavoriteReagentTracker:RegisterEvent("ADDON_LOADED")
FavoriteReagentTracker:RegisterEvent("TRADE_SKILL_SHOW")

local function ScanRecipes()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeInfo then return end
    
    -- Определяем текущую профессию
    local professionName = C_TradeSkillUI.GetTradeSkillLine()
    if not professionName or professionName == "" then return end
    
    -- Инициализируем подтаблицу для этой профессии
    FavoriteReagentTrackerDB.ingredients[professionName] = {}
    local professionIngredients = FavoriteReagentTrackerDB.ingredients[professionName]
    
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned and recipeInfo.isFavorite then
            local numSchematics = C_TradeSkillUI.GetRecipeNumReagents(recipeID)
            if numSchematics then
                for i = 1, numSchematics do
                    local name = C_TradeSkillUI.GetRecipeReagentInfo(recipeID, i)
                    if name then
                        professionIngredients[name] = recipeInfo.name
                    end
                end
            end
        end
    end
end

FavoriteReagentTracker:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "FavoriteReagentTracker" then
            FavoriteReagentTrackerDB = FavoriteReagentTrackerDB or {}
            FavoriteReagentTrackerDB.ingredients = FavoriteReagentTrackerDB.ingredients or {}
            
            local total = 0
            for _, profTable in pairs(FavoriteReagentTrackerDB.ingredients) do
                for _ in pairs(profTable) do total = total + 1 end
            end
            print("|cFF00FF00FavoriteReagentTracker загружен!|r Сохранено ингредиентов: " .. total .. ". Откройте профессию для обновления.")
        end
    elseif event == "TRADE_SKILL_SHOW" then
        local ok, err = pcall(ScanRecipes)
        if not ok then
            print("|cFFFF0000FavoriteReagentTracker: ошибка сканирования:|r " .. tostring(err))
        end
    end
end)

local function OnTooltipSetItem(tooltip)
    local name = tooltip:GetItem()
    if not name then return end
    if not FavoriteReagentTrackerDB or not FavoriteReagentTrackerDB.ingredients then return end
    
    local found = false
    
    for professionName, profTable in pairs(FavoriteReagentTrackerDB.ingredients) do
        local recipeName = profTable[name]
        if recipeName then
            if not found then
                tooltip:AddLine("• |cFF00FF00Нужен для Избранного рецепта!|r")
                found = true
            end
            tooltip:AddLine("  |cFF888888> " .. recipeName .. " (" .. professionName .. ")|r")
        end
    end
end

-- Hook both legacy and modern tooltips safely
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
else
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
end