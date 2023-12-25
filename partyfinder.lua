--[[
* MIT License
*
* Copyright (c) 2023 CatsEyeXI [https://github.com/CatsAndBoats]
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
]]--

addon.name      = 'partyfinder';
addon.author    = 'Carver, Loxley';
addon.version   = '1.0';
addon.desc      = 'Party Finder for CatsEyeXI Private Server';
addon.link      = '[https://catseyexi.com]';

require('common');
local ffi    = require('ffi');
local images = require("images");
local imgui  = require('imgui');
local selectedItem = 1;
local guiimages = images.loadTextures();
local queryActive = false;
local opened = false;
local levelFilterCheckbox = { false };
local commentSetColumnEnabled = { false };
local levelRangeInput = { '5' }; 
local partyFinderEntries = T{}
local results = T{};
local modeData = T{};
local interface = {
    IsOpen = { false },
    SelectedIndex = 0,
};

local seacom = {
    search_buffer = { '' },
    search_buffer_size = 256,
};

local tell = {
    tell_buffer = { '[PartyFinder]: Would you like to join my party?' },
    tell_buffer_size = 256,
};

local modeID =
{
    ['ACE'] = 0,
    ['CW']  = 1,
    ['WEW'] = 2,
};

local jobIconMapping = {
    ['WAR'] = 1,
    ['MNK'] = 2,
    ['WHM'] = 3,
    ['BLM'] = 4,
    ['RDM'] = 5,
    ['THF'] = 6,
    ['PLD'] = 7,
    ['DRG'] = 8,
    ['BST'] = 9,
    ['BRD'] = 10,
    ['RNG'] = 11,
    ['SAM'] = 12,
    ['NIN'] = 13,
    ['DRK'] = 14,
    ['SMN'] = 15,
    ['BLU'] = 16,
    ['COR'] = 17,
    ['PUP'] = 18,
    ['DNC'] = 19,
    ['SCH'] = 20,
    ['RUN'] = 21,
    ['GEO'] = 22,
}

local guiIcons =
{
    ['refresh'] = 0,
    ['comment'] = 1,
};

-- Not all seacom types are supported on LSB
local selectables = T{
    'expparty',
    'mission&quest',
    'battlecontent',
    'linkshell',
    'item',
    'others'
};

local seacomType = selectables[selectedItem];

local selectableName = T{
    ['expparty']      = 'EXP Party',
    ['mission&quest'] = 'Missions & Quests',
    ['battlecontent'] = 'Battle Content',
    ['linkshell']     = 'Linkshell',
    ['item']          = 'Item & Trade',
    ['others']        = 'Others'
};

local seacomTypes =
{
    -- EXP Party
    [17]  = 'Seek Party',
    [18]  = 'Find Member',
    [19]  = 'Other',
    -- Battle Content
    [33]  = 'Battle Content',
    [34]  = 'Find Member',
    [35]  = 'Other',
    -- Missions & Quests
    [49]  = 'Missions & Quests',
    [50]  = 'Find Member',
    [51]  = 'Other',
    -- Items
    [65]  = 'Want to Sell',
    [66]  = 'Want to Buy',
    [67]  = 'Items (Other)',
    -- Linkshell
    [81]  = 'Looking for LS',
    [82]  = 'Recruiting',
    [83]  = 'Linkshell',
    -- Looking for Friends
    [97]  = 'Looking for Friends',
    -- Other
    [115] = 'Other',
};

local function ClearResults()
    results = T{}
end

ashita.events.register('command', 'HandleCommand', function (e)
    if (e.command == '!pf') then
        queryActive = true;
        interface.SelectedMode = 1;
        interface.IsOpen[1] = true;
        results = T{};
        opened = true;
    end
end);

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if 
        not opened and
        (e.id == 0x000A)
    then
        queryActive = true;
        interface.SelectedMode = 1;
        interface.IsOpen[1] = true;
        results = T{};
        ClearResults()
        coroutine.sleep(1)
        AshitaCore:GetChatManager():QueueCommand(1, '/say !pf');
        opened = true;
    end
end)

-- Icon for Comment sections
local function drawGuiCommentMode(iconID)
     imgui.Image(tonumber(ffi.cast("uint32_t", guiimages.comments)), { 20, 20 }, 
                { 1 * iconID, 0 }, { 1 * iconID + 1, 1 }, 
                { 1, 1, 1, 1 }, { 0, 0, 0, 0 });
end

local function drawGuiIcon(iconID)
    imgui.Image(tonumber(ffi.cast("uint32_t", guiimages.icons)), { 16, 16 }, { 0.125 * iconID, (0.125 * iconID) / 8 }, { 0.125 * iconID + 0.125, ((0.125 * iconID) / 8) + 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 });
end

local function drawJobIcon(jobID)
    local total = 22
    local ratio = 1 / total
    local iconID = jobID - 1

    imgui.Image(tonumber(ffi.cast("uint32_t", guiimages.jobs)), { 24, 24 }, { ratio * iconID, (ratio * iconID) / total }, { ratio * iconID + ratio, ((ratio * iconID) / total) + 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 });
end

ashita.events.register('text_in', 'HandleText', function (e)
    if string.find(e.message, '!pf') then
        e.blocked = true;
        return
    end

    if (queryActive) then
        local nameMatch, nameEnd = string.find(e.message, 'Name: ');
        local modeMatch, modeEnd = string.find(e.message, '| GameMode: ');
        local jobMatch, jobEnd = string.find(e.message, '| Job: ');
        local Level, LevelEnd = string.find(e.message, '| Level: ');
        local zoneMatch, zoneEnd = string.find(e.message, '| Zone: ');
        local seacomID, seacomIDEnd = string.find(e.message, '| Type: ');
        local sComment, sCommentEnd = string.find(e.message, '| Comment: ');

        if zoneMatch and modeMatch and nameMatch and jobMatch then
            e.blocked = true;
            local result = T{
                Name = string.sub(e.message, nameEnd + 1, modeMatch - 2),
                Mode = string.sub(e.message, modeEnd + 1, jobMatch - 2),
                Job = string.sub(e.message, jobEnd + 1, Level - 2),
                Level = string.sub(e.message, LevelEnd + 1, zoneMatch - 2),
                Zone = string.sub(e.message, zoneEnd + 1, seacomID - 2),
                Type = string.sub(e.message, seacomIDEnd + 1, sComment - 2),
                Comment = string.sub(e.message, sCommentEnd + 1),
            };
            result.Type = tonumber(result.Type);
            result.Level = tonumber(result.Level);
            results:append(result);
        end
    end
end);

local function RenderInterface()
    imgui.PushStyleColor(ImGuiCol_Text,                 {0.0, 0.0, 0.0, 1.0});          -- #000000FF (Black)
    imgui.PushStyleColor(ImGuiCol_Button,               {0.8, 0.7176, 0.9569, 1.0});
    imgui.PushStyleColor(ImGuiCol_ButtonActive,         {0.8, 0.7176, 0.9569, 1.0});
    imgui.PushStyleColor(ImGuiCol_ButtonHovered,        {0.898, 0.8353, 0.9882, 1.0});
    imgui.PushStyleColor(ImGuiCol_FrameBg,              {0.96, 0.96, 0.96, 1.0});
    imgui.PushStyleColor(ImGuiCol_FrameBgActive,        {0.235, 0.165, 0.235, 1.0});
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered,       {0.651, 0.882, 0.490, 0.31});
    imgui.PushStyleColor(ImGuiCol_TextDisabled,         {0.6, 0.6, 0.6, 1.0});          -- #999999FF (Gray)
    imgui.PushStyleColor(ImGuiCol_WindowBg,             {0.94, 0.94, 0.94, 1.0});       -- #F0F0F0FF (Light Gray)
    imgui.PushStyleColor(ImGuiCol_ChildBg,              {0.96, 0.96, 0.96, 1.0});       -- #F5F5F5FF (White Smoke)
    imgui.PushStyleColor(ImGuiCol_PopupBg,              {1.0, 1.0, 1.0, 0.98});         -- #FFFFFFFF (White)
    imgui.PushStyleColor(ImGuiCol_Border,               {0.0, 0.0, 0.0, 0.3});          -- #0000004D (Dark Gray)
    imgui.PushStyleColor(ImGuiCol_BorderShadow,         {0.0, 0.0, 0.0, 0.0});          -- #00000000 (Transparent)
    imgui.PushStyleColor(ImGuiCol_TitleBg,              {0.96, 0.96, 0.96, 1.0});       -- #F5F5F5FF (White Smoke)
    imgui.PushStyleColor(ImGuiCol_TitleBgActive,        {0.82, 0.82, 0.82, 1.0});       -- #D1D1D1FF (Light Gray)
    imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed,     {1.0, 1.0, 1.0, 0.51});         -- #FFFFFF82 (Semi-transparent White)
    imgui.PushStyleColor(ImGuiCol_ScrollbarBg,          {0.82, 0.82, 0.82, 1.0});       -- #D1D1D1FF (Light Gray)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrab,        {0.8, 0.7176, 0.9569, 1.0});    -- #CCB7F4FF (Light Purple)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive,  {0.8, 0.7176, 0.9569, 1.0});    -- #CCB7F4FF (Light Purple)
    imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, {0.235, 0.165, 0.235, 1.0});    -- #3C2A3CFF (Dark Purple)
    imgui.PushStyleColor(ImGuiCol_HeaderActive,         {0.439, 0.772, 0.204, 0.31});   -- #6FA93D4F (Green)
    imgui.PushStyleColor(ImGuiCol_Header,               {0.8, 0.7176, 0.9569, 1.0});    -- #BA9DBBFF (Light Purple)
    imgui.PushStyleColor(ImGuiCol_HeaderHovered,        {0.651, 0.882, 0.490, 0.31});   -- #A6E17D4F (Light Green)
    imgui.PushStyleColor(ImGuiCol_TableRowBg,           {0.2, 0.2, 0.2, 1.0});          -- #333333FF (Dark Gray)

    if (imgui.Begin('Party Finder', interface.IsOpen, ImGuiWindowFlags_AlwaysAutoResize)) then
        -- Set the cursor position to center the content
        local contentWidth = 700;  -- Adjust the width as needed
        local windowWidth = imgui.GetWindowWidth();
        local xPos = (windowWidth - contentWidth) * 0.5;

        imgui.Text("Game Mode:");
        imgui.SameLine();

        if imgui.BeginCombo('##ModeList_ComboBox', modeData[interface.SelectedMode].Display, ImGuiComboFlags_None) then
            for index, entry in ipairs(modeData) do
                local isSelected = (interface.SelectedMode == index);
                if imgui.Selectable(entry.Display, isSelected) then
                    if (not isSelected) then
                        interface.SelectedMode = index;
                        interface.SelectedIndex = 0;
                    end
                end
            end

            imgui.EndCombo();
        end

        --imgui.SameLine();
        imgui.Text('Filter:');
        imgui.SameLine();
        imgui.Checkbox('##Filter_Checkbox', levelFilterCheckbox);
        imgui.SameLine();
        imgui.Text('Range:');
        imgui.SameLine();


        local minLevel = 0
        local maxLevel = 75

        imgui.InputInt('##FilterRange_InputInt', levelRangeInput, 5);
        levelRangeInput[1] = math.min(maxLevel, math.max(minLevel, levelRangeInput[1]));

        if imgui.IsItemHovered() then
            imgui.SetTooltip('Only show matches within ' .. levelRangeInput[1] .. ' levels of me.');
        end

        imgui.Text('Comments:');
        imgui.SameLine();
        imgui.Checkbox('##Comment_Checkbox', commentSetColumnEnabled);
        -- Adjust panel width based on comment column visibility
        local panelWidth = commentSetColumnEnabled[1] and 900 or 525

        -- Define the column positions including the additional space for the icon
        local columnPositions = {
            Name = 22,  -- Starting position for the name, after the icon
            Job = 170,  -- Adjusted positions for other columns if necessary
            Location = 315
        }

        -- Add Comment position if enabled
        if commentSetColumnEnabled[1] then
            columnPositions.Comment = 525
        end

        imgui.BeginGroup();
        imgui.BeginChild('leftpane', { panelWidth, 225 }, true);

        -- Table header
        for _, col in pairs({'Name', 'Job', 'Location'}) do
            if columnPositions[col] then
                imgui.SameLine(columnPositions[col]);
            end
            imgui.Text(col);
        end

        -- Render Comment header if enabled
        if commentSetColumnEnabled[1] then
            imgui.SameLine(columnPositions.Comment);
            imgui.Text('Comment');
        end

        imgui.Separator();

        local entries = modeData[interface.SelectedMode].Entries;
        local seekPartyIconID = 0

        for i, entry in ipairs(entries) do

            -- This discovers the CatsEyeXI Mode specifically..
            local modeType = modeID[entry.Mode];

            -- This assumes that `entry.Job` contains the job abbreviation.
            local jobIconId = jobIconMapping[entry.Job] 

            -- Retrieve the textual representation of the 'Type'
            local seacomType = seacomTypes[entry.Type];
            local seacomText = seacomType or 'Other';
            
            -- Selectable spans all columns and is invisible, just for selection
            if imgui.Selectable("##selectable" .. i, interface.SelectedIndex == i, ImGuiSelectableFlags_SpanAllColumns) then
                interface.SelectedIndex = i;
            end

            -- Position the icon before the name
            imgui.SameLine(columnPositions.Name - 21);
            imgui.Image(tonumber(ffi.cast("uint32_t", guiimages.modes)), { 22, 22 }, { 0.25 * modeType, (0.25 * modeType) / 4 }, { 0.25 * modeType + 0.25, ((0.25 * modeType) / 4) + 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 });

            -- Position the name text next to the icon, with proper spacing
            imgui.SameLine(columnPositions.Name);
            imgui.Text(entry.Name);

            -- Position for the job icon
            imgui.SameLine(columnPositions.Job - 24); -- Subtract the width of the icon plus some padding
            if jobIconId then
                drawJobIcon(jobIconId)
            end
            imgui.SameLine(columnPositions.Job);
            imgui.Text(entry.Job .. '(' .. entry.Level .. ')');

            imgui.SameLine(columnPositions.Location);
            imgui.Text(entry.Zone);


            if commentSetColumnEnabled[1] then
                 -- Check if the entry's type is 'Seek Party'
                if seacomText == 'Seek Party' then
                -- Position for the 'seek party' icon
                imgui.SameLine(columnPositions.Comment - 24 ); -- Adjust position for icon
                drawGuiCommentMode(seekPartyIconID)
                end

                imgui.SameLine(columnPositions.Comment);
                imgui.Text(entry.Comment or 'No Comment');
            end

            if seacomType == nil then
                seacomText = 'Other';
            end

            if
                imgui.IsItemHovered() and
                entry.Type ~= nil and
                entry.Type > 0
            then
                imgui.SetTooltip(string.format('[%s]: %s', seacomText, entry.Comment));
            end

            if
                (imgui.IsItemHovered() and
                imgui.IsMouseDoubleClicked(0))
            then
                local cmd = string.format('/sea all %s', entry.Name);
                AshitaCore:GetChatManager():QueueCommand(1, cmd);
            end

            if
                (imgui.IsItemHovered() and
                imgui.IsMouseClicked(1))
            then
                interface.SelectedIndex = i;
            end

        end

        if
            imgui.BeginPopupContextWindow() and
            entries[interface.SelectedIndex] ~= nil
        then
            local playerName = entries[interface.SelectedIndex].Name;
            if imgui.MenuItem('Send Tell') then
                -- AshitaCore:GetChatManager():Write(1, false, "/tell name")
                isTellWindowOpen = true;
            end

            if imgui.MenuItem('Search') then
                local cmd = string.format('/sea all %s', playerName);
                AshitaCore:GetChatManager():QueueCommand(1, cmd);                
            end

            if imgui.MenuItem('Invite') then
                local cmd = string.format('/pcmd add %s', playerName);
                AshitaCore:GetChatManager():QueueCommand(1, cmd);                       
            end

            imgui.EndPopup();
        end

        imgui.EndChild();
        imgui.EndGroup();

        local jobID    = AshitaCore:GetMemoryManager():GetPlayer():GetMainJob();
        local subID    = AshitaCore:GetMemoryManager():GetPlayer():GetSubJob();
        local jobLevel = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel();
        local jobName  = AshitaCore:GetResourceManager():GetString("jobs.names_abbr", jobID);

        drawJobIcon(jobID);
        imgui.SameLine();

        local jobStr = string.format('%s%u', jobName, jobLevel);

        if subID > 0 then
            jobStr = jobStr .. string.format('\n%s%u', AshitaCore:GetResourceManager():GetString("jobs.names_abbr", subID),  AshitaCore:GetMemoryManager():GetPlayer():GetSubJobLevel());
        end

        imgui.Text(jobStr);
        imgui.SameLine();

        if imgui.Button('Register', { 100, 30 }) then
            local cmd ='/say !pf register';
            AshitaCore:GetChatManager():QueueCommand(1, cmd);
            ashita.misc.play_sound(addon.path:append('\\sounds\\register.wav'));
        end

        imgui.SameLine();
        if imgui.Button('Withdraw', { 100, 30 }) then
            local cmd ='/say !pf remove';
            AshitaCore:GetChatManager():QueueCommand(1, cmd);         
            ashita.misc.play_sound(addon.path:append('\\sounds\\withdraw.wav'));
        end

        imgui.SameLine();
        if imgui.Button('Comment', { 100, 30 }) then
            isCommentWindowOpen = true;
        end

        local buttonWidth = 80;
        local buttonSpacing = 10;
        local buttonXPos = windowWidth - (buttonWidth + buttonSpacing);

        imgui.SameLine();
        imgui.SetCursorPosX(buttonXPos + 40);

        local iconID = guiIcons.refresh;
        if imgui.ImageButton(tonumber(ffi.cast("uint32_t", guiimages.icons)), { 25, 25 }, { 0.125 * iconID, (0.125 * iconID) / 8 }, { 0.125 * iconID + 0.125, ((0.125 * iconID) / 8) + 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 0 }) then
            ClearResults();
            coroutine.sleep(1);
            AshitaCore:GetChatManager():QueueCommand(1, '/say !pf');
        end
    end

    -- Comment Window
    if isCommentWindowOpen then
        if (imgui.Begin('Search Comment', true, ImGuiWindowFlags_AlwaysAutoResize)) then
            imgui.Text('Comment type:');
            if imgui.BeginCombo('##CommentTypeCombo', selectableName[seacomType], ImGuiComboFlags_None) then
                for index,entry in ipairs(selectables) do
                    if imgui.Selectable(selectableName[selectables[index]], selectedItem == index) then
                        selectedItem = index;
                        seacomType = selectables[selectedItem];
                    end
                end

                imgui.EndCombo();
            end

            comment = imgui.InputText('', seacom.search_buffer, seacom.search_buffer_size, ImGuiInputTextFlags_EnterReturnsTrue);

            if imgui.Button('Submit', { 80, 30 }) then
                --Create a function to hold the delayed actions..
                local function PostCloseCommands(searchString, searchType)
                    local seacomCmd   = string.format('/sc 1 "%s"', searchString);
                    local seacomUpCmd = string.format('/scu %s 1', seacomType);

                    AshitaCore:GetChatManager():QueueCommand(1, seacomCmd);
                    coroutine.sleep(0.5);
                    AshitaCore:GetChatManager():QueueCommand(1, seacomUpCmd);

                    ashita.misc.play_sound(addon.path:append('\\sounds\\seacom.wav'));
                end

                --Attach args to function..
                local boundFunction = PostCloseCommands:bind1(seacom.search_buffer[1]):bind1(seacomType);

                --Call the function next frame..
                boundFunction:oncef(1);

                --Close immediately..
                isCommentWindowOpen = false;
            end

            imgui.SameLine();
            if imgui.Button('Clear', { 80, 30 }) then
                --Create a function to hold the delayed actions..
                local function PostCloseCommands(searchString, searchType)
                    local seacomCmd   = '/sc 1 ""'
                    AshitaCore:GetChatManager():QueueCommand(1, '/sc 1 ""');
                    coroutine.sleep(0.5);
                    AshitaCore:GetChatManager():QueueCommand(1, '/seacomup');
                end

                --Attach args to function..
                local boundFunction = PostCloseCommands:bind1(seacom.search_buffer[1]):bind1(seacomType);

                --Call the function next frame..
                boundFunction:oncef(1);

                --Close immediately..
                isCommentWindowOpen = false;
            end

            imgui.End();
        end
    end

    -- Tell Window
    if isTellWindowOpen then
        if (imgui.Begin('Send Tell', true, ImGuiWindowFlags_AlwaysAutoResize)) then
            imgui.Text('Message:');

            message = imgui.InputText('##Message_InputBox', tell.tell_buffer, tell.tell_buffer_size, ImGuiInputTextFlags_EnterReturnsTrue);

            if imgui.Button('Submit', { 80, 30 }) then
                -- Check if entries are available and there is a selected entry
                if partyFinderEntries and interface.SelectedIndex > 0 and interface.SelectedIndex <= #partyFinderEntries then
                    local playerName = partyFinderEntries[interface.SelectedIndex].Name;
                    local tellMessage = tell.tell_buffer[1] or '';  -- Use index 1 instead of 0
                    local tell = string.format('/tell %s %s', playerName, tellMessage);

                    AshitaCore:GetChatManager():QueueCommand(1, tell);
                    ashita.misc.play_sound(addon.path:append('\\sounds\\sent_tell.wav'));
                end
            
                isTellWindowOpen = false;
            end

            imgui.SameLine();
            if imgui.Button('Clear', { 80, 30 }) then
                -- Clear input and close the window
                tell.tell_buffer[0] = '';
                isTellWindowOpen = false;
            end

            imgui.End();
        end
    end

    if (not interface.IsOpen[1]) then
        queryActive = false;
    end
end

ashita.events.register('d3d_present', 'HandleRender', function ()
    if (queryActive) then
        local allResults = T{ Name = 'All', Count = 0, Entries = T{} };
        local resultsByMode = T{};
        local playerLevel = AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel();
        local levelRange = tonumber(levelRangeInput[1]) or 5;

        for _,result in ipairs(results) do
            if
                not levelFilterCheckbox[1] or 
                math.abs(result.Level - playerLevel) <= levelRange
            then
                local mode = resultsByMode[result.Mode];

                if mode == nil then
                    resultsByMode[result.Mode] = {
                    Name = result.Mode,
                    Count = 1,
                    Entries = T { result },
                    };
                else
                    mode.Count = mode.Count + 1;
                    mode.Entries:append(result);
                end

                allResults.Entries:append(result);
                allResults.Count = allResults.Count + 1;
            end
        end

        resultsByMode['All'] = allResults;
        modeData = T{};

        for _,mode in pairs(resultsByMode) do
            mode.Display = string.format('%s[%u]', mode.Name, mode.Count);
            modeData:append(mode);
        end

        table.sort(modeData, function(a,b)
            return a.Count > b.Count;
        end);

        for _,mode in ipairs(modeData) do
            table.sort(mode.Entries, function(a,b)
                return (a.Name < b.Name);
            end);
        end

        -- Store results in the global variable
        partyFinderEntries = allResults.Entries;
    end

    if (interface.IsOpen[1] == true) then
        RenderInterface();
    end
end);
