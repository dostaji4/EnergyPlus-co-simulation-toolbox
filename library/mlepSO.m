%MLEPSO EnergyPlus co-simulation system object.
%Simulate EnergyPlus models in Matlab/Simulink using a loose coupling
%co-simulation mechanism. 
%
% Selected Properties and Methods:
%
% MLEPSO Properties:
%   idfFile       - EnergyPlus simulation configuration file (*.IDF)
%   epwFile       - Weather file (*.EPW).
%   inputBusName  - Name of a Simulink.Bus object created from the
%                   interface input specification (IDF/variables.cfg).
%   outputBusName - Name of a Simulink.Bus object created from the
%                   interface output specification (IDF/variables.cfg).
%   time          - Current simulation time.
%
% MLEPSO Methods:
%   y = step(u)   - Send variables 'u' to EnergyPlus and get variables
%                   'y' from EnergyPlus. 'u' and 'y' are vectors
%                   of appriate sizes defined by I/O definition in the
%                   IDF file. You can obtain the sizes by reading the
%                   'nIn' and 'nOut' properties.
%
% See also: MLEP, mlepLibrary.slx
%

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are
% met:
%
% 1. Redistributions of source code must retain the above copyright notice,
%    this list of conditions and the following disclaimer.
% 2. Redistributions in binary form must reproduce the above copyright
%    notice, this list of conditions and the following disclaimer in the
%    documentation and/or other materials provided with the distribution.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% "AS IS". NO WARRANTIES ARE GRANTED.
%

classdef mlepSO < matlab.System &...
        matlab.system.mixin.SampleTime &...
        matlab.system.mixin.Propagates &...
        matlab.system.mixin.CustomIcon &...
        matlab.system.mixin.Nondirect
    
    properties(DiscreteState)
        time;                       % Current simulation time
    end
    
    properties (Nontunable, Abstract)
        idfFile;                    % Specify IDF file
        epwFile;                    % Specify EPW file
    end
    
    properties (Nontunable)
        inputBusName = 'epInbus';   % Input bus name
        outputBusName = 'epOutbus'; % Output bus name
        dataDictionaryName = 'EnergyPlusSimulation.sldd'; % Data Dictionary
    end
    
    properties (SetAccess=protected, Nontunable, Abstract)
        idfFullFilename;
        epwFullFilename;
    end
    
    properties (Logical, Nontunable)
        useDataDictionary = false;  % Store Bus objects in Data dictionary?
    end
    
    properties (Dependent)
        nOut;               % Number of outputs
        nIn;                % Number of inputs
        outputSigName;      % List of output signal names
        inputSigName;       % List of input signal names
    end
    
    properties (Access = private)
        % Signal naming function (use with caution)
        sigNameFcn = @(name,type) ['EP_' regexprep([name '__' type],'\W','_')];
        inputMap;
    end
    
    %% ======================= Runtime methods ============================
    methods
        function obj = mlepSO(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
        
    end
    
    methods (Access = protected)
        
        function setupImpl(obj)
            % Start the EnergyPlus process and initialize communication
            obj.start;
        end
        
        function validatePropertiesImpl(obj)
            % Properties of mlepSO cannot be changed here. Only setAccess = protecte properties of 'mlep'
            % can be changed freely!
            
            % Running from Simulink?
            try
                isSimulink = ~isempty(get_param(gcb,'System'));
            catch
                isSimulink = 0;
            end
            
            % Load properties
            [~, idfFullpath] = mlep.validateInputFilename(obj.idfFullFilename, 'IDF');
            isReinitialize = mlepSO.requiresReinitialization(idfFullpath);
            
            %%%% !!!!!!! DISABLE PROPERTY LOADING UNTIL TESTED
            isReinitialize = true;
            
            if isReinitialize
                % Run initialization
                obj.initialize;
            
                if isSimulink
                    % Save the data
                    dataStoreBlock = mlepSO.getDataStoreBlock;
                    if ~isempty(dataStoreBlock)
                        saveToUserData(obj, dataStoreBlock);
                    end
                end
            else
                if isSimulink
                    
                    % Get saved data
                    dataStoreBlock = mlepSO.getDataStoreBlock;
                    inUserData = get_param(dataStoreBlock,'UserData');
                    
                    % Load object properties
                    load(obj,inUserData.mlepSavedObjStruct);
                end
            end
        end
        
        function validateInputsImpl(obj,in)
            % Validate inputs to the step method at initialization
            try
                if isstruct(in)
                    assert(isequal(obj.inputSigName,fieldnames(in)),'Input bus doesn''t comply with the specification derived from IDF file.');
                elseif isnumeric(in)
                    assert(numel(in) == obj.nIn,'The size of input %dx%d does not comply with the required size %dx%d.',...
                        size(in,1),size(in,2),obj.nIn, 1);
                elseif ischar(in) && strcmpi(in,'init')
                    %do nothing, it is the setup('init') call.
                else
                    error('Invalid input type "%s". Use either numerical vector of appropriate size or a string ''init''.',...
                        class(in));
                end
            catch me
                obj.stop;
                rethrow(me);
            end
        end
        
        function updateImpl(obj,input)
            % Send signals to E+
            if isstruct(input)
                inputs = struct2array(input);
            else
                inputs = input;
            end
            
            outtime = obj.getCurrentTime;            
            if isempty(outtime), outtime = obj.time; end            
            dt = outtime - obj.time;
            if dt ~= 0
                warning('Discrepancy in simulation time detected. EnergyPlus is %d sec. ahead.',dt);
            end
            
            
            % Write data
            obj.write(inputs, outtime);
        end
        
        function output = outputImpl(obj,input)
            % Read data from EnergyPlus and output them as a collumn vector
            
            assert(obj.isRunning, 'EnergyPlusCosim: Co-simulation process in not running.');
            % Read data from EnergyPlus
            [outputs, obj.time] = read(obj);
            if ~(numel(outputs)==obj.nOut)
                obj.stopError('EnergyPlus data output dimension not correct.');
            end
            
            % Output as a collumn vector
            output = outputs(:);
        end
        
        function resetImpl(obj)
            % Initialize / reset discrete-state properties
            obj.time = 0;
        end
        
        function releaseImpl(obj)
            % Release resources, such as file handles
            
            % Stop the process
            obj.stop;
        end
        
        function s = saveObjectImpl(obj)
            % Save object
            s = save(obj);
        end
        
        function loadObjectImpl(obj,s,~)
            % Load object
            load(obj,s);
        end
    end
    
    methods (Hidden)
        function loadBusObjects(obj)
            % Load or create bus objects for a Simulink implementation
            % Reinitialize only when necessary (i.e. IDF file change)
            
            isReinitialize = mlepSO.requiresReinitialization(obj.idfFullFilename);
            
            if isReinitialize
                % Run initialization
                obj.initialize;
                
                % Save the data
                dataStoreBlock = mlepSO.getDataStoreBlock;
                if ~isempty(dataStoreBlock)
                    saveToUserData(obj, dataStoreBlock);
                end
                
            else
                % --- Load initialized data from block ----------------
                % We are in Simulink and there is loadable UserData
                
                % Reassign bus objects
                if ~obj.useDataDictionary
                    
                    dataStoreBlock = mlepSO.getDataStoreBlock;
                    
                    % Get Bus objects
                    inUserData = get_param(dataStoreBlock,'UserData');
                    
                    % Assign them
                    assignin('base',obj.inputBusName,inUserData.inBus);
                    assignin('base',obj.outputBusName,inUserData.outBus);
                end
            end
        end
    end
    
    methods (Access = private)
        function [inBus, outBus] = createBusObjects(obj)
            % Create Bus objects
            % The fastest way is by using the Simulink.Bus.cellToObject
            % method. Avoid calling object properties in the for loop.
            % Dot notation is expensive!
            
            busDescr = 'EnergyPlus Simulation bus';
            
            % --- Clear all existing EnergyPlus Bus objects in data
            % dictionary
            
            % Get Data dictionary variables
            if obj.useDataDictionary
                ddRootName = get_param(bdroot,'DataDictionary');
                if ~isempty(ddRootName)
                    rootDD = Simulink.data.dictionary.open(ddRootName);
                    ddSec = getSection(rootDD,'Design Data');
                    ddVars = find(ddSec,'-value','-class','Simulink.Bus'); %#ok<GTARG>
                    for i = 1:numel(ddVars)
                        val = getValue(ddVars(i));
                        if isprop(val,'Description') && strcmp(val.Description, busDescr)
                            deleteEntry(ddSec,ddVars(i).Name);
                        end
                    end
                    % Close all
                    saveChanges(rootDD);
                    close(rootDD);
                end
            end
            
            % --- Create outbus
            elems = cell(obj.nOut,1);
            Ts = obj.timestep;
            signames = obj.outputSigName;
            for i = 1:obj.nOut
                elems{i} = cell(1,6);
                elems{i}{1} = signames{i};   %Element name
                elems{i}{2} = 1;            %Dimensions
                elems{i}{3} = 'double';     %Data type
                elems{i}{4} = Ts;           %Sample time
                elems{i}{5} = 'real';       %Complexity
                elems{i}{6} = 'Sample';     %Sampling mode
            end
            
            
            %Bus object information, specified as a cell array of cell arrays. Each subordinate cell array must contain this bus object information:
            outbus = {...
                obj.outputBusName,... %Bus name
                '',... %Header file
                busDescr,... %Description
                'Auto',... %Data scope
                '-1',... %Alignment
                elems... %Elements
                };
            
            % --- Create inbus
            elems = cell(obj.nIn,1);
            signames = obj.inputSigName;
            for i = 1:obj.nIn
                elems{i} = cell(1,6);
                elems{i}{1} = signames{i};   %Element name
                elems{i}{2} = 1;            %Dimensions
                elems{i}{3} = 'double';     %Data type
                elems{i}{4} = Ts;           %Sample time
                elems{i}{5} = 'real';       %Complexity
                elems{i}{6} = 'Sample';     %Sampling mode
            end
            
            
            %Bus object information, specified as a cell array of cell arrays. Each subordinate cell array must contain this bus object information:
            inbus = {...
                obj.inputBusName,... %Bus name
                '',... %Header file
                busDescr,... %Description
                'Auto',... %Data scope
                '-1',... %Alignment
                elems... %Elements
                };
            
            % --- Create the bus objects and assign them to base workspace
            Simulink.Bus.cellToObject({outbus, inbus});
            
            % Get the Bus Objects
            inBus = evalin('base',obj.inputBusName);
            outBus = evalin('base',obj.outputBusName);
            
            % --- Save data to data dictionary
            if obj.useDataDictionary
                % Create/open Data Dictionary for EnergyPlus
                epDictionaryName = obj.dataDictionaryName;
                epDictionaryFilename = [fileparts(get_param(bdroot,'FileName')) filesep epDictionaryName];
                if exist(epDictionaryFilename,'file')
                    epDD = Simulink.data.dictionary.open(epDictionaryFilename);
                else
                    epDD = Simulink.data.dictionary.create(epDictionaryFilename);
                end
                epSec = getSection(epDD,'Design Data');
                
                % Save to model workspace (it would be the obvious choice,
                % but it is not allowed to load bus objects from here the moment)
                %                 ws = get_param(bdroot,'ModelWorkspace');
                %                 assignin(ws,obj.inputBusName,inBus);
                %                 assignin(ws,obj.outputBusName,outBus);
                
                % Assign the Bus Objects to the Data Dictionary
                assignin(epSec, obj.inputBusName, inBus);
                assignin(epSec, obj.outputBusName, outBus);
                
                % Save data dictionary
                saveChanges(epDD);
                
                % Clear base workspace variables
                evalin('base',['clearvars(''' obj.inputBusName ''',''' obj.outputBusName ''');']);
                
                % Connect to model dictionary or assign dictionary to model
                ddRootName = get_param(bdroot,'DataDictionary');
                if isempty(ddRootName)
                    % Assign EnergyPlus dictionary to the model
                    set_param(bdroot,'DataDictionary',epDictionaryName);
                else
                    % Add data source to the existing Data Dictionary of
                    % the model
                    rootDD = Simulink.data.dictionary.open(ddRootName);
                    addDataSource(rootDD, epDictionaryName);
                    saveChanges(rootDD);
                end
                
                % Close all
                Simulink.data.dictionary.closeAll;
            end
        end
        
        function saveToUserData(obj, block)
            
            % Disable warning
            warning('off','Simulink:Commands:SetParamLinkChangeWarn');
            
            % --- Save initialized data to block ------------------
            if isempty(gcb), return, end
            
            % Get data store block
            dataStoreBlock = find_system(gcb,'LookUnderMasks','on',...
                'FollowLinks','on',...
                'SearchDepth', 1,...
                'System','mlep');
            
            if numel(dataStoreBlock) ~= 1, return, end
            
            % Create bus objects
            [inBus, outBus] = obj.createBusObjects;
            
            % Save IDF checksum
            outUserData = struct;
            outUserData.idfChecksum = obj.idfChecksum;
            
            % Save bus objects
            outUserData.inBus = inBus;
            outUserData.outBus = outBus;
            
            % Save the object (all data)
            outUserData.mlepSavedObjStruct = save(obj);
            
            % Save object into the block UserData
            set_param(block,'UserData',outUserData);
            set_param(block,'UserDataPersistent',1);
            
            % Enable warning            
            warning('on','Simulink:Commands:SetParamLinkChangeWarn');
        end
        
    end
    
    methods (Static, Access = private)
        function isReinitialize = requiresReinitialization(idfFile)
            % Data store block = 'The system object block';
            isReinitialize = 1;
            
            if isempty(bdroot) || ...
                    strcmpi(get_param(bdroot,'BlockDiagramType'),'library') || ...
                    strcmpi(get_param(gcb,'Commented'),'on')                       % is commented out?
                return
            end
            
            % Get data store block
            dataStoreBlock = find_system(gcb,'LookUnderMasks','on',...
                'FollowLinks','on',...
                'SearchDepth', 1,...
                'System','mlep');
            
            if isempty(dataStoreBlock), return, end
            
            % Get saved UserData
            inUserData = get_param(gcb,'UserData');
            
            
            if isempty(inUserData) || ...                     % has saved state?
                    ~isfield(inUserData,'idfChecksum') || ... % checksum exists?
                    ~isfield(inUserData,'inBus') || ...       % inBus exists?
                    ~isfield(inUserData,'outBus') || ...      % outBus exists?
                    ~isfield(inUserData,'mlepSavedObjStruct') % saved obj data exist?
                return
            end
            
            % --- Compare IDF checksums
            % Get old checksum
            oldChecksum = inUserData.idfChecksum;
            
            % Create current IDF file checksum
            currentChecksum = mlep.fileChecksum(idfFile);
            
            if strcmp(oldChecksum, currentChecksum)
                % Do not load again, just assure busObjects are
                % assigned
                isReinitialize = 0;
            end
        end
        
        function block = getDataStoreBlock
            block = '';
            if isempty(gcb), return, end
            
            % Get data store block
            dataStoreBlock = find_system(gcb,'LookUnderMasks','on',...
                'FollowLinks','on',...
                'SearchDepth', 1,...
                'System','mlep');
            
            if numel(dataStoreBlock) ~= 1, return, end
            
            block = dataStoreBlock{1};
        end
    end
    
    %% ----------------------- Get/Set methods -----------------------------
    methods
        function value = get.nIn(obj)
            if ~isempty(obj.inputTable)
                value = height(obj.inputTable);
            else
                value = 0;
            end
        end
        
        function value = get.inputSigName(obj)
            value = cell(obj.nIn,1);
            for i = 1: obj.nIn
                signame = obj.sigNameFcn(obj.inputTable.Name{i},...
                    obj.inputTable.Type{i});
                value{i} = signame;
            end
        end
        
        function value = get.nOut(obj)
            if ~isempty(obj.outputTable)
                value = height(obj.outputTable);
            else
                value = 0;
            end
        end
        
        function value = get.outputSigName(obj)
            value = cell(obj.nOut,1);
            for i = 1: obj.nOut
                signame = obj.sigNameFcn(obj.outputTable.Name{i},...
                    obj.outputTable.Type{i});
                value{i} = signame;
            end
        end
        
        function set.inputBusName(obj,value)
            validateattributes(value, {'char'},{'scalartext','nonempty'});
            % Check if it is a valid variable name
            assert(isvarname(value), 'Invalid variable name "%s".', value);
            % Avoid duplicate name
            assert(~strcmp(value,obj.outputBusName),'Bus objects cannot have the same name.'); %#ok<MCSUP>
            obj.inputBusName = value;
        end
        
        function set.outputBusName(obj,value)
            validateattributes(value, {'char'},{'scalartext','nonempty'});
            % Check if it is a valid variable name
            assert(isvarname(value), 'Invalid variable name "%s".', value);
            % Avoid duplicate name
            assert(~strcmp(value,obj.inputBusName),'Bus objects cannot have the same name.'); %#ok<MCSUP>
            obj.outputBusName = value;
        end
        
        %         function set.idfFile_SO(obj,value)
        %             obj.idfFile_SO = value;
        %
        %             if ~isempty(gcb) && strcmpi(get_param(bdroot,'BlockDiagramType'),'library')
        %                 %Trigger idfFile set
        %                 obj.idfFile = value;
        %             end
        %         end
        %
        %         function set.epwFile_SO(obj,value)
        %             obj.epwFile_SO = value;
        %
        %             %Trigger epwFile set
        %             obj.epwFile = value;
        %         end
    end
    
    %% ===================== Simulink I/O methods =========================
    methods (Access = protected)
        
        function [out] = getOutputDataTypeImpl(obj) %#ok<MANU>
            % Return data type for each output port
            out = "double";
        end
        
        function [sz,dt,cp] = getDiscreteStateSpecificationImpl(obj,name) %#ok<INUSD>
            % Return size, data type, and complexity of discrete-state
            % specified in name
            sz = [1 1];
            dt = "double";
            cp = false;
        end
        
        function [out] = getOutputSizeImpl(obj)
            % Return size for each output port
            out = [obj.nOut 1];
        end
        
        function [out] = isOutputFixedSizeImpl(obj) %#ok<MANU>
            % Return true for each output port with fixed size
            out = true;
        end
        
        function [out] = isOutputComplexImpl(obj) %#ok<MANU>
            % Return true for each output port with complex data
            out = false;
        end
        
        function sts = getSampleTimeImpl(obj)
            % Specify sampling time
            sts = obj.createSampleTime("Type", "Discrete", ...
                "SampleTime", obj.timestep);
        end
    end
    
    %% ================== Simulink Block Appearence =======================
    methods(Access = protected)
        function icon = getIconImpl(obj) %#ok<MANU>
            % Define icon for System block
            icon = matlab.system.display.Icon("mlepIcon.jpg"); % Example: image file icon
        end
        
        function name = getInputNamesImpl(obj)
            % Return input port names for System block
            name = obj.inputBusName;
        end
        
        function [out] = getOutputNamesImpl(obj)
            % Return output port names for System block
            out = obj.outputBusName;
        end
    end
    
    methods(Access = protected, Static)
        
        function simMode = getSimulateUsingImpl
            simMode = 'Interpreted execution';
        end
        
        function flag = showSimulateUsingImpl
            % Hide Simulate using block
            flag = false;
        end
        
        function header = getHeaderImpl(obj) %#ok<INUSD>
            % Define header panel for System block dialog
            header = matlab.system.display.Header(mfilename("class"));
        end
        
        function groups = getPropertyGroupsImpl(obj) %#ok<INUSD>
            simGroup = matlab.system.display.Section(...
                'Title','Simulation settings',...
                'PropertyList',{'idfFile','epwFile'});
            
            simTab = matlab.system.display.SectionGroup(...
                'Title','Simulation', ...
                'Sections',simGroup);
            
            busGroup = matlab.system.display.Section(...
                'Title','Bus',...
                'PropertyList',{'inputBusName','outputBusName','useDataDictionary','dataDictionaryName'});
            
            busTab = matlab.system.display.SectionGroup(...
                'Title','Bus', ...
                'Sections',busGroup);
            groups = [simTab,busTab];
        end
    end
    
end