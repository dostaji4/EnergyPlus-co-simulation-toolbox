function mlepEnergyPlusSimulation_clbk(block, type, varargin)
%MLEPENERGYPLUSSIMULATION_CLBK - Callback functions for the 'EnergyPlus Simulation' block.

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.
%

switch type
    case 'OpenFcn'
        mlepEnergyPlusSimulation_OpenFcn(block);
    case 'maskInit'
        mlepEnergyPlusSimulation_maskInit(block);
    case 'InitFcn'
        mlepEnergyPlusSimulation_InitFcn(block);
    case 'browseButton'
        mlepEnergyPlusSimulation_browseButton(block, varargin{:});
    case 'generateBus'
        mlepEnergyPlusSimulation_generateBus(block);
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

function mlepEnergyPlusSimulation_maskInit(block)
% This method is triggered when the mask is being drawn or after mask
% parameters are changed and button "ok" or "apply" is pressed.

% Make mlep reinitialize
% would be great to be able to set <system_obj>.isInitialized = 0;
% - don't know how to access the system object properties

% Get bus objects names
inputBusName = get_param(block,'inputBusName');
outputBusName = get_param(block,'outputBusName');

% Check bus objects existence
baseVars = evalin('base',['who(''' inputBusName ''',''' outputBusName ''');']);
if numel(baseVars) ~= 2, return, end

%Set Vector2Bus
set_param([block '/Vector to Bus'], 'busType', ['Bus: ' outputBusName]);
vector2Bus_clbk([block '/Vector to Bus'],'popup');

%Set output
set_param([block '/Out'], 'OutDataTypeStr', ['Bus: ' outputBusName]);

%Set input
set_param([block '/In'], 'OutDataTypeStr', ['Bus: ' inputBusName]);

end

function mlepEnergyPlusSimulation_InitFcn(block)
1;
end

function mlepEnergyPlusSimulation_generateBus(block)
1;
end

function selectedFile = mlepEnergyPlusSimulation_browseButton(block, varargin)
%mlepEnergyPlusSimulation_browseButton Browse button callback. 
% Syntax: mlepEnergyPlusSimulation_browseButton(block, filetype) The
% filetype is either 'IDF' or 'EPW' and the the block parameters are set or
% 

if nargin == 2
    validateattributes(varargin{1},{'char'},{'scalartext'});
    filetype = validatestring(varargin{1},{'IDF','EPW'});
else
    filetype = '*';
end

switch filetype
    case 'IDF'
        filefilter = '*.idf';
        fileNameToSet = 'idfFile';
        dialogTitle = 'Select IDF File';
    case 'EPW'
        filefilter = '*.epw';
        fileNameToSet = 'epwFile';
        dialogTitle = 'Select EPW File';
    otherwise
        filefilter = '*';
        fileNameToSet = '';
        dialogTitle = 'Select File to Open';
end

% Ask for file
[file,path] = uigetfile(filefilter,dialogTitle);
if file ~= 0 % not a Cancel button    
    if isfield(get_param(block, 'ObjectParameters'),fileNameToSet) % parameter exists
        % Set mask parameters
        set_param(block, fileNameToSet, fullfile(path,file));
    else
        warning('Parameter ''%s'' does not exist in block ''%s''. Not setting the selected path anywhere.', fileNameToSet, block);
    end
end
selectedFile = fullfile(path,file);
end



