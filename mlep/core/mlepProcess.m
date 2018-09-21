classdef mlepProcess < handle
    %mlepProcess A class of a cosimulation process
    %   This class represents a co-simulation process. It enables data
    %   exchanges between the host (in Matlab) and the client (the
    %   cosimulation process), using the communication protocol defined in
    %   BCVTB.
    %
    %   This class wraps the mlep* functions.
    %
    %   See also:
    %       <a href="https://gaia.lbl.gov/bcvtb">BCVTB (hyperlink)</a>
    %
    % (C)   2009-2013 by Truong Nghiem(truong@seas.upenn.edu)
    %       2010-2013 by Willy Bernal(Willy.BernalHeredia@nrel.gov)
    
    % Last update: 2015-07-30 by Willy Bernal
    
    % HISTORY:
    %   2013-07-22  Split Start and Socket Accept Functions.
    %   2011-07-13  Added global settings and execution command selection.
    %   2011-04-28  Changed to use Java process for running E+.
    %   2010-11-23  Changed to protocol version 2.
        
    
    properties
        version;        % Current version of the protocol
        program;
        env;
        arguments = {}; % Arguments to the client program
        workDir = '.';   % Working directory (default is current directory)
        outputDir = 'eplusout'; % EnergyPlus output directory (created under working folder)
        port = 0;       % Socket port (default 0 = any free port)
        host = '';      % Host name (default '' = localhost)
        bcvtbDir;       % Directory to BCVTB (default '' means that if
        % no environment variable exist, set it to current
        % directory)
        configFile = 'socket.cfg';  % Name of socket configuration file
        configFileWriteOnce = false;  % if true, only write the socket config file
        variablesFile = 'variables.cfg'; % Contains ExternalInterface settings 
        iddFile = 'Energy+.idd'; % IDD file
        idfFile = 'in.idf'; % Building specification IDF file (E+ default by default)
        epwFile = 'in.epw'; % Weather profile EPW file (E+ default by default)       
        % for the first time and when server
        % socket changes.
        acceptTimeout = 20000;  % Timeout for waiting for the client to connect
        execcmd;        % How to execute EnergyPlus from Matlab (system/Java)
        status = 0;
        verboseEP = true; % Print standard output of the E+ process into Matlab
        msg = '';       
    end
    
    properties (SetAccess=private, GetAccess=public)
        rwTimeout = 0;      % Timeout for sending/receiving data (0 = infinite)
        isRunning = false;  % Is co-simulation running?
        serverSocket = [];  % Server socket to listen to client
        commSocket = [];    % Socket for sending/receiving data
        writer;             % Buffered writer stream
        reader;             % Buffered reader stream        
        process = [];        % Process object for E+
    end
    
    properties (Constant)
        CRChar = sprintf('\n');
    end
    
    methods
        function obj = mlepProcess
            defaultSettings(obj);
        end
        
        function [status, msg] = start(obj)
            % status and msg are returned from the client process
            % status = 0 --> success
            if obj.isRunning, return; end
            
            % Check parameters
            if isempty(obj.program)
                error('Program name must be specified.');
            end
            
            % Call mlepCreate
            try
                if ~isempty(obj.serverSocket)
                    theport = obj.serverSocket;
                    if obj.configFileWriteOnce
                        theConfigFile = -1;  % Do not write socket config file
                    else
                        theConfigFile = obj.configFile;
                    end
                else
                    theport = obj.port;
                    theConfigFile = obj.configFile;
                end
                                
                status = runEP(obj, theport,theConfigFile);
                msg = '';
                
            catch ErrObj
                obj.closeCommSockets;
                rethrow(ErrObj);
            end
        end
        
        function status = runEP(obj, port, configfile)
            
            host_ = obj.host;            
            env_ = obj.env;
            
            ni = nargin;
            if ni < 2 || isempty(port)
                port = 0;  % any port that is free
            end
            if ni < 3 || isempty(configfile)
                configfile = 'socket.cfg';
            end                        
            bWorkDir = ~strcmp(obj.workDir,'.');
            
            % Set BCVTB_HOME environment
            if ~isempty(obj.bcvtbDir)
                env_ = [env_, {{'BCVTB_HOME', obj.bcvtbDir, obj.bcvtbDir}}];  % Always overwrite
            else
                env_ = [env_, {{'BCVTB_HOME', pwd}}];
            end
            
            
            % Save current directory and change directory if necessary                        
            if bWorkDir                 
                oldCurDir = cd(obj.workDir);                
            end            
            
            % Create E+ output folder
            obj.cleanEP(pwd);                                      
            outputDir_ = fullfile(pwd,obj.outputDir);            
            mkdir(outputDir_);                
            
            
            % If port is a ServerSocket java object then re-use it
            if isa(port, 'java.net.ServerSocket')
                if port.isClosed
                    port = 0;   % Create a new socket
                else
                    serversock = port;
                end
            end
            
            % Create server socket if necessary
            if isnumeric(port)
                % If any error happens, this function will be interrupted
                if ni >= 6 && ~isempty(host_)
                    serversock = java.net.ServerSocket(port, 0, host_);
                    hostname = host_;
                else
                    serversock = java.net.ServerSocket(port);
                    
                    % The following get local host address for incoming connections even
                    % from outside, but it seems unstable, sometimes E+ cannot connect.
                    % hostname = char(getHostName(java.net.InetAddress.getLocalHost));
                    
                    % The following get address that can only be used locally on this
                    % machine, no connections from outside. It may be more stable.
                    hostname = char(getHostName(javaMethod('getLocalHost', 'java.net.InetAddress')));
                    %hostname = char(getHostAddress(serversock.getInetAddress));
                end
            else
                hostname = char(getHostName(javaMethod('getLocalHost', 'java.net.InetAddress')));
                %hostname = char(getHostAddress(serversock.getInetAddress));
            end
            
            serversock.setSoTimeout(obj.acceptTimeout);
            
            % Write socket config file if necessary (configfile ~= -1)
            if configfile ~= -1
                fid = fopen(fullfile(outputDir_,configfile), 'w');
                if fid == -1
                    % error
                    serversock.close; serversock = [];
                    error('Error while creating socket config file: %s', ferror(fid));
                end
                
                % Write socket config to file
                socket_config = [...
                    '<?xml version="1.0" encoding="ISO-8859-1"?>\n' ...
                    '<BCVTB-client>\n' ...
                    '<ipc>\n' ...
                    '<socket port="%d" hostname="%s"/>\n' ...
                    '</ipc>\n' ...
                    '</BCVTB-client>'];
                fprintf(fid, socket_config, serversock.getLocalPort, hostname);
                
                [femsg, ferr] = ferror(fid);
                if ferr ~= 0  % Error while writing config file
                    serversock.close; serversock = [];
                    fclose(fid);
                    error('Error while writing socket config file: %s', femsg);
                end
                
                fclose(fid);
            end
            
            % Create the external process
            try
                for kk = 1:numel(env_)
                    setenv(env_{kk}{1}, env_{kk}{2});
                end
                
                
                %% Create the EnergyPlus co-simulatin process
                epdir = fileparts(obj.program);                
                epwFilename = [obj.epwFile, '.epw'];
                idfFilename = [obj.idfFile, '.idf'];                
                
                assert(exist(obj.iddFile,'file')>0,'Could not find "%s" file. Please correct the file path or make sure it is on the Matlab search path.',obj.iddFile);
                assert(exist(obj.variablesFile,'file')>0,'Could not find "%s" file. Please correct the file path or make sure it is on the Matlab search path.',obj.variablesFile);
                assert(exist(epwFilename,'file')>0,'Could not find "%s" file. Please correct the file path or make sure it is on the Matlab search path.',epwFilename);
                assert(exist(idfFilename,'file')>0,'Could not find "%s" file. Please correct the file path or make sure it is on the Matlab search path.',idfFilename);
                
                
                var_file_path = fileparts(which(obj.variablesFile));
                if ~strcmp(var_file_path,pwd)
                    warning('Using "%s" file from outside the current path. Specifically from "%s"',obj.variablesFile,var_file_path);
                end
                
                % Copy variables.cfg to the working directory
                if ~copyfile(which(obj.variablesFile),outputDir_)
                    error('Cannot copy "%s" to "%s".',var_fobj.variablesFileile, outputDir_);
                end
                % Add disclamer to the new variables.cfg file
                copied_var_file = fullfile(outputDir_,obj.variablesFile);
                S = fileread(copied_var_file);                
                disclaimer = ['<!--' newline,...
                    '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' newline,...
                    'THIS IS A FILE COPY.' newline,...
                    'DO NOT EDIT THIS FILE AS ANY CHANGES WILL BE OVERWRITTEN!' newline,...
                    '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' newline,...
                    '-->' newline];
                anchor = '<BCVTB-variables>';
                k = strfind(S,anchor);
                if isempty(k), error('Parsing of "%s" failed. Please check the file',obj.variablesFile); 
                else
                    k = k + numel(anchor);
                    S = [S(1:k), disclaimer, S(k+1:end)];
                end
                FID = fopen(copied_var_file, 'w');
                if FID == -1, error('Cannot open file "%s".', copied_var_file); end                
                fwrite(FID, S, 'char');
                fclose(FID);
                
                % Prepare EP command
                epcmd = javaArray('java.lang.String',11);
                epcmd(1) = java.lang.String([epdir, filesep, 'energyplus']);
                epcmd(2) = java.lang.String('-w'); % weather file
                epcmd(3) = java.lang.String(which(epwFilename));
                epcmd(4) = java.lang.String('-i'); % IDD file
                epcmd(5) = java.lang.String(which(obj.iddFile));
                epcmd(6) = java.lang.String('-x'); % expand objects
                epcmd(7) = java.lang.String('-p'); % output prefix
                epcmd(8) = java.lang.String(obj.idfFile);
                epcmd(9) = java.lang.String('-s'); % output suffix
                epcmd(10) = java.lang.String('D'); % Dash style "prefix-suffix"
                epcmd(11) = java.lang.String(which(idfFilename)); % IDF file
                
                epproc = processManager('command',epcmd,...
                                        'printStdout',obj.verboseEP,...
                                        'printStderr',obj.verboseEP,...
                                        'keepStdout',~obj.verboseEP,...
                                        'keepStderr',~obj.verboseEP,...
                                        'autoStart', false,...                                        
                                        'id','EP');  
                epproc.workingDir = outputDir_;                
                addlistener(epproc.state,'exit',@epProcListener);
                epproc.start();                     
                    
                if ~epproc.running                    
                    error('Error while starting external co-simulation program.');                    
                else
                    obj.process = epproc;
                end
            catch ErrObj
                serversock.close; % serversock = [];
                rethrow(ErrObj);
            end
            
            % Listen for the external program to connect
            try
%                 simsock = serversock.accept; % One or the other
                simsock = []; % simsock dummy
            catch ErrObj
                % Error, usually because the external program failed to connect
                serversock.close; % serversock = [];
                rethrow(ErrObj);
            end
            
            % Now that the connection is established, return the sockets
            obj.serverSocket = serversock;
            obj.commSocket = simsock;
            
            status = 0; % zero means no_problem
            
            % Revert current folder
            if bWorkDir                 
                cd(oldCurDir);                
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
        
        %%==============================================================
        function [status, msg] = acceptSocket(obj)
            % status and msg are returned from the client process
            % status = 0 --> success
            status = obj.status;
            msg = obj.msg;
            
            % Accept Socket
            obj.commSocket = obj.serverSocket.accept;
            
            % Create Streams
            if status == 0 && isjava(obj.commSocket)
                % Create writer and reader
                obj.createStreams;
                obj.isRunning = true;
                msg = '';
            end
        end
        
        %%==============================================================
        
        function stop(obj, stopSignal)
            if ~obj.isRunning, return; end
            
            % Send stop signal
            if nargin < 2 || stopSignal
                obj.write(mlepEncodeStatus(obj.version, 1));
            end
            
            % Close connection
            obj.closeCommSockets;
            
            % Destroy process E+
            if isa(obj.process, 'processManager') && obj.process.running
                obj.process.stop;
            end
            
            obj.isRunning = false;
        end
        
        function packet = read(obj)
            if obj.isRunning
                packet = char(obj.reader.readLine);
            else
                error('Co-simulation is not running.');
            end
        end
        
        function write(obj, packet)
            if obj.isRunning
                obj.writer.write([packet mlepProcess.CRChar]);
                obj.writer.flush;
            else
                error('Co-simulation is not running.');
            end
        end
        
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
            obj.write(mlepEncodeData(obj.version, 0, TInputs(1),...
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
                obj.write(mlepEncodeData(obj.version, 0, TInputs(kRun),...
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
        
        function setRWTimeout(obj, value)
            if value < 0, value = 0; end
            obj.rwTimeout = value;
            if isjava(obj.commSocket)
                obj.commSocket.setSoTimeout(value);
                obj.createStreams;  % Recreate reader and writer streams
            end
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
        
    end
    
    methods (Access=private)
        function closeCommSockets(obj)
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
        
        function createStreams(obj)
            obj.writer = java.io.BufferedWriter(java.io.OutputStreamWriter(obj.commSocket.getOutputStream));
            obj.reader = java.io.BufferedReader(java.io.InputStreamReader(obj.commSocket.getInputStream));
        end
        
        function defaultSettings(obj)
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
                if noSettings                    
                    disp('Load MLEPSETTINGS.mat or run installMlep.m again.');
                    error('Error loading MLE+ settings: Load MLEPSETTINGS.mat or run installMlep.m again.');
                end
                
            end
            
            if noSettings || ~isfield(MLEPSETTINGS, 'version')
                obj.version = 2;    % Current version of the protocol
            else
                obj.version = MLEPSETTINGS.version;
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
        
        function cleanEP(obj, rootDir)            
            dirname = fullfile(rootDir,obj.outputDir);
            if exist(dirname,'dir')
                mlepProcess.rmdirR(dirname);
            end
        end
    end
    
    methods (Static)
        function rmdirR(dirname)
            delete(fullfile(dirname,'*'));
            st = rmdir(dirname);
            assert(st,'Could not delete folder "%s"',dirname);
        end
    end
end

