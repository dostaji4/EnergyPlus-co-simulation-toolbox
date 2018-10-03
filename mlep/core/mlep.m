classdef mlep < handle
    %mlep A class of a cosimulation process
    %   The class represents a co-simulation process. It enables data
    %   exchanges between the host (in Matlab) and the client (the
    %   EnergyPlus process), using the communication protocol defined in
    %   BCVTB.
    %
    % (C)   2009-2013 by Truong Nghiem(truong@seas.upenn.edu)
    %       2010-2015 by Willy Bernal(Willy.BernalHeredia@nrel.gov)
    %       2018      by Jiri Dostal (jiri.dostal@cvut.cz)
    
    
    % Last update: 2018-10-01   Jiri Dostal (jiri.dostal@cvut.cz)
    
    % HISTORY:
    %   2015-07-30  Standalone mlep (Willy Bernal)
    %   2013-07-22  Split Start and Socket Accept Functions.
    %   2011-07-13  Added global settings and execution command selection.
    %   2011-04-28  Changed to use Java process for running E+.
    %   2010-11-23  Changed to protocol version 2.
    
    properties
        versionProtocol = 2;  % Current version of the protocol
        program;
        env;
        arguments = {}; % Arguments to the client program
        workDir = '.';   % Working directory (default is current directory)
        outputDir = 'eplusout'; % EnergyPlus output directory (created under working folder)
        outputDirFullPath;
        epDir;          % EnergyPlus directory
        epProgram = 'energyplus'; % EnergyPlus executable
        port = 0;       % Socket port (default 0 = any free port)
        host = '';      % Host name (default '' = localhost)
        bcvtbDir;       % Directory to BCVTB (default '' means that if
        % no environment variable exist, set it to current
        % directory)
        configFile = 'socket.cfg';  % Name of socket configuration file
        variablesFile = 'variables.cfg'; % Contains ExternalInterface settings
        iddFile = 'Energy+.idd'; % IDD file
        idfFile = 'in.idf'; % Building specification IDF file (E+ default by default)
        epwFile = 'in.epw'; % Weather profile EPW file (E+ default by default)
        % for the first time and when server
        % socket changes.
        acceptTimeout = 6000;  % Timeout for waiting for the client to connect        
        execcmd;        % How to execute EnergyPlus from Matlab (system/Java)
        status = 0;
        verboseEP = true; % Print standard output of the E+ process into Matlab
        versionEnergyPlus = ''; % EnergyPlus version found
        msg = '';
        timestep;       %[s] Timestep specified in the IDF file (Co-simulation timestep must adhere to this value)
        checkAndKillExistingEPprocesses = 1;    % If selected, mlep will check on startup for other energyplus processes and kill them
    end
    
    properties (Hidden)
        initialized = false;    % Initialization flag
    end
    
    properties (SetAccess=private, GetAccess=public)
        rwTimeout = 10000;  % Timeout for sending/receiving data (0 = infinite)        
        isRunning = false;  % Is co-simulation running?
        serverSocket = [];  % Server socket to listen to client
        commSocket = [];    % Socket for sending/receiving data
        writer;             % Buffered writer stream
        reader;             % Buffered reader stream
        process = [];       % Process object for E+
        idfData = [];       % Structure with data from parsed IDF
        inputTable;         % Table of inputs to EnergyPlus
        outputTable;        % Table of outputs from EnergyPlus
        idfFullFilename;
        epwFullFilename;
        iddFullFilename;
        varFullFilename;
        isUserVarFile;      % True if user-defined variables.cfg file is present
    end
    
    properties (Constant, GetAccess = private)
        CRChar = newline;      % Defined marker by the BCVTB protocol (newline = char(10))
        file_not_found_str = 'Could not find "%s" file. Please correct the file path or make sure it is on the Matlab search path.';
    end
    
    %% =========================== MLEP ===================================
    methods
        function obj = mlep
            default(obj);
        end
        
        function initialize(obj)
            if obj.initialized
                return
            end
            % Check parameters
            if isempty(obj.program)
                error('Program name must be specified.');
            end
            
            % Assert files availability
            assert(exist(obj.iddFile,'file')>0,obj.file_not_found_str,obj.iddFile);
            obj.iddFullFilename = which(obj.iddFile);
            obj.idfFullFilename = which(obj.idfFile);
            obj.epwFullFilename = which(obj.epwFile);
            
            % Load IDF file
            obj.loadIdf;            
                        
            % Check IDF version 
            obj.versionEnergyPlus = mlep.getEPversion(obj.iddFullFilename);        
            if ~strcmp(obj.versionEnergyPlus,obj.idfData.version{1})
                warning('IDF file of version "%s" is being simulated by EnergyPlus of version "%s".',obj.idfData.version{1}, obj.versionEnergyPlus);
            end
            
            % Check for possible hanging EP processes
            if obj.checkAndKillExistingEPprocesses
                mlep.killProcess(obj.epProgram);
            end
            
            % Create E+ output folder
            obj.cleanEP(obj.workDir);
            obj.outputDirFullPath = fullfile(obj.workDir,obj.outputDir);
            [st,ms] = mkdir(obj.outputDirFullPath);
            assert(st,'%s',ms);
            
            % Determine co-simulation inputs and outputs out of IDF or
            % varibles.cfg files
            idfDir = fileparts(obj.idfFullFilename);
            obj.varFullFilename = fullfile(idfDir, obj.variablesFile);
            obj.isUserVarFile = (exist(obj.varFullFilename,'file') == 2);
            
            if obj.isUserVarFile
                [obj.inputTable, ...
                 obj.outputTable] = mlep.parseVariablesConfigFile(obj.varFullFilename);                
            else
                % Use all the inputs and outputs from IDF
                obj.inputTable = obj.idfData.inputTable;
                obj.outputTable = obj.idfData.outputTable;
            end
            
            % Check I/O configuration
            obj.checkIO;            
            
            % Create or copy ExternalInterface variable configuration file
            obj.makeVariablesConfigFile;
            
            % Stop further initializations
            obj.initialized = true;
        end
        
        function start(obj)
            % status and msg are returned from the client process
            % status = 0 --> success
            if obj.isRunning, return; end
            
            % Initialize
            obj.initialize;
            
            % Save current directory and change directory if necessary
            changeDir = ~strcmp(obj.workDir,'.');
            if changeDir
                runDir = cd(obj.workDir);
            else
                runDir = pwd;
            end
            
            try
                % Create server socket if necessary
                obj.makeSocket;                                   
                % Run the EnergyPlus process
                obj.runEP;
                
            catch ErrObj
                obj.closeSocket;
                if changeDir
                    cd(runDir);
                end
                rethrow(ErrObj);
            end
            
            % Revert current folder
            if changeDir
                cd(runDir);
            end
        end
        
        function stop(obj, stopSignal)
            if ~obj.isRunning, return; end
            
            % Send stop signal
            if nargin < 2 || stopSignal
                obj.write(mlepEncodeStatus(obj.versionProtocol, 1));
            end
            
            % Close connection
            obj.closeSocket;
            
            % Destroy process E+
            if isa(obj.process, 'processManager') && obj.process.running
                obj.process.stop;
            end
            
            obj.isRunning = false;
            obj.initialized = false;
        end
        
        function delete(obj)
            if obj.isRunning
                obj.stop;
            end
            
            % Close server socket
            if isjava(obj.serverSocket)
                obj.serverSocket.close;
                obj.serverSocket = [];
            end
        end

        function default(obj)
            % Obtain default settings from the global variable MLEPSETTINGS
            % If that variable does not exist, assign default values to
            % settings.
            global MLEPSETTINGS
            
            noSettings = isempty(MLEPSETTINGS) || ~isstruct(MLEPSETTINGS);
            if noSettings
                % Try to run mlepInit
                if exist('installMlep', 'file') == 2
                    % Run installation script
                    installMlep;
                    noSettings = isempty(MLEPSETTINGS) || ~isstruct(MLEPSETTINGS);
                end                
                assert(~noSettings,'Error loading mlep settings: Load MLEPSETTINGS.mat or run installMlep.m again.');
            end
            
            if noSettings || ~isfield(MLEPSETTINGS, 'version')
                obj.versionProtocol = 2;    % Current version of the protocol
            else
                obj.versionProtocol = MLEPSETTINGS.version;
            end
            
            if noSettings || ~isfield(MLEPSETTINGS, 'program')
                obj.program = '';
            else
                obj.program = MLEPSETTINGS.program;
            end
            
            if noSettings || ~isfield(MLEPSETTINGS, 'bcvtbDir')
                obj.bcvtbDir = '';
            else
                obj.bcvtbDir = MLEPSETTINGS.bcvtbDir;
            end
            
            if noSettings || ~isfield(MLEPSETTINGS, 'env')
                obj.env = {};
            else
                obj.env = MLEPSETTINGS.env;
            end
            
            if noSettings || ~isfield(MLEPSETTINGS, 'execcmd')
                obj.execcmd = '';
            else
                obj.execcmd = MLEPSETTINGS.execcmd;
            end
        end
    end
    
    % ---------------------- Get/Set methods ------------------------------
    methods
        
        function value = get.epDir(obj)
            if exist(obj.iddFile,'file')
                value = fileparts(which(obj.iddFile));
            else
                error('EnergyPlus directory not found. Please make sure it is on the search path.');
            end
        end
        
        function set.idfFile(obj, file)
            assert(~isempty(file),'IDF file not specified.');
            assert(ischar(file) || isstring(file),'Invalid file name.');
            if strlength(file)<4 || ~strcmpi(file(end-3:end), '.idf')
                file = [file '.idf']; %add extension
            end
            assert(exist(file,'file')>0,obj.file_not_found_str,file);
            obj.idfFile = file;
        end
        
        function set.epwFile(obj,file)
            assert(~isempty(file),'EPW file not specified.');
            assert(ischar(file) || isstring(file),'Invalid file name.');
            if strlength(file)<4 || ~strcmpi(file(end-3:end), '.epw')
                file = [file '.epw'];
            end
            assert(exist(file,'file')>0,obj.file_not_found_str,file);
            obj.epwFile = file;
        end
    end
    
    %% ======================== EnergyPlus ================================
    methods (Access = private)
        
        % Run the EnergyPlus process
        function runEP(obj)
            env_ = obj.env;
            
            % Set BCVTB_HOME environment
            if ~isempty(obj.bcvtbDir)
                env_ = [env_, {{'BCVTB_HOME', obj.bcvtbDir}}];
            else
                env_ = [env_, {{'BCVTB_HOME', pwd}}];
            end
            
            % Set local environment
            for i = 1:numel(env_)
                setenv(env_{i}{1}, env_{i}{2});
            end
            
            %% Create the EnergyPlus co-simulatin process
            [~,idfName] = fileparts(obj.idfFile);
            
            % Create the external E+ process
            
            % Prepare EP command
            epcmd = javaArray('java.lang.String',11);
            epcmd(1) = java.lang.String(fullfile(obj.epDir,obj.epProgram));
            epcmd(2) = java.lang.String('-w'); % weather file
            epcmd(3) = java.lang.String(obj.epwFullFilename);
            epcmd(4) = java.lang.String('-i'); % IDD file
            epcmd(5) = java.lang.String(obj.iddFullFilename);
            epcmd(6) = java.lang.String('-x'); % expand objects
            epcmd(7) = java.lang.String('-p'); % output prefix
            epcmd(8) = java.lang.String(idfName);
            epcmd(9) = java.lang.String('-s'); % output suffix
            epcmd(10) = java.lang.String('D'); % Dash style "prefix-suffix"
            epcmd(11) = java.lang.String(obj.idfFullFilename); % IDF file
            
            epproc = processManager('command',epcmd,...
                'printStdout',obj.verboseEP,...
                'printStderr',obj.verboseEP,...
                'keepStdout',~obj.verboseEP,...
                'keepStderr',~obj.verboseEP,...
                'autoStart', false,... % start process by .start
                'id','EP');     % process ID (also sets stdout prefix)
            epproc.workingDir = obj.outputDirFullPath;
            addlistener(epproc.state,'exit',@epProcListener);
            epproc.start();
            
            if ~epproc.running
                error('Error while starting external co-simulation program.');
            else
                obj.process = epproc;
            end
            
            function epProcListener(src,data)
                fprintf('\n');
                fprintf('%s: Process exited with exitValue = %g\n',src.id,src.exitValue);
                
                if src.exitValue ~= 1
                    fprintf('Event name %s\n',data.EventName);
                    fprintf('\n');
                    if ~isempty(src.stdout)
                        fprintf('StdOut of the process:\n\n');
                        processManager.printStream(src.stdout,'StdOut',80);
                    end
                    if ~isempty(src.stderr)
                        fprintf('StdErr of the process:\n\n');
                        processManager.printStream(src.stdout,'StdErr',80);
                    end
                end
                
            end
        end
        
        % Load I/O variables from the IDF file
        function loadIdf(obj)
            %% COLLECT DATA IDF FILE
            in = mlepReadIDF(obj.idfFullFilename,...
                {'Timestep',...
                'RunPeriod',...
                'ExternalInterface:Schedule',...
                'ExternalInterface:Actuator',...
                'ExternalInterface:Variable',...
                'Output:Variable',...
                'Version'});
            obj.idfData.timeStep = str2double(char(in(1).fields{1}));
            obj.timestep = 60/obj.idfData.timeStep * 60; %[s];
            obj.idfData.runPeriod = (str2double(char(in(2).fields{1}(4))) - str2double(char(in(2).fields{1}(2))))*31 + 1 + str2double(char(in(2).fields{1}(5))) - str2double(char(in(2).fields{1}(3)));
            obj.idfData.schedule = in(3).fields;
            obj.idfData.actuator = in(4).fields;
            obj.idfData.variable = in(5).fields;
            obj.idfData.output = in(6).fields;
            obj.idfData.version = in(7).fields;
            
            % List Schedules
            obj.idfData.inputTable = table('Size',[0 2],'VariableTypes',{'string','string'},'VariableNames',{'Name','Type'});
            for i = 1:size(obj.idfData.schedule,2)
                if ~size(obj.idfData.schedule,1)
                    break;
                end
                obj.idfData.inputTable(i,:) = {'schedule',...                % Name
                                                obj.idfData.schedule{i}{1}}; % Type
            end
            
            % List Actuators
            cInput = height(obj.idfData.inputTable);
            for i = 1:size(obj.idfData.actuator,2)
                if ~size(obj.idfData.actuator,1)
                    break;
                end
                obj.idfData.inputTable(cInput+i) = {'actuator',...           % Name
                                                obj.idfData.actuator{i}{1}}; % Tyoe
            end
            
            % List Variable
            cInput = height(obj.idfData.inputTable);
            for i = 1:size(obj.idfData.variable,2)
                if ~size(obj.idfData.variable,1)
                    break;
                end
                obj.idfData.inputTable(cInput+i) = {'variable',...           % Name
                                                obj.idfData.actuator{i}{1}}; % Type
            end
            
            % List Outputs
            obj.idfData.outputTable = table('Size',[0 3],'VariableTypes',{'string','string','string'},'VariableNames',{'Name','Type','Period'});
            for i = 1:size(obj.idfData.output,2)                    
                obj.idfData.outputTable(i,:) = {obj.idfData.output{i}{1}, ... % Name
                                                obj.idfData.output{i}{2}, ... % Type
                                                obj.idfData.output{i}{3}};    % Period
            end
        end
        
        % Create a variable.cfg config file or reuse user-defined one
        function makeVariablesConfigFile(obj)
            % If there is a variable.cfg in the same directory as the IDF file,
            % then use it (copy it into the outputFolder for E+ to use).
            % Otherwise, create a new one based on the inputs and outputs
            % defined in the IDF file.
            
            if obj.isUserVarFile
                assert(exist(obj.varFullFilename,'file')==2,obj.file_not_found_str,obj.varFullFilename);
                % Copy variables.cfg to the output directory (= working dir for EP)
                if ~copyfile(obj.varFullFilename, obj.outputDirFullPath)
                    error('Cannot copy "%s" to "%s".', obj.varFullFilename, obj.outputDirFullPath);
                end
                newVarFullFilename = fullfile(obj.outputDirFullPath, obj.variablesFile);
                % Add disclamer to the copied variables.cfg file
                S = fileread(newVarFullFilename);
                disclaimer = [newline '<!--' newline,...
                    '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' newline,...
                    'THIS IS A FILE COPY.' newline,...
                    'DO NOT EDIT THIS FILE AS ANY CHANGES WILL BE OVERWRITTEN!' newline,...
                    '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' newline,...
                    '-->' newline];
                anchor = '<BCVTB-variables>';
                [~,e] = regexp(S,anchor);
                if isempty(e), error('Parsing of "%s" failed. Please check the file.',obj.variablesFile);
                else
                    S = [S(1:e), disclaimer, S(e+1:end)];
                end
                FID = fopen(newVarFullFilename, 'w');
                if FID == -1, error('Cannot open file "%s".', newVarFullFilename); end
                fwrite(FID, S, 'char');
                fclose(FID);
            else
                % Create a new 'variables.cfg' file based on the input/output
                % definition in the IDF file
                
                mlepWriteVariableConfig(obj.inputTable,...
                    obj.outputTable,...
                    fullfile(obj.outputDirFullPath, obj.variablesFile));
                
            end
        end
        
        % Check input/output configuration
        function checkIO(obj)
            
            % Check variables.cfg config for wrong entries
            assert(~isempty(obj.inputTable) && ~isempty(obj.outputTable), 'Run parsing of the variables.cfg file first.');
            chk = ismember(obj.inputTable,obj.idfData.inputTable);
            assert(all(chk),'The following inputs to EnergyPlus (ExternalInterface) are defined in the "variables.cfg file, but are missing in the IDF file:\n%s ',...
                evalc('disp(obj.inputTable(~chk,:))'));
            chk = ismember(obj.outputTable,obj.idfData.outputTable);
            assert(all(chk),'The following inputs to EnergyPlus (ExternalInterface) are defined in the "variables.cfg file, but are missing in the IDF file:\n%s ',...
                evalc('disp(obj.outputTable(~chk,:))'));
            
            % Check i/o tables for duplicates
            [obj.inputTable,ia] = unique(obj.inputTable,'rows','stable');
            dupl = setdiff(1:height(obj.inputTable),ia);
            if ~isempty(dupl)
                warning('Omitting the following duplicate input entries:\n%s ',...
                    evalc('disp(obj.inputTable(dupl,:))'));
            end
            [obj.outputTable,ia] = unique(obj.outputTable,'rows','stable');
            dupl = setdiff(1:height(obj.outputTable),ia);
            if ~isempty(dupl)
                warning('IDF file: Omitting the following duplicate output entries:\n%s ',...
                    evalc('disp(obj.outputTable(dupl,:))'));
            end
            
            % Check Outputs for asterisks
            chk = contains(obj.outputTable.Name,'*');
            if any(chk)
               error('IDF file: Ambiguous "*" key value detected in the following entries:\n%sPlease specify the key value exactly (using "Environment", zone name, surface name, etc.).',...
                   evalc('disp(obj.outputTable(chk,:))'));
            end
            
            % Check Outputs for reporting frequency other then 
            chk = contains(obj.outputTable.Period,'timestep','IgnoreCase',true);
            if any(~chk)                
                warning('IDF file: Omitting the following output varibles with reporting frequency other then "timestep":\n%s ',...                    
                    evalc('disp(obj.outputTable(~chk,:))'));
                obj.outputTable = obj.outputTable(chk,:);
            end
        end
        
        % Delete files from the previous simulation
        function cleanEP(obj, rootDir)
            % Remove "outputDir" from the rootDir folder
            if strcmp(rootDir,'.')
                rootDir = pwd;
            end
            dirname = fullfile(rootDir,obj.outputDir);
            if exist(dirname,'dir')
                mlep.rmdirR(dirname);
            end
        end
    end
    
    methods (Access = private, Static)
        % Parse variables.cfg file for desired I/O
        function [inputTable, outputTable] = parseVariablesConfigFile(file)
            assert(exist(file,'file') > 0,'File "%s" not found.');
            
            inputTable = table('Size',[0 2],'VariableTypes',{'string','string'},'VariableNames',{'Name','Type'});
            cInput = 1;
            outputTable = table('Size',[0 2],'VariableTypes',{'string','string'},'VariableNames',{'Name','Type'});
            cOutput = 1;
            
            % Start parsing
            s = xml2struct(file); %modified version of xml2struct allowing for not checking the .dtd file
            s = struct2cell(s);
            vars = s{1}{2}.variable;            
            for i = 1:numel(vars)
                switch vars{i}.Attributes.source
                    % Output from E+
                    case 'EnergyPlus' 
                        out = vars{i}.EnergyPlus.Attributes;
                        assert(isfield(out,'name') && isfield(out,'type'),'Fields "name" and/or "type" are not existing');
                        outputTable(cOutput,:) = {out.name, out.type};
                        cOutput = cOutput + 1;
                        
                    % Input to E+
                    case 'Ptolemy' 
                        name = fieldnames(vars{i}.EnergyPlus.Attributes);
                        assert(any(contains({'schedule','variable','actuator'},name)),...
                            'Unknown variable name "%s".',name);
                        inputTable(cInput,:) = {name{1}, vars{i}.EnergyPlus.Attributes.(name{1})};                        
                        cInput = cInput + 1;
                    
                    % Error
                    otherwise
                        error('Unknown varible source "%s".',vars{i}.Attributes.source)
                end
            end
        end
        
        % Get EnergyPlus version out of Energy+.idd file
        function [ver, minor] = getEPversion(iddFullpath)
            % Parse EnergyPlus version out of Energy+.idd file
            assert(exist(iddFullpath,'file')>0,'Could not find "%s" file. Please correct the file path or make sure it is on the Matlab search path.',iddFullpath);
            % Read file
            fid = fopen(iddFullpath);
            if fid == -1, error('Cannot open file "%s".', iddFullpath); end
            str = fread(fid,100,'*char')';
            fclose(fid);
            % Parse the string
            expr = '(?>^!IDD_Version\s+|\G)(\d{1}\.\d{1}|\G)\.(\d+)';
            tokens = regexp(str,expr,'tokens');
            assert(~isempty(tokens)&&size(tokens{1},2)==2,' Error while parsing "%s" for EnergyPlus version',iddFullpath);
            ver = tokens{1}{1};
            minor = tokens{1}{2};
        end
        
        % Helper function for killing processes identified by name
        function killProcess(name)
            p = System.Diagnostics.Process.GetProcessesByName(name);
            for i = 1:p.Length
                try
                    dt = p(i).StartTime.Now - p(i).StartTime;
                    warning('Found process "%s", ID = %d, started %d minutes ago. Terminating the process.',name, p(i).Id, dt.Minutes);
                    p(i).Kill();
                    p(i).WaitForExit(100);
                catch
                    warning('Couldn''t kill process "%s" with ID = %d.',name,p(i).Id);
                    % process was terminating or can't be terminated - deal with it
                    % process has already exited - might be able to let this one go
                end
            end
        end
        
        % Helper function for recursive rmdir
        function rmdirR(dirname)
            % Remove foldert recursively (with all files beneath)
            delete(fullfile(dirname,'*'));
            st = rmdir(dirname);
            assert(st,'Could not delete folder "%s".',dirname);
        end
    end
    
    methods (Access = public, Static)
        % Translate flag number into a human readable string
        function str = epFlag2str(flag)
            % Flag	Description
            % +1	Simulation reached end time.
            % 0	    Normal operation.
            % -1	Simulation terminated due to an unspecified error.
            % -10	Simulation terminated due to an error during the initialization.
            % -20	Simulation terminated due to an error during the time integration.
            switch flag
                case 1
                    str = 'Simulation reached end time. If this is not intended, extend the simulation period in the IDF file';
                case 0
                    str = 'Normal operation';
                case -1
                    str = 'Simulation terminated due to an unspecified runtime error';
                case -10
                    str = 'Simulation terminated due to an error during initialization';
                case -20
                    str = 'Simulation terminated due to an error during the time integration';
                otherwise
                    str = sprintf('Unknown flag "%d".',flag);
            end
        end
    end
    
    %% ======================= Communication ==============================
    methods
        % Create or reuse java socket
        function makeSocket(obj)
            if isempty(obj.serverSocket) || ...
                    (~isempty(obj.serverSocket) && obj.serverSocket.isClosed)
                % If any error happens, this function will be interrupted
                if ~isempty(obj.host)
                    serversock = java.net.ServerSocket(obj.port, 0, obj.host);
                    hostname = obj.host;
                else
                    serversock = java.net.ServerSocket(obj.port);
                    
                    % The following get local host address for incoming connections even
                    % from outside, but it seems unstable, sometimes E+ cannot connect.
                    % hostname = char(getHostName(java.net.InetAddress.getLocalHost));
                    
                    % The following get address that can only be used locally on this
                    % machine, no connections from outside. It may be more stable.
                    hostname = char(getHostName(javaMethod('getLocalHost', 'java.net.InetAddress')));
                    %hostname = char(getHostAddress(serversock.getInetAddress));
                end
                obj.serverSocket = serversock;
            else
                hostname = char(getHostName(javaMethod('getLocalHost', 'java.net.InetAddress')));
                %hostname = char(getHostAddress(serversock.getInetAddress));
            end
            
            % Set accept timeout
            obj.serverSocket.setSoTimeout(obj.acceptTimeout);
            
            % Write socket config file
            mlepWriteSocketConfig(fullfile(obj.outputDirFullPath,obj.configFile),obj.serverSocket, hostname);
            
            obj.commSocket = [];
        end
        
        % Establish connection by accepting socket
        function acceptSocket(obj)
            assert(obj.initialized, 'Initialize the object first.');
            % Accept Socket
            obj.commSocket = obj.serverSocket.accept;
            
            % Create Streams            
            if isjava(obj.commSocket)
                % Create writer and reader                
                if obj.rwTimeout ~= 0
                    obj.commSocket.setSoTimeout(obj.rwTimeout);
                end
                obj.createStreams;
                obj.isRunning = true;                
            else
                error('Could not establish socket connection. Check that the EnergyPlus process is running and socket configuration.');
            end            
        end
        
        % Read from socket
        function packet = read(obj)
            if obj.isRunning
                packet = char(readLine(obj.reader));
%                 packet = char(readLine(java.io.BufferedReader(java.io.InputStreamReader(obj.commSocket.getInputStream))));
            else
                error('Co-simulation is not running.');
            end
        end
        
        % Write to socket
        function write(obj, packet)
            if obj.isRunning
%                 wr = java.io.BufferedWriter(java.io.OutputStreamWriter(obj.commSocket.getOutputStream));
%                 wr.write(sprintf('%s\n', packet));
%                 wr.flush;
                assert(numel(packet) < 21621);
                obj.writer.write([packet mlep.CRChar]);
                obj.writer.flush;
            else
                error('Co-simulation is not running.');
            end
        end
        
        % Communication timeout
        function setRWTimeout(obj, value)
            if value < 0, value = 0; end
            obj.rwTimeout = value;
            if isjava(obj.commSocket)
                obj.commSocket.setSoTimeout(value);
                obj.createStreams;  % Recreate reader and writer streams
            end
        end
        
        % Feed a sequence of input to the simulation
        function [status, TOut, ROut, IOut, BOut] = feedInputs(obj,...
                TInputs, RInputs, IInputs, BInputs)
            % Runs simulation with sequences of inputs, and returns outputs
            % The process will be started if it is not running, and it will
            % not be stopped when this function returns.
            % status: 0 if successful, 1 if the client terminates before
            %       all inputs are fed, -1 if other errors.
            % TInputs and TOut are vectors of input & output time instants.
            % All input and output sequences are matrices where each row
            % contains input/output data for one time instant, each column
            % corresponds to an input/output signal. R*, I*, B* are for
            % real, integer, boolean signals respectively.
            %
            % This function does not check for validity of arguments, so
            % take appropriate caution.
            
            if nargin < 5
                error('Not enough parameters.');
            end
            
            ROut = [];
            IOut = [];
            BOut = [];
            status = 0;
            
            nRuns = length(TInputs);
            if nRuns < 1
                disp('nRuns is zero.');
                status = -1;
                return;
            end
            
            TOut = nan(nRuns, 1);
            
            if ~obj.isRunning
                obj.start;
                if ~obj.isRunning
                    disp('Cannot start the simulation process.');
                    status = -1;
                    return;
                end
            end
            
            if isempty(RInputs), RInputs = zeros(nRuns, 0); end
            if isempty(IInputs), IInputs = zeros(nRuns, 0); end
            if isempty(BInputs), BInputs = zeros(nRuns, 0); end
            
            % Run the first time to obtain the size of outputs
            obj.write(mlepEncodeData(obj.versionProtocol, 0, TInputs(1),...
                RInputs(1,:), IInputs(1,:), BInputs(1,:)));
            
            readpacket = obj.read;
            
            if isempty(readpacket)
                disp('Cannot read first input packets.');
                status = -1;
                return;
            else
                [flag, timevalue, rvalues, ivalues, bvalues] = mlepDecodePacket(readpacket);
                switch flag
                    case 0
                        TOut(1) = timevalue;
                        
                        ROut = nan(nRuns, length(rvalues)); ROut(1,:) = rvalues;
                        IOut = nan(nRuns, length(ivalues)); IOut(1,:) = ivalues;
                        BOut = nan(nRuns, length(bvalues)); BOut(1,:) = bvalues;
                    case 1
                        obj.stop(false);
                        status = 1;
                        return;
                    otherwise
                        fprintf('Error from E+ with flag %d.\n', flag);
                        obj.stop(false);
                        status = -1;
                        return;
                end
            end
            
            for kRun = 2:nRuns
                fprintf('Run %d at time %g with U = %g.\n', kRun, TInputs(kRun), RInputs(kRun,:));
                obj.write(mlepEncodeData(obj.versionProtocol, 0, TInputs(kRun),...
                    RInputs(kRun,:), IInputs(kRun,:), BInputs(kRun,:)));
                
                % Try to read a number of times (there is some problem with
                % TCP connection).
                nTrials = 0;
                while nTrials < 10
                    readpacket = obj.read;
                    if isempty(readpacket)
                        nTrials = nTrials + 1;
                    else
                        break;
                    end
                end
                
                if isempty(readpacket)
                    disp('Cannot read input packets.');
                    status = -1;
                    break;
                else
                    [flag, timevalue, rvalues, ivalues, bvalues] = mlepDecodePacket(readpacket);
                    switch flag
                        case 0
                            TOut(kRun) = timevalue;
                            ROut(kRun,:) = rvalues;
                            IOut(kRun,:) = ivalues;
                            BOut(kRun,:) = bvalues;
                        case 1
                            obj.stop(false);
                            status = 1;
                            break;
                        otherwise
                            fprintf('Error from E+ with flag %d.\n', flag);
                            obj.stop(false);
                            status = -1;
                            break;
                    end
                end
            end
        end
    end
    
    methods (Access = private)
        % Close socket connection
        function closeSocket(obj)
            % Close serverSocket
            if isjava(obj.serverSocket)
                obj.serverSocket.close();
            end
            
            % Close commSocket
            if isjava(obj.commSocket)
                obj.commSocket.close();
            end
            
            % Close Reader
            if isjava(obj.reader)
                obj.reader.close();
            end
            
            % Close Writer
            if isjava(obj.writer)
                obj.writer.close();
            end
            
            % Delete Java Objects
            obj.reader = [];
            obj.writer = [];
            obj.serverSocket = [];
            obj.commSocket = [];
        end
        
        % Create java i/o streams
        function createStreams(obj)
            obj.writer = java.io.BufferedWriter(java.io.OutputStreamWriter(obj.commSocket.getOutputStream));
            obj.reader = java.io.BufferedReader(java.io.InputStreamReader(obj.commSocket.getInputStream));
        end
    end
  
end

