function mlepEnergyPlusSimulation_clbk(block, type, varargin)
%MLEPENERGYPLUSSIMULATION_CLBK - Callback functions for the 'EnergyPlus Simulation' block.

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.
%

switch type
    case 'OpenFcn'
        mlepEnergyPlusSimulation_OpenFcn(block);            
    case {'InitFcn','generateBus'}
        mlepEnergyPlusSimulation_InitFcn(block);
    case 'browseButton'
        mlepEnergyPlusSimulation_browseButton(block, varargin{:});    
    otherwise
        error('Unknown callback: ''%s.''', type);
end
end

function mlepEnergyPlusSimulation_OpenFcn(block)

% Mask of a System Object cannot be programatically opened (r18a). So
% promoted parameters are used instead (at least semi-automatic way).

% Open mask
open_system(block,'mask');
end

function mlepEnergyPlusSimulation_InitFcn(block)
% Create new mlep instance (the actual existing instance is not reachable
% at the moment) and run validate properties routine of the system object!

if strcmp(get_param(bdroot, 'BlockDiagramType'),'library') %strcmp(get_param(bdroot, 'SimulationStatus'),'initializing')        
    return
end

% Get bus names
inputBusName = get_param(block,'inputBusName');
outputBusName = get_param(block,'outputBusName');

% Create mlep instance
ep = mlep;

% Set its properties
ep.idfFile = get_param(block,'idfFile');
ep.epwFile = get_param(block,'epwFile');
ep.useDataDictionary = strcmp(...
                        get_param(block,'useDataDictionary'),...
                        'on');
ep.inputBusName = inputBusName;
ep.outputBusName = outputBusName;

% Load bus objects
loadBusObjects(ep);      

% The bus objects are available now. Set them into all necessary blocks.
% Set Vector2Bus
set_param([block '/Vector to Bus'], 'busType', ['Bus: ' outputBusName]);
vector2Bus_clbk([block '/Vector to Bus'],'popup');

% Set output
set_param([block '/Out'], 'OutDataTypeStr', ['Bus: ' outputBusName]);

% Set input
set_param([block '/In'], 'OutDataTypeStr', ['Bus: ' inputBusName]);
end

function selectedFile = mlepEnergyPlusSimulation_browseButton(block, varargin)
%mlepEnergyPlusSimulation_browseButton Browse button callback.
% Syntax: mlepEnergyPlusSimulation_browseButton(block, filetype) The
% filetype is either 'IDF' or 'EPW' and the the block parameters are set or
%

assert(nargin == 2);
validateattributes(varargin{1},{'char'},{'scalartext'});
filetype = validatestring(varargin{1},{'IDF','EPW'});

fileNameToSet = [lower(filetype), 'File']; % 'idfFile_SO' or 'epwFile_SO'

% Ask for file
selectedFile = mlep.browseForFile(filetype);
if selectedFile ~= 0 % not a Cancel button
    if isfield(get_param(block, 'ObjectParameters'),fileNameToSet) % parameter exists
        % Set mask parameters
        set_param(block, fileNameToSet, selectedFile);
    else
        warning('Parameter ''%s'' does not exist in block ''%s''. Not setting the selected path anywhere.', fileNameToSet, block);
    end
end
end



