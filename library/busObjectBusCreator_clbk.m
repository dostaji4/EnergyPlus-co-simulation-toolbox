function busObjectBusCreator_clbk(block, type)
%BUSOBJECTBUSCREATOR_CLBK - Callback functions for the 'BusObjectBusCreator' block.

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.
%
% Code influenced by Landon Wagner, 2015 code of 'Bus Object Bus Creator'.

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
        % Using variable names terminated with "_BOBC" to lessen the chances of
        % collisions with existing workspace variables.
        
        % Get the current block handle and mask handle.
        blockHandle = get_param(block,'handle');
        maskObj       = Simulink.Mask.get(block);
        
        % Get a list of variables in the workspace in order to search for the '1x1
        % Bus' types.
        waVars = evalin('base','whos');
        
        % Reset the 'TypeOptions' bus list in case some '1x1 Bus' types have been
        % deleted from or added to the workspace.
        opts = {'<empty>'};
        
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
        
        if nBusObj == 0
            
            % If there are NO bus objects in the workspace then provide a warning
            % popup...
            warning('There are currently no bus objects in the workspace - you have no use for this block. Use a normal Bus Creator instead.')
            
            % ... and do nothing.
            
        else
            % Fill out the BusType options
            if ~strcmp([old_opts{:}],[opts{:}])
                maskObj.Parameters.TypeOptions = opts;
            end
            
            % If the currently selected bus data type ('OutDataTypeStr') is not
            % 'Inherit: auto' then get the current 'OutDataTypeStr' and 'maskVal.'
            if ~strcmp(get_param(blockHandle, 'OutDataTypeStr'), 'Inherit: auto')
                
                outDataStr = get_param(blockHandle, 'OutDataTypeStr');
                maskVal   = get_param(blockHandle, 'MaskValues');
                
                if ~strcmp(outDataStr, maskVal{1}) && ismember(outDataStr, opts)
                    
                    % Upon re-opening the mask if the default 'TypeOptions' list member
                    % (The first one.) contained in 'maskVal' does not match the
                    % currently selected bus data type ('OutDataTypeStr') then set the
                    % 'TypeOptions' list member to the selected bus data type. (Cuts down
                    % on confusion to have the displayed list member match the selected
                    % bus data type rather than the first entry.)
                    set_param(blockHandle, 'MaskValues', {outDataStr});
                end
            end
        end
        
    end

    function busObjectBusCreator_button(block)
        % Using variable names terminated with "_BOBC" to lessen the chances of
        % collisions with existing workspace variables.
        
        % Get the current block, current block handle and mask handle.
        blockHandle = get_param(block,'handle');
        
        % Get the desired bus type...
        busTypeStr = get_param(blockHandle, 'busType');
        
        % ... and set the 'OutDataTypeStr' to it.
        set_param(blockHandle, 'OutDataTypeStr', busTypeStr);
        
        %% First delete any existing lines on the port.
        % Get the line handles.
        lineHandle = get_param(blockHandle, 'LineHandles');
        
        % If any lines exist (Non- -1 line handles.), delete them and start over.
        if max(lineHandle.Inport > 0)
            
            for i = 1:length(lineHandle.Inport)
                if lineHandle.Inport(i) > 0
                    delete_line(lineHandle.Inport(i))
                end
            end
        end
        
        %% Then work on adding new lines.
        
        % Get the block path for 'add_line' function.
        blockPath = get_param(blockHandle, 'Parent');
        
        % Get the newly selected bus type ('OutDataTypeStr')...
        busType = get_param(block, 'OutDataTypeStr');
        
        % ... and parse off "Bus: " so the string of the desired bus contained in
        % 'OutDataTypeStr' matches the raw workspace bus names.
        busType = busType(6:end);
        
        % Then evaluate the string containing the workspace bus name which will
        % load the desired bus parameters.
        busObj = evalin('base',busType);
        
        % From the parameters grab the number of lines to add.
        nElems = busObj.getNumLeafBusElements;
        
        % Set the number of inputs of the masked bus creator to the number of lines
        % to add.
        set_param(blockHandle, 'Inputs', num2str(nElems));
        
        % Set heigh
        sz = get_param(blockHandle, 'Position');
        y0 = sz(2) + (sz(4)-sz(2))/2; % vertical center
        h  = max(sz(4)-sz(2), nElems*10); % height
        sz = [sz(1), ...
            y0 - h/2, ...
            sz(3), ...
            y0 + h/2];
        set_param(blockHandle, 'Position', sz);
        
        % Get (Inputs.) port handles so we can grab the positions of them.
        portHandle = get_param(blockHandle, 'PortHandles');
        
        % Get longest signal name to adjust the line lenght right
        signalNames = {busObj.Elements.Name};
        
        for i = 1:nElems
            
            % Get the position of input port number 'i'.
            portPos = get_param(portHandle.Inport(i), 'Position');
            
            % Add a line long as the longest name
            %(This must be done because it's the lines that get named,
            % not the port positions.)
            portLine = add_line(blockPath, ...
                [portPos - [ceil(50/10*max(strlength(signalNames)))+10 0]; portPos]);
            
            % Rename the new line to the bus 'i-st/nd/rd/th' element name.
            set_param(portLine, 'Name', busObj.Elements(i).Name)
        end
    end

    function busObjectBusCreator_CopyFcn(block)
        % Disable library link
        set_param(block,'LinkStatus','none');
    end
end