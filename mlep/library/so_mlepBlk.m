classdef so_mlepBlk < matlab.System &...
                      matlab.system.mixin.SampleTime &...
                      matlab.system.mixin.Propagates &...                      
                      matlab.system.mixin.CustomIcon
    %EnergyPlus co-simulation block for Simulink.
    
    % Public, tunable properties
    properties
        
    end
    
    properties(DiscreteState)
        
    end
    
    properties(Nontunable)        
        idfFile = 'SmOffPSZ.idf'; %Specify IDF file
        epwFile = 'USA_IL_Chicago-OHare.Intl.AP.725300_TMY3.epw'; %Specify EPW file         
        inputBusName = 'epInbus';  %Input bus name
        outputBusName = 'epOutbus'; %Output bus name
    end
    
    properties(Access = private)        
        outputSigName;         
        inputSigName;
        proc;  %mlep instance
        sigNameFcn = @(name,type) regexprep([name '__' type],'\W','_');
        nOutIdf;
        nInIdf;
        inputMap;
    end

%% ======================= Runtime methods ================================
    methods
        function obj = so_mlepBlk(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
    end

    methods (Access = protected)
        function setupImpl(obj)
            % Perform one-time calculations, such as computing constants            
             if ~obj.proc.isRunning
                 obj.proc.start;                
            end
        end
        
        function validatePropertiesImpl(obj)
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
            obj.createBusObjects;
        end

        function validateInputsImpl(obj,inbus)
            % Validate inputs to the step method at initialization
            if ~isstruct(inbus)
                warning('Input is not a bus. Assigning inputs by order.');
                obj.inputMap = 1:numel(inbus);
            else
                %             'Bus with valid signal names is expected at input.';
                inbusSignals = fieldnames(inbus);
                
                for i = 1:obj.nInIdf
                    idx = contains(inbusSignals,obj.inputSigName{i});
                    if ~any(idx) % more then one occurence should not be present
                        obj.stopError('Signal "%s" not found in the input bus.\nExpecting these signals: \n"%s".',...
                            obj.inputSigName{i},...
                            strjoin(obj.inputSigName,'",\n"'));
                    else
                        obj.inputMap(i) = find(idx); % Save inbus to EP mapping
                    end
                end
            end
        end
        
        function [flag,time,outbus] = stepImpl(obj,inbus)
            % Implement algorithm. Calculate y as a function of input u and
            % discrete states.
            % Step EnergyPlus and get outputs
            if ~obj.proc.isRunning
                % Create connection
                [status, msg] = obj.proc.acceptSocket;
                assert( ...
                    status == 0, ...
                    'EnergyPlusCosim:startupError', ...
                    'Cannot start EnergyPlus: %s.', msg );
            end
            
            % Read data from E+
            readpacket = obj.proc.read;
            assert( ...
                ~isempty(readpacket), ...
                'EnergyPlusCosim:readError', ...
                'Could not read data from EnergyPlus.' );
            
            % Decode data
            try 
                [flag, time, rValIn] = mlepDecodePacket(readpacket);
            catch 
                obj.stopError('Error occured while decoding EnergyPlus packet.');
            end
            
            % Process output
            if flag ~= 0                
                err_str = sprintf(['EnergyPlus process sent flag "%d". ',...
                            mlep.epFlag2str(flag)], flag);
                if flag < 0 
                    [~,errFile] = fileparts(obj.idfFile);                    
                    errFile = [errFile '.err'];
                    errFilePath = fullfile(pwd,obj.proc.outputDir,errFile);
                    err_str = [err_str, ...
                        sprintf(' Check the <a href="matlab:open %s">%s</a> file for further information.',...
                            errFilePath, errFile)];
                end
                obj.stopError(err_str);                
            else
                if ~(numel(rValIn)==obj.nOutIdf)
                    obj.stopError('EnergyPlus data output dimension not correct.');
                end
                
                % Create output bus
                for i = 1:obj.nOutIdf                  
                    outbus.(obj.outputSigName{i}) = rValIn(i);
                end
            end
            
            % Send signals to E+            
            if isstruct(inbus)
                inbus_vec = struct2array(inbus);
                inbus_vec = inbus_vec(obj.inputMap); 
            else
                inbus_vec = inbus;
            end
            real_val_out = inbus_vec;
            
            % Write data
            obj.proc.write( ...
                mlepEncodeRealData(obj.proc.versionProtocol, 0, obj.getCurrentTime, real_val_out));
        
        end
        
        function releaseImpl(obj)
            % Release resources, such as file handles
            % Stop the process            
            obj.proc.stop;            
        end
    end
    
    methods(Access = private)
        function createBusObjects(obj)
            % Create inbus
            bus = Simulink.Bus;            
            for i = 1:obj.nOutIdf                
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
            for i = 1:obj.nInIdf                
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
            error(msg, varargin{:});            
        end
    end
    
%% ========================= Get/Set methods ==============================
    methods 
       function value = get.nInIdf(obj)
           value = numel(obj.proc.idfdata.inputList);
       end
       
       function value = get.inputSigName(obj)  
            value = cell(obj.nInIdf,1);
            for i = 1: obj.nInIdf
                signame = obj.sigNameFcn(obj.proc.idfdata.inputList(i).Name,...
                        obj.proc.idfdata.inputList(i).Type); 
                value{i} = signame;
            end
       end 
       
       function value = get.nOutIdf(obj)
           value = numel(obj.proc.idfdata.outputList);
       end
       
       function value = get.outputSigName(obj)
            obj.nOutIdf = numel(obj.proc.idfdata.outputList);
            value = cell(obj.nOutIdf,1);
            for i = 1: obj.nOutIdf
                signame = obj.sigNameFcn(obj.proc.idfdata.outputList(i).Name,...
                        obj.proc.idfdata.outputList(i).Type); 
                value{i} = signame;
            end            
       end
    end
    
%% ======================= Simulink I/O methods ===========================
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
            out3 = obj.outputBusName;
        end

        function [out,out2,out3] = isOutputFixedSizeImpl(obj)
            % Return true for each output port with fixed size
            out = true;
            out2 = true;
            out3 = true;
        end
        
        function [out,out2,out3] = getOutputSizeImpl(obj)
            % Return size for each output port
            out = [1 1];
            out2 = [1 1];
            out3 = [1 1];
        end
        
        function [out,out2,out3] = isOutputComplexImpl(obj)
            % Return true for each output port with complex data
            out = false;
            out2 = false;
            out3 = false;
        end

        function sts = getSampleTimeImpl(obj)    
            samplingTime = obj.proc.timestep;
            sts = obj.createSampleTime("Type", "Discrete", ...
                 "SampleTime", samplingTime);
        end
    end

%% ================ Simulink Block Graphics Specification =================
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
        function header = getHeaderImpl
            % Define header panel for System block dialog
            header = matlab.system.display.Header(mfilename("class"));
        end

        function group = getPropertyGroupsImpl
            % Define property section(s) for System block dialog
            group = matlab.system.display.Section(mfilename("class"));
        end
    end
end