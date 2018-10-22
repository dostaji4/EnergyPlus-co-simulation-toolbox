function mlepEnergyPlusSimulation_clbk(block, type)
%MLEPENERGYPLUSSIMULATION_CLBK - Callback functions for the 'EnergyPlus Simulation' block.

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.
%

switch type
    case 'OpenFcn'
        mlepEnergyPlusSimulation_OpenFcn(block)
    case 'maskInit'
        mlepEnergyPlusSimulation_maskInit(block)
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

