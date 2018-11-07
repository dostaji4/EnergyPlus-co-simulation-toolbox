function busObjectBusCreator_clbk(block, type)
%BUSOBJECTBUSCREATOR_CLBK - Callback functions for the 'BusObjectBusCreator' block.

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.
%
% Code influenced by Landon Wagner, 2015 code of 'Bus Object Bus Creator'.

% String to be displayed when no Bus object is selected
default_str = 'Select a Bus object...';

% String to be displayed when no Bus object is found
empty_str = 'No Bus objects found.';

switch type
    case 'popup'
        busObjectBusCreator_popup(block);
    case 'button'
        busObjectBusCreator_button(block);
    case 'CopyFcn'
        busObjectBusCreator_CopyFcn(block);
    otherwise
        error('Unknown callback: ''%s.''', type);
end


    function busObjectBusCreator_popup(block)
        % Get the current block handle and mask handle.
        bch = get_param(block,'handle');
        maskObj = Simulink.Mask.get(block);
        popupParam = maskObj.getParameter('busType');        
        
        % --- Find Bus objects ---
        % Get base workspace variables
        bwVars = evalin('base','whos');
        allBusNames = {};
        if ~isempty(bwVars)
            flag = strcmp({bwVars.class},'Simulink.Bus');
            allBusNames = {bwVars(flag).name};                    
        end
        
        % Get Data dictionary - Design Data Bus objects        
        ddName = get_param(bdroot(block),'DataDictionary');
        if ~isempty(ddName)
            dd = Simulink.data.dictionary.open(ddName);  
            ddSec = getSection(dd,'Design Data');
            ddVars = find(ddSec,'-value','-class','Simulink.Bus'); %#ok<GTARG>
            allBusNames = [allBusNames {ddVars.Name}];
        end
        
        % --- Create popup --- 
        % Create popup entries        
        busOpts = strcat({'Bus: '}, allBusNames);
        
        if ~isempty(busOpts)            
            % Add default option
            extOpts = [{default_str}, busOpts];
            
            % Current number of options
            old_opts = popupParam.TypeOptions;
            
            % Fill out the BusType options
            if ~strcmp([old_opts{:}],[extOpts{:}])
                popupParam.TypeOptions = extOpts;
            end
        end
        
        % If the currently selected bus data type ('OutDataTypeStr') is not
        % 'Inherit: auto' then get the current 'OutDataTypeStr' and 'maskVal.'
        currentOutDataTypeStr = get_param(bch, 'OutDataTypeStr');
        if ~strcmp(currentOutDataTypeStr, 'Inherit: auto')
            
            if ismember(currentOutDataTypeStr, busOpts)
                % Upon re-opening the mask if the default 'TypeOptions' list member
                % (The first one.) contained in 'maskVal' does not match the
                % currently selected bus data type ('OutDataTypeStr') then set the
                % 'TypeOptions' list member to the selected bus data type. (Cuts down
                % on confusion to have the displayed list member match the selected
                % bus data type rather than the first entry.)
                popupParam.Value = currentOutDataTypeStr;
            else
                if isempty(busOpts)
                    popupParam.TypeOptions = {empty_str};
                    popupParam.Value = empty_str;
                else
                    popupParam.Value = default_str;                    
                end                
                warning('The Output Data Type ''%s'' is no longer available in a data dictionary nor base workspace. Setting the Output Data Type to ''Inherit: auto''.',...
                    currentOutDataTypeStr);                
                set_param(bch, 'OutDataTypeStr','Inherit: auto');
            end
        end 
    end

    function busObjectBusCreator_button(block)
        % Using variable names terminated with "_BOBC" to lessen the chances of
        % collisions with existing workspace variables.
        
        % Get the current block, current block handle and mask handle.
        bch = get_param(block,'handle');
        
        % Get the desired bus type...
        selectedBusTypeStr = get_param(bch, 'busType');
        
        if ismember(selectedBusTypeStr,{default_str, empty_str}) 
            helpdlg(selectedBusTypeStr);
            return 
        elseif isempty(regexp(selectedBusTypeStr,'Bus: ','ONCE'))
            warndlg('Invalid data entry "%s"',selectedBusTypeStr);
            return
        else
            set_param(bch, 'OutDataTypeStr','Inherit: auto');            
        end
        
        % ... and set the 'OutDataTypeStr' to it.
        set_param(bch, 'OutDataTypeStr', selectedBusTypeStr);
        
                
        % Get the block path for 'add_line' function.
        blockPath = get_param(bch, 'Parent');
        
        % Get the newly selected bus type ('OutDataTypeStr')...
        busType = get_param(block, 'OutDataTypeStr');
        
        % ... and parse off "Bus: " so the string of the desired bus contained in
        % 'OutDataTypeStr' matches the raw workspace bus names.
        busType = busType(6:end);
        
        % Load the selected Bus object
        if Simulink.data.existsInGlobal(bdroot(block),busType)
            % From Data Dictionary first
            busObj = Simulink.data.evalinGlobal(bdroot(block),busType);
        elseif evalin('base',['exist(''' busType ''',''var'')'])
            busObj = evalin('base',busType);
        else
            error('Simulink.Bus object ''%s'' not found in a data dictionary nor the base workspace.',...
                busType);
        end
                
        % From the parameters grab the number of lines to add.
        nElems = busObj.getNumLeafBusElements;        
        assert(nElems > 0, 'The Simulink.Bus object ''%s'' contains zero elements.', busType);
        
        % First delete any existing lines on the port.
        % Get the line handles.
        lineHandle = get_param(bch, 'LineHandles');
        
        % If any lines exist (Non- -1 line handles.), delete them and start over.
        if max(lineHandle.Inport > 0)
            
            for i = 1:length(lineHandle.Inport)
                if lineHandle.Inport(i) > 0
                    delete_line(lineHandle.Inport(i))
                end
            end
        end
        
        % Set the number of inputs of the masked bus creator to the number of lines
        % to add.
        set_param(bch, 'Inputs', num2str(nElems));
        
        % Set heigh
        sz = get_param(bch, 'Position');
        y0 = sz(2) + (sz(4)-sz(2))/2; % vertical center
        h  = max(95, nElems*10); % height
        sz = [sz(1), ...
            y0 - h/2, ...
            sz(3), ...
            y0 + h/2];
        set_param(bch, 'Position', sz);
                
        % Get Input port handles so we can grab the positions of them.
        portHandle = get_param(bch, 'PortHandles');
        
        % Get longest signal name to adjust the line lenght right
        signalNames = {busObj.Elements.Name};
        lineLength = ceil(50/10*max(strlength(signalNames)))+10;
        for i = 1:nElems            
            % Get the position of input port number 'i'.
            portPos = get_param(portHandle.Inport(i), 'Position');            
            % Add a line long as the longest name
            %(This must be done because it's the lines that get named,
            % not the port positions.)
            portLine = add_line(blockPath, ...
                [portPos - [lineLength 0]; portPos]);
            
            % Rename the new line to the bus 'i-st/nd/rd/th' element name.
            set_param(portLine, 'Name', busObj.Elements(i).Name)
        end
        
    end

    function busObjectBusCreator_CopyFcn(block)
        % Disable library link
        set_param(block,'LinkStatus','none');
    end
end