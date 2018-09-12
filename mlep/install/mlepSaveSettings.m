function mlepSaveSettings(homePath, eplusPath, javaPath, bcvtbPath);
% MLEPSAVESETTINGS code to save MLE+ Settings. 
%
%      Use: mlepSaveSettings 
%
%      In installMlep you need to specify whether you want to use the GUI
%      mode or the Manual mode. Set manualInstall = 0 if you do not want to
%      use the GUI. 
%      GUI (manualInstall = 1): A installation screen will pop up according
%      to your operating system (PC or UNIX)
%      MANUAL (manualInstall = 0): You need to specify the E+ and Java 
%      directory for Windows machines and only the E+ directory for UNIX 
%      systems.  
%
%      Last Modified by Willy Bernal willyg@seas.upenn.edu 08-Aug-2013 16:29:59

global MLEPSETTINGS

% Run MLE+ Initialization
mlepInit(eplusPath, javaPath, bcvtbPath);

% PC env
if ispc
    MLEPSETTINGS.path = MLEPSETTINGS.env;
else
    
end

% Save MLE+ Settings
save([homePath filesep 'MLEPSETTINGS.mat'],'-v7','MLEPSETTINGS');
end