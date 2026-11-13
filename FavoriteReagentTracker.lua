local FavoriteReagentTracker = CreateFrame("Frame")
FavoriteReagentTracker:RegisterEvent("ADDON_LOADED")
FavoriteReagentTracker:RegisterEvent("TRADE_SKILL_SHOW")
FavoriteReagentTracker:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")

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
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        -- Задержка 0.5 сек от глюков быстрого переключения и обновлений от TSM
        C_Timer.After(0.5, function()
            local ok, err = pcall(ScanRecipes)
            if not ok and FavoriteReagentTrackerDB.showMessages then
                print("|cFFFF0000FavoriteReagentTracker: ошибка сканирования:|r " .. tostring(err))
            end
        end)
    end
end)

-- Обработчик тултипа, полностью адаптированный под современный движок WoW Forever и TSM
local function OnTooltipSetItem(tooltip, data)
    if not tooltip or tooltip:IsForbidden() then return end
    if not FavoriteReagentTrackerDB or not FavoriteReagentTrackerDB.ingredients then return end

    -- Используем TooltipUtil для получения данных предмета
    local name, link = TooltipUtil.GetDisplayedItem(tooltip)
    if not name or type(name) ~= "string" or name == "" then return end
    
    local cleanName = string.match(name, "^[^|]+")
    if cleanName then cleanName = strtrim(cleanName) else cleanName = name end
    
    local linesToAdd = {}
    local addedRecipes = {}
    
    for profName, profTable in pairs(FavoriteReagentTrackerDB.ingredients) do
        local recipesList = profTable[cleanName] or profTable[name]
        if type(recipesList) == "table" and #recipesList > 0 then
            for _, recipeName in ipairs(recipesList) do
                if not addedRecipes[recipeName] then
                    table.insert(linesToAdd, {recipe = recipeName, prof = profName})
                    addedRecipes[recipeName] = true
                end
            end
        end
    end
    
    if #linesToAdd > 0 then
        -- СИНХРОННОЕ добавление строк, без C_Timer.After
        -- Проверка на дубли (оставляем, но она должна работать и так)
        local tooltipName = tooltip:GetName()
        local numLines = tooltip:NumLines()
        
        for i = numLines, math.max(1, numLines - 10), -1 do
            local line
            if tooltipName and _G[tooltipName .. "TextLeft" .. i] then
                line = _G[tooltipName .. "TextLeft" .. i]
            elseif tooltip.LeftLines and tooltip.LeftLines[i] then
                line = tooltip.LeftLines[i]
            end
            
            local text = line and line:GetText()
            if text and string.find(text, "Нужен для Избранных рецептов", 1, true) then
                return -- Текст уже есть, выходим
            end
        end
        
        tooltip:AddLine(" ")
        tooltip:AddLine("• |cFF00FF00Нужен для Избранных рецептов:|r")
        for _, lineData in ipairs(linesToAdd) do
            tooltip:AddLine("  |cFF888888> " .. lineData.recipe .. " (" .. lineData.prof .. ")|r")
        end
        -- tooltip:Show() вызывать не нужно, тултип уже показан движком
    end
end

-- Регистрация тултипа
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
else
    GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
end

-- Слэш-команда для управления настройками
SLASH_FAVORITEREAGENTTRACKER1 = "/frt"
SlashCmdList["FAVORITEREAGENTTRACKER"] = function(msg)
    local cmd = strtrim(string.lower(msg or ""))
    
    if cmd == "on" then
        FavoriteReagentTrackerDB.showMessages = true
        print("|cFF00FF00FavoriteReagentTracker:|r Сообщения в чат |cFF00FF00ВКЛЮЧЕНЫ|r.")
    elseif cmd == "off" then
        FavoriteReagentTrackerDB.showMessages = false
        print("|cFF00FF00FavoriteReagentTracker:|r Сообщения в чат |cFFFF0000ВЫКЛЮЧЕНЫ|r.")
    else
        local status = FavoriteReagentTrackerDB.showMessages and "|cFF00FF00ВКЛЮЧЕНЫ|r" or "|cFFFF0000ВЫКЛЮЧЕНЫ|r"
        print("|cFF00FF00FavoriteReagentTracker|r (v1.0)")
        print("Текущий статус сообщений: " .. status)
        print("Используйте:")
        print("  |cFFFFFF00/frt on|r  - Включить сообщения")
        print("  |cFFFFFF00/frt off|r - Выключить сообщения")
    end
end