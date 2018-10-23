classdef mlepSO < matlab.System &...
        matlab.system.mixin.SampleTime &...
        matlab.system.mixin.Propagates &...
        matlab.system.mixin.CustomIcon &...
        matlab.system.mixin.Nondirect
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
    %   setup('init') - Initialize system object manually when necessary.
    %                   The routine will start the EnergyPlus process and
    %                   initialize communication. The setup routine is
    %                   called automatically during the first "step" call
    %                   if not ran manually. 
    %
    % See also: MLEP
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
        generateBusObjects = true;   % Generate Bus objects
    end
    
    properties (SetAccess = private, Abstract)
        timestep;                   % Simulation timestep
    end

    properties (SetAccess = private)
        nOut;               % Number of outputs
        nIn;                % Number of inputs
    end
    
    properties (Hidden, SetAccess = private)        
        outputSigName;      % List of output signal names
        inputSigName;       % List of input signal names
        outTable;           % Prototype of output bus (to save time)
    end
    
    properties (Access = private)                            
        % Signal naming function (use with caution)
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
           
            if ~isempty(gcs) && ...
                    (strcmpi(get_param(bdroot,'BlockDiagramType'),'library') || ... % is library?
                     strcmpi(get_param(gcb,'Commented'),'on'))                   % is commented out?
                return
            end
            
            % Initialize             
            obj.initialize;            
            
            % Create output bus object
            if obj.generateBusObjects                               
                obj.createBusObjects;
            end
        end
        
        function validateInputsImpl(obj,in)
            try
                % Validate inputs to the step method at initialization
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
        
    end
    
    methods(Access = private)
        function createBusObjects(obj)                         
            % Create Bus objects - the fastest way is by using the
            % Simulink.Bus.cellToObject method. Avoid calling object
            % properties in the for loop!
           
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
                'EP Output Bus',... %Description
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
                'EP Output Bus',... %Description
                'Auto',... %Data scope
                '-1',... %Alignment
                elems... %Elements
                };
            
            % --- Create the bus objects and assign them to base workspace
            Simulink.Bus.cellToObject({outbus, inbus});
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
        
        function set.inputBusName(obj,value)
            validateattributes(value, {'char'},{'scalartext','nonempty'});
            % Avoid duplicate name
            assert(~strcmp(value,obj.outputBusName),'Bus objects cannot have the same name.'); %#ok<MCSUP>
            obj.inputBusName = value;
        end
        
        function set.outputBusName(obj,value)
            validateattributes(value, {'char'},{'scalartext','nonempty'});
            % Avoid duplicate name
            assert(~strcmp(value,obj.inputBusName),'Bus objects cannot have the same name.'); %#ok<MCSUP>
            obj.outputBusName = value;            
        end
    end
    
    %% ===================== Simulink I/O methods =========================
    methods (Access = protected)

        function [out] = getOutputDataTypeImpl(obj) %#ok<MANU>
            % Return data type for each output port                        
            out = "double";            
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
            out = [obj.nOut 1];            
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
                'PropertyList',{'generateBusObjects','inputBusName','outputBusName'});
            
            busTab = matlab.system.display.SectionGroup(...
                'Title','Bus', ...
                'Sections',busGroup);
            groups = [simTab,busTab];
        end
    end
    
end