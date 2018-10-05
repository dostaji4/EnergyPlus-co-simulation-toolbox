classdef mlepSO < matlab.System &...
        matlab.system.mixin.SampleTime &...
        matlab.system.mixin.Propagates &...
        matlab.system.mixin.CustomIcon &...
        matlab.system.mixin.Nondirect
    %EnergyPlus co-simulation block for Simulink.
    
    % Public, tunable properties
    properties
        
    end
    
    properties(DiscreteState)
        time;
    end
    
    properties (Nontunable)
        idfFile = 'in.idf';         % Specify IDF file
        epwFile = 'in.epw';         % Specify EPW file        
        inputBusName = 'epInbus';   % Input bus name
        outputBusName = 'epOutbus'; % Output bus name                
    end
    
    properties (Logical, Nontunable)
        useBus = true;              % Use bus
    end
    
    properties (Hidden, SetAccess = private)
        nOut;
        nIn;
        timestep;
        outputSigName;
        inputSigName;
        outTable;        
    end
    
    properties (Access = private)                            
        sigNameFcn = @(name,type) ['EP_' regexprep([name '__' type],'\W','_')];        
        inputMap;
        proc;  %mlep instance
    end
    
    %% ======================= Runtime methods ============================
    methods
        function obj = so_mlepBlk(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
    end
    
    methods (Access = protected)
        function setupImpl(obj)            
            if ~obj.proc.isRunning
                obj.proc.start;
            end            
        end

        function resetImpl(obj)
            % Initialize / reset discrete-state properties            
            obj.time = 0;
        end
        
        function validatePropertiesImpl(obj)
            
%             if isLibraryMdl(bdroot), return, end
            % Validate related or interdependent property values
            if isempty(obj.proc)
                obj.proc = mlep;
            end
            
            % Validate files
            obj.proc.idfFile = obj.idfFile;
            obj.proc.epwFile = obj.epwFile;
            
            % Initialize
            obj.proc.initialize;
            
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
        end
        
        function updateImpl(obj,input)
            % Send signals to E+
            if isstruct(input)
                rValIn = struct2array(input);                
            else
                rValIn = input;
            end            
            
            % Write data
            outtime = obj.getCurrentTime;
            if isempty(outtime), outtime = obj.time; end
            obj.proc.write(mlep.encodeRealData(obj.proc.versionProtocol,...
                                              0, ...
                                              outtime,...
                                              rValIn));
        end

        function [flag, time, output] = outputImpl(obj,~)
            % Initialize
            if ~obj.proc.isRunning
                % Create connection
                obj.proc.acceptSocket;
                assert( ...
                    obj.proc.isRunning, ...
                    'EnergyPlusCosim:startupError: Cannot start EnergyPlus.');
            end
            
            % Read data from EnergyPlus
            readPacket = obj.proc.read;
            assert( ...
                ~isempty(readPacket), ...
                'EnergyPlusCosim:readError', ...
                'Could not read data from EnergyPlus.' );
            
            % Decode data
            try
                [flag, time, rValOut] = mlep.decodePacket(readPacket);
            catch me
                obj.stopError(me); %'Error occured while decoding EnergyPlus packet.'
            end
            
            % Process outputs from EnergyPlus
            if flag ~= 0
                err_str = sprintf('EnergyPlusCosim: EnergyPlus process sent flag "%d" (%s).',...
                    flag, mlep.epFlag2str(flag));
                if flag < 0
                    [~,errFile] = fileparts(obj.idfFile);
                    errFile = [errFile '.err'];
                    errFilePath = fullfile(pwd,obj.proc.outputDir,errFile);
                    err_str = [err_str, ...
                        sprintf('Check the <a href="matlab:open %s">%s</a> file for further information.',...
                        errFilePath, errFile)];
                end
                obj.stopError(err_str);
            else
                if ~(numel(rValOut)==obj.nOut)
                    obj.stopError('EnergyPlus data output dimension not correct.');
                end
                
                if obj.useBus
                    % Create output bus
                    obj.outTable{1,:} = rValOut;
                    output = table2struct(obj.outTable);
                    % Note: This is the fastest way compared to
                    % slower  out = cell2struct(num2cell(rValOut'),obj.outputSigName,1);
                    % slowest for i = 1:obj.nOut
                    %            out.(obj.outputSigName{i}) = rValOut(i);
                    %         end
                else
                    % Output vector
                    output = rValOut(:);
                end                
                obj.time = time;
            end
        end
        
        function releaseImpl(obj)
            % Release resources, such as file handles
            % Stop the process
            obj.proc.stop;
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
                elem.SampleTime = obj.proc.timestep;
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
                elem.SampleTime = obj.proc.timestep;
                elem.Complexity = 'real';
                % Add to bus
                bus.Elements(i) = elem;
            end
            assignin('base',obj.inputBusName, bus);
        end
        
        function stopError(obj, msg, varargin)
            obj.proc.stop;
            if isa(msg,'MException')
                rethrow(msg);
            else
                error(msg, varargin{:});
            end
        end
    end
    
    % ----------------------- Get/Set methods -----------------------------
    methods
        function value = get.nIn(obj)
            value = height(obj.proc.inputTable);
        end
        
        function value = get.inputSigName(obj)
            value = cell(obj.nIn,1);
            for i = 1: obj.nIn
                signame = obj.sigNameFcn(obj.proc.inputTable.Name{i},...
                    obj.proc.inputTable.Type{i});
                value{i} = signame;
            end
        end
        
        function value = get.nOut(obj)
            value = height(obj.proc.outputTable);
        end
        
        function value = get.outputSigName(obj)
            value = cell(obj.nOut,1);
            for i = 1: obj.nOut
                signame = obj.sigNameFcn(obj.proc.outputTable.Name{i},...
                    obj.proc.outputTable.Type{i});
                value{i} = signame;
            end
        end
        
        function value = get.timestep(obj)
            value = obj.proc.timestep;
        end
    end
    
    %% ===================== Simulink I/O methods =========================
    methods (Access = protected)
        %         function flag = isInputSizeMutableImpl(obj,index)
        %             % Return false if input size cannot change
        %             % between calls to the System object
        %             flag = false;
        %         end
        %
        %         function flag = isInputComplexityMutableImpl(obj,index)
        %             % Return false if input complexity cannot change
        %             % between calls to the System object
        %             flag = false;
        %         end
        %
        %         function flag = isInputDataTypeMutableImpl(obj,index)
        % Return false if input data type cannot change
        % between calls to the System object
        %             flag = false;
        %         end
        %
        %         function num = getNumInputsImpl(obj)
        %             % Define total number of inputs for system with optional inputs
        %             num = 1;
        %         end
        %
        %         function num = getNumOutputsImpl(obj)
        %             % Define total number of outputs for system with optional
        %             % outputs
        %             num = 3;
        %         end
        %
        function [out,out2,out3] = getOutputDataTypeImpl(obj)
            % Return data type for each output port
            out = "double";
            out2 = "double";
            if obj.useBus
                out3 = obj.outputBusName;
            else
                out3 = "double";
            end
        end
        
        function [out,out2,out3] = isOutputFixedSizeImpl(obj)
            % Return true for each output port with fixed size
            out = true;
            out2 = true;
            out3 = true;
        end

        function [sz,dt,cp] = getDiscreteStateSpecificationImpl(obj,name)
            % Return size, data type, and complexity of discrete-state
            % specified in name
            sz = [1 1];
            dt = "double";
            cp = false;
        end
        
        function [out,out2,out3] = getOutputSizeImpl(obj)
            % Return size for each output port
            out = [1 1];
            out2 = [1 1];
            if obj.useBus
                out3 = [1 1];
            else
                out3 = [obj.nOut 1];
            end
        end
        
        function [out,out2,out3] = isOutputComplexImpl(obj)
            % Return true for each output port with complex data
            out = false;
            out2 = false;
            out3 = false;
        end
        
        function sts = getSampleTimeImpl(obj)            
            sts = obj.createSampleTime("Type", "Discrete", ...
                "SampleTime", obj.timestep);
        end
    end
    
    %% ================== Simulink Block Appearence =======================
    methods(Access = protected)
        function icon = getIconImpl(obj)
            % Define icon for System block
            icon = matlab.system.display.Icon("mlepIcon.jpg"); % Example: image file icon
        end
        
        function name = getInputNamesImpl(obj)
            % Return input port names for System block
            name = obj.inputBusName;
        end
        
        function [name,name2,name3] = getOutputNamesImpl(obj)
            % Return output port names for System block
            name = 'Flag';
            name2 = 'Time';
            name3 = obj.outputBusName;
        end
    end
    
    methods(Access = protected, Static)
        function header = getHeaderImpl(obj)
            % Define header panel for System block dialog
            header = matlab.system.display.Header(mfilename("class"));
        end
        
        function groups = getPropertyGroupsImpl(obj)
            simGroup = matlab.system.display.Section(...
                'Title','Simulation settings',...
                'PropertyList',{'idfFile','epwFile'});
            
            simTab = matlab.system.display.SectionGroup(...
                'Title','Simulation', ...
                'Sections',[simGroup]);
            
            busGroup = matlab.system.display.Section(...
                'Title','Bus',...
                'PropertyList',{'useBus','inputBusName','outputBusName'});
            
            busTab = matlab.system.display.SectionGroup(...
                'Title','Bus', ...
                'Sections',[busGroup]);
            groups = [simTab,busTab];
        end
    end
    
end