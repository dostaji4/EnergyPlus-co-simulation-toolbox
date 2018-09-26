%% MLEPSIMULINKBLK M-S-Function for E+ Cosimulation block for Simulink.
%   This Matlab S-Function implements the Simulink block for EnergyPlus
%   Cosimulation.  It is part of the MLE+ toolbox.  Open the MLE+ Simulink
%   library mlepLibrary.slx to use this block.
%
% This S-function is modified from the original function written by Truong
% Nghiem and distributed with MLE+ v. 1.1. It is modified and redistributed
% under the [TO DO: FIGURE THIS OUT] license.
%
% SYNTAX:
%  msfun_mlepBlk(block)
%
% INPUTS:
%   block =     Simulink block which uses the S-function
%
% COMMENTS:
% 1. This is a Simulink S-function. Its structure and conventions conform
%    with the Simulink documentation for S-functions; for more info. see
%    doc('S-Function').
% 
% 2. This function is not intended for use outside of the NREL Campus
%    Energy Modeling Simulink library; therefore the error checking and
%    documentation are minimal. View the code to see what is going on.
%
% HISTORY:
%   Nov. 2010       Original version by Truong Nghiem
%                   (nghiem@seas.upenn.edu) with support for BCVTB
%                   protocol v. 2.
%                   
%                   Original code (C) 2010 by Truong Nghiem;
%                   reused with permission.
%
%   Aug. 2013       Modified by Willy Bernal (willyg@seas.upenn.edu) for
%                   use with the NREL Campus Energy Modeling project
%
%   Nov. 2013       Modified by Stephen Frank for readability and ease of
%                   use
%
%   Jul. 2015       Modified by Willy Bernal to work for the MLE+
%                   installation and not only Campus Energy Modeling 
%                   Project. 
%
%   Sep. 2018       Modified by Jiri Dostal to be independent of the MLE+.
%                   Core is now based on the Willy Bernal version from
%                   2015.
%

function msfun_mlepBlk(block)
    % Set the basic attributes of the S-function and registers the required
    % callbacks
    setup(block);
end

%% Setup
% Set up the S-function block's basic characteristics
function setup(block)
    %% Parameters
    % Register the number of parameters
    block.NumDialogPrms = 10;
    
    % TO DO: Implement CheckParameters()
    
    % Manually trigger CheckParameters() to check the dialog parameters
    %CheckParameters(block)
    
    % Parse the dialog parameters
    ParseParameters(block)
    
    % Retrieve parameters from user data
    d = get_param(block.BlockHandle, 'UserData');

    %% Ports
    % Input ports:
    %   1 - Vector of EnergyPlus inputs
    %
    % Output ports:
    %   1 - Termination/error flag
    %   2 - EnergyPlus time stamp
    %   3 - Vector of EnergyPlus outputs
    
    % Register the number of input ports
    block.NumInputPorts  = 1;
    
    % Register the number of output ports
    block.NumOutputPorts = 3;

    % Setup port properties to be dynamic
    block.SetPreCompInpPortInfoToDynamic;
    block.SetPreCompOutPortInfoToDynamic;
    
    % Override input port properties
    block.InputPort(1).Dimensions  = -1;            % inherited size
    block.InputPort(1).DatatypeID  = 0;             % double
    block.InputPort(1).Complexity  = 'Real';
    block.InputPort(1).DirectFeedthrough = true;
    
    % Override output port properties
    block.OutputPort(1).Dimensions  = 1;            % flag
    block.OutputPort(1).DatatypeID  = 0;            % double
    block.OutputPort(1).Complexity  = 'Real';
    block.OutputPort(1).SamplingMode = 'sample';

    block.OutputPort(2).Dimensions  = 1;            % time
    block.OutputPort(2).DatatypeID  = 0;            % double
    block.OutputPort(2).Complexity  = 'Real';
    block.OutputPort(2).SamplingMode = 'sample';

    nDim = d.dialog.nout;
    block.OutputPort(3).Dimensions  = nDim;         % output vector
    block.OutputPort(3).DatatypeID  = 0;            % double
    block.OutputPort(3).Complexity  = 'Real';
    block.OutputPort(3).SamplingMode = 'sample';

    %% Options
    % Register the sample times: Discrete; no offset    
    block.SampleTimes = [d.timestep 0];
    
    % Set the block simStateCompliance to default    
    block.SimStateCompliance = 'DefaultSimState';

    %% Register S-function methods
    % Initialize conditions
    block.RegBlockMethod('InitializeConditions', @InitializeConditions);
    
    % Set input port properties
    block.RegBlockMethod('SetInputPortDimensions', @SetInputPortDimensions);
    block.RegBlockMethod('SetInputPortSamplingMode', @SetInputPortSamplingMode);
    
    % Check dialog parameters
    %block.RegBlockMethod('CheckParameters', @CheckParameters);
    
	% Simulation start
    block.RegBlockMethod('Start', @Start);
    
    % Compute output (required)
    block.RegBlockMethod('Outputs', @Outputs);
    
    % Simulation end (required)
    block.RegBlockMethod('Terminate', @Terminate);
    
end

%% Parse Parameters
% Parse the dialog parameters and store them in the block user data
function ParseParameters(block)
    
    % Define names of dialog parameters (in order)
    dialogNames = { ...
        'work_dir', ...         % Working directory
        'rel_path', ...         % Working directory is relative path (T/F)
        'fname', ...            % Name of IDF file
        'weather_profile', ...  % Name of weather profile file        
        'nout', ...             % Number of real outputs
        'timeout', ...          % Communication timeout
        'eplus_path', ...       % Path to EnergyPlus executable
        'bcvtb_dir', ...        % Path to BCVTB library
        'port', ...             % Socket port
        'host' };               % Host machine
    
    % Put dialog parameters into data structure
    d.dialog = struct();
    for i = 1:length(dialogNames)
        d.dialog.(dialogNames{i}) = block.DialogPrm(i).Data;
    end
    
    % Parse working directory path
    if isempty(d.dialog.work_dir)
        % Empty = use current working directory
        workDir = '.';
        
    elseif d.dialog.rel_path
        % Parse relative path
        if strcmp(d.dialog.work_dir(1), filesep)
            workDir = [pwd d.dialog.work_dir];
        else
            workDir = [pwd filesep d.dialog.work_dir];
        end
    else
        % Use absolute path
        workDir = d.dialog.work_dir;
    end
    
    if strcmp(workDir(end), filesep)
        % Strip trailing file sep
        workDir = workDir(1:end-1);
    end
    
    % Parse model file location         
    idfFile = d.dialog.fname;
    if strcmpi(d.dialog.fname(end-3:end), '.idf')
        % Strip extension
        idfFile = idfFile(1:end-4);
    end
    
    % Check paths
    assert( ...
        exist(workDir, 'dir') > 0, ...
        'EnergyPlusCosim:invalidWorkingDirectory', ...
        'Specified working directory "%s" does not exist.', ...
        workDir );
    assert( ...
        exist([idfFile,'.idf'], 'file') > 0, ...
        'EnergyPlusCosim:invalidModelFile', ...
        'Specified IDF file "%s" does not exist.', ...
        idfFile );
    
    % Parse weather file name (may contain '.' in the filename)
    epwFile = d.dialog.weather_profile;
    if strcmpi(epwFile(end-3:end), '.epw')
        % Strip extension
        epwFile = epwFile(1:end-4);
    end
    
    d.idfFile = idfFile;
    d.epwFile = epwFile;
    d.workDir = workDir;
    in = readIDF([idfFile '.idf'],'Timestep');
    d.timestep = 60/str2double(char(in(1).fields{1})) * 60 ;
    
    % Save to UserData of the block    
    set_param(block.BlockHandle, 'UserData', d);
    set_param(block.BlockHandle, 'UserDataPersistent', 'on');
end



%% Set sampling mode for input ports
% Not sure if really needed?
function SetInputPortSamplingMode(block, port, mode)
    block.InputPort(port).SamplingMode = mode;
end


%% Set dimension for input ports
% Not sure if really needed?
function SetInputPortDimensions(block, port, dimsInfo)
    block.InputPort(port).Dimensions = dimsInfo;
end


%% Start
function Start(block)
    %% Setup
    % Load user data (includes parsed dialog parameters)
    d = get_param(block.BlockHandle, 'UserData');    
    
    % Create the mlep object
    processobj = mlep;
    
    % Setup up mlep
    processobj.workDir =        d.workDir;
    processobj.idfFile =        d.idfFile;
    processobj.epwFile =        d.epwFile;
    processobj.acceptTimeout =  d.dialog.timeout*1000; % s -> ms
    processobj.port =           d.dialog.port;
    processobj.host =           d.dialog.host;
    if ~isempty(d.dialog.eplus_path)
        processobj.program =    d.dialog.eplus_path;
    end
    if ~isempty(d.dialog.bcvtb_dir)
        processobj.bcvtbDir =   d.dialog.bcvtb_dir;
    end
    d.processobj = processobj;    
    
    assert( ...
        isa(processobj, 'mlep'), ...
        'EnergyPlusCosim:lostCosimulationProcess', ...
        'Internal error: Cosimulation process object is lost.' );
    
    %% Start mlep
    % Start mlep process
    [status, msg] = processobj.start;
    processobj.status = status;
    processobj.msg = msg;

    assert( ...
        status == 0, ...
        'EnergyPlusCosim:startupError', ...
        'Cannot start EnergyPlus: %s.', msg );

    % Save processobj to UserData of the block    
    set_param(block.BlockHandle, 'UserData', d);

end

%% InitializeConditions:
function InitializeConditions(block)
    % Get processobj
    d = get_param(block.BlockHandle, 'UserData');
    processobj = d.processobj;
    assert( ...
        isa(processobj, 'mlep'), ...
        'EnergyPlusCosim:lostCosimulationProcess', ...
        'Internal error: Cosimulation process object is lost.' );

    %% Accept Socket 
    [status, msg] = processobj.acceptSocket;
        assert( ...
        status == 0, ...
        'EnergyPlusCosim:startupError', ...
        'Cannot start EnergyPlus: %s.', msg );

%     % Save processobj back to UserData of the block
% COMMENTED OUT BY JD
%     set_param(block.BlockHandle, 'UserData', d);

end


%% Outputs
function Outputs(block)
    % Get processobj
    d = get_param(block.BlockHandle, 'UserData');
    processobj = d.processobj;
    assert( ...
        isa(processobj, 'mlep'), ...
        'EnergyPlusCosim:lostCosimulationProcess', ...
        'Internal error: Cosimulation process object is lost.' );

    % Step EnergyPlus and get outputs
    if processobj.isRunning
        % MLE+ version number
        VERNUMBER = 2;

        % Send signals to E+
        rvaluesOut = block.InputPort(1).Data;
        
        % Read data from E+
        readpacket = processobj.read;
        assert( ...
            ~isempty(readpacket), ...
            'EnergyPlusCosim:readError', ...
            'Could not read data from EnergyPlus.' );

        % Decode data
        % (Currently, ivalues and bvalues are not used)
        [flag, timevalue, rvaluesIn] = mlepDecodePacket(readpacket);
        
        % Process output
        if flag ~= 0
            processobj.stop;
            block.OutputPort(1).Data = flag;
            return;
        else
            % Case where no data is returned
            if isempty(rvaluesIn), rvaluesIn = 0; end

            % Set outputs of block
            block.OutputPort(1).Data = flag;
            block.OutputPort(2).Data = timevalue;
            block.OutputPort(3).Data = rvaluesIn(:);
        end
        
        % Write data to E+
        processobj.write( ...
            mlepEncodeRealData(VERNUMBER, 0, block.CurrentTime, rvaluesOut));
        
    end

end

%% Terminate
function Terminate(block)
    % Get processobj
    d = get_param(block.BlockHandle, 'UserData');
    if ~isempty(d) && isstruct(d)
        processobj = d.processobj;
        assert( ...
            isa(processobj, 'mlep'), ...
            'EnergyPlusCosim:lostCosimulationProcess', ...
            'Internal error: Cosimulation process object is lost.' );
        
        % Stop the running process
        if processobj.isRunning
            processobj.stop;
        end
    end
    
end