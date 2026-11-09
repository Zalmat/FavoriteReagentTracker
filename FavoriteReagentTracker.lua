local FavoriteReagentTracker = CreateFrame("Frame")
FavoriteReagentTracker:RegisterEvent("ADDON_LOADED")
FavoriteReagentTracker:RegisterEvent("TRADE_SKILL_SHOW")

local function ScanRecipes()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeInfo then return end
    
    local professionInfo = C_TradeSkillUI.GetBaseProfessionInfo()
    local professionName = professionInfo and professionInfo.professionName
    
    if not professionName or professionName == "" then return end
    
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    
    -- Собираем список избранных рецептов для текущей профессии
    local currentFavorites = {}
    local currentFavoriteNames = {}
    
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned and recipeInfo.favorite then
            table.insert(currentFavorites, recipeID)
            table.insert(currentFavoriteNames, recipeInfo.name)
        end
    end
    
    -- Если избранного нет, очищаем профессию и выходим
    if #currentFavorites == 0 then
        FavoriteReagentTrackerDB.ingredients[professionName] = {}
        return
    end
    
    -- ЗАЩИТА ОТ ГЛЮКОВ ИГРЫ (ДУБЛЕЙ)
    for pName, pTable in pairs(FavoriteReagentTrackerDB.ingredients) do
        if pName ~= professionName then
            local matchCount = 0
            for _, savedRecipeName in ipairs(currentFavoriteNames) do
                local foundInOther = false
                for _, rList in pairs(pTable) do
                    if type(rList) == "table" then
                        for _, savedName in ipairs(rList) do
                            if savedName == savedRecipeName then
                                foundInOther = true
                                break
                            end
                        end
                    end
                    if foundInOther then break end
                end
                if foundInOther then matchCount = matchCount + 1 end
            end
            
            -- Если ВСЕ избранные рецепты уже есть в другой профессии - это глюк
            if matchCount == #currentFavoriteNames then
                return
            end
        end
    end
    
    -- Сканируем реагенты
    FavoriteReagentTrackerDB.ingredients[professionName] = {}
    local professionIngredients = FavoriteReagentTrackerDB.ingredients[professionName]
    local foundReagents = 0
    
    for _, recipeID in ipairs(currentFavorites) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        
        if schematic and schematic.reagentSlotSchematics then
            for _, slot in ipairs(schematic.reagentSlotSchematics) do
                for _, reagent in ipairs(slot.reagents) do
                    local itemName = C_Item.GetItemNameByID(reagent.itemID)
                    if itemName then
                        if not professionIngredients[itemName] then
                            professionIngredients[itemName] = {}
                        end
                        table.insert(professionIngredients[itemName], recipeInfo.name)
                        foundReagents = foundReagents + 1
                    end
                end
            end
        end
    end
    
    -- Вывод статистики (только если включена настройка)
    if foundReagents > 0 and FavoriteReagentTrackerDB.showMessages then
        local totalReagents = 0
        local allUniqueRecipes = {}
        for pName, pTable in pairs(FavoriteReagentTrackerDB.ingredients) do
            for _, rList in pairs(pTable) do
                if type(rList) == "table" then
                    totalReagents = totalReagents + 1
                    for _, rName in ipairs(rList) do
                        allUniqueRecipes[rName] = true
                    end
                end
            end
        end
        local totalRecipeCount = 0
        for _ in pairs(allUniqueRecipes) do totalRecipeCount = totalRecipeCount + 1 end
        
        print("|cFF00FF00FavoriteReagentTracker:|r Профессия |cFFFFFF00" .. professionName .. "|r обновлена.")
        print("  - Для неё найдено: " .. foundReagents .. " реагентов для " .. #currentFavorites .. " рецептов.")
        print("  - |cFFAAAAAAВсего в базе:|r " .. totalReagents .. " реагентов для " .. totalRecipeCount .. " рецептов.")
    end
end

FavoriteReagentTracker:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "FavoriteReagentTracker" then
            FavoriteReagentTrackerDB = FavoriteReagentTrackerDB or {}
            FavoriteReagentTrackerDB.ingredients = FavoriteReagentTrackerDB.ingredients or {}
            
            -- Включаем сообщения по умолчанию
            if FavoriteReagentTrackerDB.showMessages == nil then
                FavoriteReagentTrackerDB.showMessages = true
            end
            
            if FavoriteReagentTrackerDB.showMessages then
                print("|cFF00FF00FavoriteReagentTracker загружен!|r")
            end
        end
    elseif event == "TRADE_SKILL_SHOW" then
        -- Задержка 0.5 сек от глюков быстрого переключения
        C_Timer.After(0.5, function()
            local ok, err = pcall(ScanRecipes)
            if not ok and FavoriteReagentTrackerDB.showMessages then
                print("|cFFFF0000FavoriteReagentTracker: ошибка сканирования:|r " .. tostring(err))
            end
        end)
    end
end)

local function OnTooltipSetItem(tooltip)
    local name = tooltip:GetItem()
    if not name then return end
    if not FavoriteReagentTrackerDB or not FavoriteReagentTrackerDB.ingredients then return end
    
    local found = false
    local addedRecipes = {} -- Локальная таблица для защиты от дублей в тултипе
    local cleanName = name:match("^[^|]+"):trim()
    
    for profName, profTable in pairs(FavoriteReagentTrackerDB.ingredients) do
        local recipesList = profTable[cleanName] or profTable[name]
        
        if type(recipesList) == "table" and #recipesList > 0 then
            if not found then
                tooltip:AddLine(" ")
                tooltip:AddLine("• |cFF00FF00Нужен для Избранных рецептов:|r")
                found = true
            end
            
            for _, recipeName in ipairs(recipesList) do
                -- Проверяем, не добавили ли мы уже этот рецепт
                if not addedRecipes[recipeName] then
                    tooltip:AddLine("  |cFF888888> " .. recipeName .. " (" .. profName .. ")|r")
                    addedRecipes[recipeName] = true
                end
            end
        end
    end
end

-- Подключаем тултип с защитой (ТОЛЬКО ОДИН РАЗ!)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        -- Защита от изменения тултипов в запрещенных зонах
        if tooltip:IsForbidden() then return end
        OnTooltipSetItem(tooltip)
    end)
else
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
end



-- Слэш-команда для управления настройками
SLASH_FAVORITEREAGENTTRACKER1 = "/frt"
SlashCmdList["FAVORITEREAGENTTRACKER"] = function(msg)
    local cmd = msg:lower():trim()
    
    if cmd == "on" then
        FavoriteReagentTrackerDB.showMessages = true
        print("|cFF00FF00FavoriteReagentTracker:|r Сообщения в чат |cFF00FF00ВКЛЮЧЕНЫ|r.")
    elseif cmd == "off" then
        FavoriteReagentTrackerDB.showMessages = false
        print("|cFF00FF00FavoriteReagentTracker:|r Сообщения в чат |cFFFF0000ВЫКЛЮЧЕНЫ|r.")
    else
        -- Если ввели просто /frt или неизвестную команду, показываем статус и справку
        local status = FavoriteReagentTrackerDB.showMessages and "|cFF00FF00ВКЛЮЧЕНЫ|r" or "|cFFFF0000ВЫКЛЮЧЕНЫ|r"
        print("|cFF00FF00FavoriteReagentTracker|r (v1.0)")
        print("Текущий статус сообщений: " .. status)
        print("Используйте:")
        print("  |cFFFFFF00/frt on|r  - Включить сообщения")
        print("  |cFFFFFF00/frt off|r - Выключить сообщения")
    end
end