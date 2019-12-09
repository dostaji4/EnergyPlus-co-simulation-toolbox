function blkStruct = slblocks
% SLBLOCKS - Simulink Library browser definition file

% Name of the subsystem which will show up in the Simulink Blocksets
% and Toolboxes subsystem.
blkStruct.Name = sprintf('mlep\nLibrary');

% The function that will be called when the user double-clicks on
% this icon.
blkStruct.OpenFcn = 'open(''mlepLibrary.slx'');';

% The argument to be set as the Mask Display for the subsystem.
blkStruct.MaskDisplay = 'disp(''mlep Library Blocks'');';

% Library information for Simulink library browser
blkStruct.Browser = struct();
blkStruct.Browser.Library = 'mlepLibrary';
blkStruct.Browser.Name    = 'EnergyPlus co-simulation toolbox';
