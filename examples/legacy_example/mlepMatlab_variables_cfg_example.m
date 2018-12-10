%% Co-simulation example - specify I/O in variables.cfg
% Demonstrates the functionality of the mlep (MatLab-EnergyPlus) tool in 
% a small office building simulation scenario.
%
% Note that a start of the simulation period as well as a timestep and
% an input/output configuration is defined by the the EnergyPlus simulation
% configuration file (.IDF). Climatic conditions are obtained from a
% EnergyPlus Weather data file (.EPW). 
%
% See also: mlepMatlab_so_example.m, mlepSimulink_example.slx

%% Create mlep instance and configure it

% Instantiate co-simulation tool
ep = mlep;

% Building simulation configuration file
ep.idfFile = 'SmOffPSZ';

% Weather file
ep.epwFile = 'USA_IL_Chicago-OHare.Intl.AP.725300_TMY3';

% Initialize the co-simulation. 
% Note: Two configurations of inputs/outputs are present in this example.
% It was therefore necessary to call initialization routine separately. In
% the case of one fixed setting you can use just the 'start' method (e.g.
% 'ep.start').
ep.initialize; 

%% Input/output configuration 
% If there is no "variables.cfg" config file present in the directory
% where the IDF file resides, then the IDF file is parsed for configured
% inputs/outputs (and "variables.cfg" file is created under output directory
% - named 'eplusout' by default). If a user-defined "variables.cfg" is
% present then it should contain a subset of the IDF I/O and it defines
% the co-simulation inputs/outputs.

% Display inputs/outputs defined in the IDF file. (no "variables.cfg" file
% present).
disp('Input/output configuration without the "variables.cfg" file present.');
inputTable = ep.inputTable    %#ok<*NASGU,*NOPTS>
outputTable = ep.outputTable

% Now with the "variables.cfg" file (example file contains a subset of the
% IDF i/o set).
cd(fileparts(mfilename('fullpath')));
copyfile('variables_example.cfg','variables.cfg');

% Re-initialize
ep.initialize;

disp('Input/output configuration with the "variables.cfg" file present.');
inputTable = ep.inputTable
outputTable = ep.outputTable

% The IDF i/o configuration can still be viewed
disp('Alternative way to obtain IDF input/output configuration.');
inputTableIDF = ep.idfData.inputTable
outputTableIDF = ep.idfData.outputTable

%% Simulate

% Specify simulation duration
endTime = 4*24*60*60; %[s]

% Prepare data logging
nRows = ceil(endTime / ep.timestep); %Query timestep after mlep initialization
logTable = table('Size',[0, 1 + ep.nOut],...
    'VariableTypes',repmat({'double'},1,1 + ep.nOut),...
    'VariableNames',[{'Time'}; ep.outputSigName]);
iLog = 1;

% Start the co-simulation process and communication. 
ep.start

% The simulation loop
t = 0;
while t < endTime
    % Prepare inputs (possibly from last outputs)
    u = [20 25];
    
    % Get outputs from EnergyPlus
    [y, t] = ep.read;
    
    % Send inputs to EnergyPlus
    ep.write(u,t); 
    
    % Log
    logTable(iLog, :) = num2cell([t y(:)']);
    iLog = iLog + 1;        
end
% Stop co-simulation process
ep.stop;

%% Plot results

plot(seconds(table2array(logTable(:,1))),...
    table2array(logTable(:,2:end)));
xtickformat('hh:mm:ss');
legend(logTable.Properties.VariableNames(2:end),'Interpreter','none');

title(ep.idfFile);
xlabel('Time [hh:mm:ss]');
ylabel('Temperature [C]');

%% Clean up
delete variables.cfg
