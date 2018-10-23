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
        blockHandle = get_param(block,'handle');
        maskObj       = Simulink.Mask.get(block);
        
        %% Manage BusObjects
        % Get a list of variables in the workspace in order to search for the '1x1
        % Bus' types.
        waVars = evalin('base','whos');
        
        % Current number of options
        old_opts = maskObj.Parameters.TypeOptions;
        
        % Reset the bus count.
        nBusObj = 0;        
        
        for i = 1:length(waVars)
            
            % If the variable is a bus object...
            if strcmp(waVars(i).class, 'Simulink.Bus')
                
                nBusObj = nBusObj + 1;
                
                % ... add it to the TypeOptions of the mask.
                opts(nBusObj) = {['Bus: ', waVars(i).name]};
            end
        end
        
        % Internal Bus Creator handle
        bch = get_param([block '/BusCreator'],'handle');
        
        if nBusObj == 0
            
            % If there are NO bus objects in the workspace then provide a warning
            % popup...
            warning('There are currently no bus objects in the workspace - you have no use for this block.')
            maskObj.Parameters.TypeOptions = {empty_str};
            return
        end
        
        % Add default option
        opts = [{default_str}, opts];
        
        % Fill out the BusType options
        if ~strcmp([old_opts{:}],[opts{:}])
            maskObj.Parameters.TypeOptions = opts;
        end
        
        % If the currently selected bus data type ('OutDataTypeStr') is not
        % 'Inherit: auto' then get the current 'OutDataTypeStr' and 'maskVal.'
        currentOutDataTypeStr = get_param(bch, 'OutDataTypeStr');
        if ~strcmp(currentOutDataTypeStr, 'Inherit: auto')
            
            if ismember(currentOutDataTypeStr, opts)
                % Upon re-opening the mask if the default 'TypeOptions' list member
                % (The first one.) contained in 'maskVal' does not match the
                % currently selected bus data type ('OutDataTypeStr') then set the
                % 'TypeOptions' list member to the selected bus data type. (Cuts down
                % on confusion to have the displayed list member match the selected
                % bus data type rather than the first entry.)
                set_param(blockHandle, 'MaskValues', {currentOutDataTypeStr});
            else
                set_param(blockHandle, 'MaskValues', {default_str});
                set_param(bch, 'OutDataTypeStr','Inherit: auto');
            end
        end
        
    end

    function objExists = vector2Bus_maskInit(block)
        % Create demux and bus creator inside. Return wheater the bus
        % object exists (1 -> exists. 0-> does not exist);
        
        assert(nargout == 0 || nargout == 1);
        %% Create Demux and Bus Creator        
        
        % Get block handle
        blockHandle = get_param(block,'handle');
        
        % Get the internal Bus Creator handle
        bch = get_param([block '/BusCreator'],'handle');
        
        % Get current option
        selectedBusTypeStr = get_param(blockHandle, 'MaskValues');
        
        if ismember(selectedBusTypeStr,{default_str, empty_str}) || ...
            isempty(regexp(selectedBusTypeStr,'Bus: ','ONCE'))
            set_param(bch, 'OutDataTypeStr','Inherit: auto');
            return
        end
        
        % ... and parse off "Bus: " so the string of the desired bus contained in
        % 'OutDataTypeStr' matches the raw workspace bus names.
        busType = regexp(selectedBusTypeStr,'^Bus: (.*)','tokens');            
        assert(~isempty(busType));
        busType = busType{1}{1}{1};

        try 
            % Evaluate the string containing the workspace bus name which will
            % load the desired bus parameters.
            % USE -> Simulink.data.existsInGlobal and Simulink.data.evalinGlobal
            busObj = evalin('base',busType);
            if nargout == 1 
                objExists = 1;
            end
        catch                         
            if nargout == 1 
                objExists = 0;
            else
                warning('''%s'': Selected Bus object ''%s'' doesn''t exists in the base workspace.', block, busType);
            end
            return
        end
        
        % Get the desired number of elements        
        nSignals = busObj.getNumLeafBusElements;
        
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
        
        % Set the type to the BusCreator block
        set_param(bch,'OutDataTypeStr',selectedBusTypeStr{1});
        set_param(bch,'InheritFromInputs', 'off');
    end

    function vector2Bus_InitFcn(block)
%         % Check 
%         % Get block handle
%         blockHandle = get_param(block,'handle');
%         
%         % Get current option
%         selectedBusTypeStr = get_param(blockHandle, 'MaskValues');
%         
%         if strcmp(selectedBusTypeStr,default_str) 
%             error('''%s'': Please select first a Bus object.',block);
%         elseif strcmp(selectedBusTypeStr,empty_str)         
%             error('''%s'': No Bus objects found in the base workspace. The block cannot be used, please comment it out or remove it.',block);
%         end
%         
%         % Check if the Bus object exists
%         busType = regexp(selectedBusTypeStr,'^Bus: (.*)','tokens');
%         assert(~isempty(busType{1}));
%         busType = busType{1}{1}{1};
           
        % Recreate inner blocks
        objExists = vector2Bus_maskInit(block);
        
        % Give error 
        if ~objExists
            error('''%s'': Selected Bus object ''%s'' doesn''t exists in the base workspace.', block, busType);
        end
    end

    function vector2Bus_CopyFcn(block)
       % Disable library link
       set_param(block,'LinkStatus','none');
       set_param(block,'CopyFcn','');
    end
end