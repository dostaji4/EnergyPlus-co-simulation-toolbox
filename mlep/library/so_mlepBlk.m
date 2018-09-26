classdef so_mlepBlk < matlab.System & matlab.system.mixin.SampleTime & matlab.system.mixin.Propagates
    %EnergyPlus co-simulation block for Simulink.
    
    % Public, tunable properties
    properties
        
    end
    
    properties(DiscreteState)
        
    end
    
    properties(Nontunable)        
        idfFile; %Specify IDF file
        epwFile; %Specify EPW file         
        inputBusName = 'so_mlep_inbus';  %Input bus name
        outputBusName = 'so_mlep_outbus'; %Output bus name
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
    
    methods
        function obj = so_mlepBlk(varargin)
            % Support name-value pair arguments when constructing object
            setProperties(obj,nargin,varargin{:})
        end
    end

    methods(Access = protected)
        function setupImpl(obj)
            % Perform one-time calculations, such as computing constants            
             if ~obj.proc.isRunning
                 obj.proc.start;                
            end
        end
        
        function [flag, time, outbus] = stepImpl(obj,inbus)
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
                obj.stopError('EnergyPlus process sent flag "%d".',flag);                
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
            inbus_vec = struct2array(inbus);
            real_val_out = inbus_vec(obj.inputMap);
            
            % Write data
            obj.proc.write( ...
                mlepEncodeRealData(obj.proc.versionProtocol, 0, obj.getCurrentTime, real_val_out));
        
        end
        
        function resetImpl(obj)
            % Initialize / reset discrete-state properties
        end
        
        function releaseImpl(obj)
            % Release resources, such as file handles
            % Stop the running process            
            obj.proc.stop;            
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
            err_str = 'Bus with valid signal names is expected at input.';
            assert(isstruct(inbus),err_str);
            inbusSignals = fieldnames(inbus);
            
            for i = 1:obj.nInIdf
                idx = contains(inbusSignals,obj.inputSigName{i});
                if ~any(idx) % more then one occurence should not be present               
                    obj.stopError('Signal "%s" not found in the input bus. Expecting these signals \n"%s".',...
                        obj.inputSigName{i},...
                        strjoin(obj.inputSigName,'",\n"'));                
                else
                    obj.inputMap(i) = find(idx); % Save inbus to EP mapping
                end
            end
        end

        function flag = isInputSizeMutableImpl(obj,index)
            % Return false if input size cannot change
            % between calls to the System object
            flag = false;
        end

        function flag = isInputComplexityMutableImpl(obj,index)
            % Return false if input complexity cannot change
            % between calls to the System object
            flag = false;
        end

        function flag = isInputDataTypeMutableImpl(obj,index)
            % Return false if input data type cannot change
            % between calls to the System object
            flag = false;
        end

        function num = getNumInputsImpl(obj)
            % Define total number of inputs for system with optional inputs
            num = 1;            
        end

        function num = getNumOutputsImpl(obj)
            % Define total number of outputs for system with optional
            % outputs
            num = 3;            
        end

        function [out,out2,out3] = getOutputSizeImpl(obj)
            % Return size for each output port
            out = [1 1];
            out2 = [1 1];
            out3 = [1 1];
        end

        function [flag,time,outbus] = getOutputDataTypeImpl(obj)
            % Return data type for each output port
            flag = "double";
            time = "double";                        
            outbus = obj.outputBusName;
        end

        function [out,out2,out3] = isOutputComplexImpl(obj)
            % Return true for each output port with complex data
            out = false;
            out2 = false;
            out3 = false;

            % Example: inherit complexity from first input port
            % out = propagatedInputComplexity(obj,1);
        end

        function [out,out2,out3] = isOutputFixedSizeImpl(obj)
            % Return true for each output port with fixed size
            out = true;
            out2 = true;
            out3 = true;
        end
        
        function stopError(obj, msg, varargin)
            obj.proc.stop;
            error(msg, varargin{:});            
        end
        
        function sts = getSampleTimeImpl(obj)    
            samplingTime = obj.proc.timestep;
            sts = obj.createSampleTime("Type", "Discrete", ...
                 "SampleTime", samplingTime);
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
    end
    
    % Get/Set methods
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
end