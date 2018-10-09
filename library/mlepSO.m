classdef mlepSO < matlab.System &...
        matlab.system.mixin.SampleTime &...
        matlab.system.mixin.Propagates &...
        matlab.system.mixin.CustomIcon &...
        matlab.system.mixin.Nondirect
    %MLEPSO - EnergyPlus co-simulation system object.
    %Simulate EnergyPlus models in Matlab/Simulink using a loose coupling
    %co-simulation mechanism.    
    %
    % Selected Properties and Methods:
    %
    % MLEPSO Properties:
    %   idfFile       - EnergyPlus simulation configuration file (*.IDF)
    %   epwFile       - Weather file (*.EPW).
    %   useBus        - Logical switch determining if input and output are
    %                   buses. (Default: true)
    %   inputBusName  - Name of a Simulink.Bus object created from the
    %                   interface input specification (IDF/variables.cfg).
    %   outputBusName - Name of a Simulink.Bus object created from the
    %                   interface output specification (IDF/variables.cfg).
    %   time          - Current simulation time.
    %
    % MLEPSO Methods:    
    %   y = step(u)   - Send variables "u" to EnergyPlus and get variables
    %                   "y" from EnergyPlus. If useBus = true, then "u" 
    %                   must be an appropriate buses/structure and "y" is
    %                   a bus/structure, otherwise "u" and "y" are vectors
    %                   of appriate sizes.
    %   setup('init') - Initialize system object manually when necessary.
    %                   The routine will start the EnergyPlus process and
    %                   initialize communication. The setup routine is
    %                   called automatically during the first "step" call
    %                   if not ran manually. 
    %
    % See also: MLEP
    %
    %
    % Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
    % All rights reserved.
        
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
    end
    
    properties (Logical, Nontunable)
        useBus = true;              % Use bus
    end
    
    properties (SetAccess = private, Abstract)
        timestep;                   % Simulation timestep
    end
    
    properties (Hidden, SetAccess = private)
        nOut;               % Number of outputs
        nIn;                % Number of inputs
        outputSigName;      % List of output signal names
        inputSigName;       % List of input signal names
        outTable;           % Prototype of output bus (to save time)
    end
    
    properties (Access = private)                            
        sigNameFcn = @(name,type) ['EP_' regexprep([name '__' type],'\W','_')];        
        inputMap;            
    end
    
    %% ====================== Abstract methods ============================
%     methods (Abstract)
%         initialize(obj);                
%     end
    
    %% ======================= Runtime methods ============================
    methods
        function obj = mlepSO(varargin) 
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
    end
    
    methods (Access = protected)
        
        function setupImpl(obj)        
            obj.start;                    
        end
        
        function validatePropertiesImpl(obj)
           
            if ~isempty(bdroot) && isLibraryMdl(bdroot), return, end
            
            % Initialize
            obj.initialize;
            
            % Create output bus object
            if obj.useBus
                % Prepare output structure prototype
                obj.outTable = table('Size',[0 obj.nOut],...
                    'VariableTypes',repmat({'double'},1,obj.nOut),...
                    'VariableNames', obj.outputSigName);    
                obj.outTable{1,:} = zeros(1,obj.nOut);
                obj.createBusObjects;
            end
        end
        
        function validateInputsImpl(obj,in)
            try
                % Validate inputs to the step method at initialization
                if obj.useBus && isstruct(in)
                    assert(isequal(obj.inputSigName,fieldnames(in)));
                else
                    if obj.useBus && ~isstruct(in)
                        warning('Input is not a bus. Assigning inputs by their order.');
                    end
                    if isnumeric(in)
                        assert(numel(in) == obj.nIn,'The size of input %dx%d does not comply with the required size %dx%d.',...
                            size(in,1),size(in,2),obj.nIn, 1);
                    elseif ischar(in) && strcmpi(in,'init')
                        %do nothing
                    else
                        error('Invalid input type "%s". Use either numerical vector of appropriate size or a string ''init''.',...
                            class(in));
                    end
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

            % Write data
            obj.write(inputs, outtime);           
        end

        function output = outputImpl(obj,~)            
            assert(obj.isRunning, 'EnergyPlusCosim: Co-simulation process in not running.');
            
            % Read data from EnergyPlus
            [outputs, obj.time] = read(obj);
            if ~(numel(outputs)==obj.nOut)
                obj.stopError('EnergyPlus data output dimension not correct.');
            end
            
            if obj.useBus
                % Create output bus
                obj.outTable{1,:} = outputs;
                output = table2struct(obj.outTable);
                % Note: This is the fastest way compared to
                % slower  out = cell2struct(num2cell(rValOut'),obj.outputSigName,1);
                % slowest for i = 1:obj.nOut
                %            out.(obj.outputSigName{i}) = rValOut(i);
                %         end
            else
                % Output vector
                output = outputs(:);
            end        
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
        
    end
    
    methods(Access = private)
        function createBusObjects(obj)             
            bus = Simulink.Bus;
            for i = 1:obj.nOut
                % Create one signal
                elem = Simulink.BusElement;
                elem.Name = obj.outputSigName{i};
                elem.Dimensions = 1;
                elem.DimensionsMode = 'Fixed';
                elem.DataType = 'double';
                elem.SampleTime = obj.timestep;
                elem.Complexity = 'real';
                % Add to bus
                bus.Elements(i) = elem;
            end
            assignin('base',obj.outputBusName, bus);
            
            % Create outbus
            bus = Simulink.Bus;
            for i = 1:obj.nIn
                % Create one signal
                elem = Simulink.BusElement;
                elem.Name = obj.inputSigName{i};
                elem.Dimensions = 1;
                elem.DimensionsMode = 'Fixed';
                elem.DataType = 'double';
                elem.SampleTime = obj.timestep;
                elem.Complexity = 'real';
                % Add to bus
                bus.Elements(i) = elem;
            end
            assignin('base',obj.inputBusName, bus);
        end
    end
    
    % ----------------------- Get/Set methods -----------------------------
    methods
        function value = get.nIn(obj)
            value = height(obj.inputTable);
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
            value = height(obj.outputTable);
        end
        
        function value = get.outputSigName(obj)
            value = cell(obj.nOut,1);
            for i = 1: obj.nOut
                signame = obj.sigNameFcn(obj.outputTable.Name{i},...
                    obj.outputTable.Type{i});
                value{i} = signame;
            end
        end
        
    end
    
    %% ===================== Simulink I/O methods =========================
    methods (Access = protected)

        function [out] = getOutputDataTypeImpl(obj)
            % Return data type for each output port            
            if obj.useBus
                out = obj.outputBusName;
            else
                out = "double";
            end                        
        end
        
        function [out] = isOutputFixedSizeImpl(obj) %#ok<MANU>
            % Return true for each output port with fixed size
            out = true;            
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
            if obj.useBus
                out = [1 1];
            else
                out = [obj.nOut 1];
            end
        end
        
        function [out,out2] = isOutputComplexImpl(obj) %#ok<MANU>
            % Return true for each output port with complex data
            out = false;
            out2 = false;            
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
                'PropertyList',{'useBus','inputBusName','outputBusName'});
            
            busTab = matlab.system.display.SectionGroup(...
                'Title','Bus', ...
                'Sections',busGroup);
            groups = [simTab,busTab];
        end
    end
    
end