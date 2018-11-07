function vector2Bus_clbk(block, type)
%vector2bus_clbk - Callback functions.
% Valid type options are 'popup', 'initMask', 'InitFcn', 'CopyFcn'.

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.

% String to be displayed when no Bus object is selected
default_str = 'Select a Bus object...';

% String to be displayed when no Bus object is found
empty_str = 'No Bus objects found.';

switch type
    case 'popup'
        vector2Bus_popup(block);
    case 'maskInit'
        vector2Bus_maskInit(block);
    case 'InitFcn'
        vector2Bus_InitFcn(block);
    case 'CopyFcn'
        vector2Bus_CopyFcn(block);
    otherwise
        error('Unknown callback: ''%s.''', type);
end

    function vector2Bus_popup(block)
        % Using variable names terminated with "_BOBC" to lessen the chances of
        % collisions with existing workspace variables.
        
        % Get the current block handle and mask handle.        
        maskObj     = Simulink.Mask.get(block);
        popupParam  = maskObj.getParameter('busType');
        
        % --- Find Bus objects ---
        % Get base workspace variables
        bwVars = evalin('base','whos');
        allBusNames = {};
        if ~isempty(bwVars)
            flag = strcmp({bwVars.class},'Simulink.Bus');
            allBusNames = {bwVars(flag).name};                    
        end
        
        % Get Data dictionary variables
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
        else
            popupParam.TypeOptions = {empty_str};
        end    
        
        % Internal Bus Creator handle
        bch = get_param([block '/BusCreator'],'handle');
        
        % --- Mask popup functionality ---
        % all options that can happen, hopefully
        currentOutDataTypeStr = get_param(bch, 'OutDataTypeStr');        
        selectedDataType = get_param(block,'busType');
        lastManuallySelectedParam = popupParam.Value;
          
        if strcmp(currentOutDataTypeStr,'Inherit: auto')            
            if ~ismember(selectedDataType,{default_str, empty_str})                
                % = Previously unused block and valid selection                       
                % Set Output Data Type to the selected value
                set_param(bch, 'OutDataTypeStr',selectedDataType);
                set_param(block,'busType',selectedDataType);
                popupParam.Value = selectedDataType;
            end
        else            
            if strcmp(lastManuallySelectedParam,selectedDataType) && ...
                    strcmp(currentOutDataTypeStr, selectedDataType)
                % = no change
                % Do nothing, nothing changed
            elseif ismember(selectedDataType,{default_str}) || ...
                    (~strcmp(lastManuallySelectedParam,selectedDataType) && ...
                    strcmp(lastManuallySelectedParam,currentOutDataTypeStr))
                % = default or empty selected, or option has disappeared
                % Keep the Output data type and try to select the popup
                % option pertaining to the Output data type
                if ismember(currentOutDataTypeStr, busOpts)            
                    set_param(block,'busType',currentOutDataTypeStr);
                    popupParam.Value = currentOutDataTypeStr;
                else
                    set_param(block,'busType',default_str);
                    popupParam.Value = default_str;
                end
            elseif strcmp(lastManuallySelectedParam,selectedDataType) && ...
                    ismember(currentOutDataTypeStr, busOpts)
                % = bus objects changed, but the output type is still
                % available
                % Keep the Output data type and try to select the popup
                % option pertaining to the Output data type
                set_param(block,'busType',currentOutDataTypeStr);
                popupParam.Value = currentOutDataTypeStr;
            elseif ~strcmp(lastManuallySelectedParam,selectedDataType)
                % = new bus option selected
                % Set Output Data Type to the selected value            
                set_param(bch, 'OutDataTypeStr',selectedDataType);
                set_param(block,'busType',selectedDataType);
                popupParam.Value = selectedDataType;
            else 
                % = bus object changed and the current selection is missing
                % Actually, it is not possible in connection to mlep.
               set_param(bch, 'OutDataTypeStr','Inherit: auto');
            end            
        end
        
        % Set the options to the BusCreator block        
        set_param(bch,'InheritFromInputs', 'off');
    end

    function vector2Bus_maskInit(block)
        % Create demux and bus creator inside. Serves also is an indicator
        % for bus selection validity
        
        %% Validate busType
        
        % Get current option
        selectedBusTypeStr = get_param(block, 'busType');
        
        if ismember(selectedBusTypeStr,{default_str, empty_str}) || ...
            isempty(regexp(selectedBusTypeStr,'Bus: ','ONCE'))                       
            return
        end
        
        % Get Bus Type 
        busType = getBusTypeFromBusTypeStr(selectedBusTypeStr);
        
        % Get Bus object
        model = bdroot(block);
        busObj = getBusObject(model, busType);
        
        % Check the busObj
        if isempty(busObj)          
            warning('Simulink.Bus object ''%s'' not found in a data dictionary nor the base workspace.',...
                busType);
            return
        end
        
        % Get the desired number of elements        
        nSignals = busObj.getNumLeafBusElements;
        
        % Set internal Demux, Bus Creator and connect
        createConnection(block, nSignals);
        
    end

    function vector2Bus_InitFcn(block)
        % Check if Output Data Bus object is available, set "Inherit:auto"
        % if not to allow for its creation elsewhere
        
        % Validate 
        vector2Bus_popup(block);
        
        % Internal Bus Creator handle
        bch = get_param([block '/BusCreator'],'handle');
        
        % Get current Output data        
        currentOutDataTypeStr = get_param(bch, 'OutDataTypeStr');
        
        if ~strcmp(currentOutDataTypeStr, 'Inherit: auto')
            % Get Bus Type 
            busType = getBusTypeFromBusTypeStr(currentOutDataTypeStr);

            % Get Bus object
            model = bdroot(block);           
            
            % Validate bus object
            if isempty(getBusObject(model, busType))
                %Give error
                hilite_system(block);
                error('''%s'': Selected Bus object ''%s'' doesn''t exists in the base workspace nor in any linked data dictionary.', block, busType);
            end
        end
    end

    function vector2Bus_CopyFcn(block)
       % Disable library link
       set_param(block,'LinkStatus','none');
       set_param(block,'CopyFcn','');
    end

    function busObj = getBusObject(model, busType)
        % Load the selected Bus object
        busObj = [];        
        mws = get_param(model,'ModelWorkspace');
        if Simulink.data.existsInGlobal(model,busType)
            % From Data Dictionary first
            busObj = Simulink.data.evalinGlobal(model,busType);            
%         elseif hasVariable(mws,busType)            
%             % From Model workspace next (maybe it will be allowed in the
%             % future)
%             busObj = getVariable(mws, busType);
        elseif evalin('base',['exist(''' busType ''',''var'')'])
            % From Base workspace last
            busObj = evalin('base',busType);            
        end
    end
end

function busType = getBusTypeFromBusTypeStr(busTypeStr)
% ... and parse off "Bus: " so the string of the desired bus contained in
% 'OutDataTypeStr' matches the raw workspace bus names.
busType = regexp(busTypeStr,'^Bus: (.*)','tokens');
assert(~isempty(busType));
busType = busType{1}{1};
end

function createConnection(block, nSignals)
%% Create demux, bus creator and connect them

% Get the current vector size
nOldSignals = str2double(get_param([block '/Demux'],'Outputs'));

% Create connections
if nSignals > nOldSignals
    % Add just the right number of lines
    set_param([block '/Demux'],'Outputs',num2str(nSignals))
    set_param([block '/BusCreator'],'Inputs',num2str(nSignals))
    for iSig = (nOldSignals+1):nSignals
        add_line(block,['Demux/' num2str(iSig)],['BusCreator/' num2str(iSig)])
    end
elseif nSignals < nOldSignals
    % Remove just the right number of lines
    for iSig = (nSignals+1):nOldSignals
        delete_line(block,['Demux/' num2str(iSig)],['BusCreator/' num2str(iSig)])
    end
    set_param([block '/Demux'],'Outputs',num2str(nSignals))
    set_param([block '/BusCreator'],'Inputs',num2str(nSignals))
end
end
