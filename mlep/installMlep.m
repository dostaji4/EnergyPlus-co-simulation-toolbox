% INSTALLMLEP code to install MLE+
%      Run this script before using MLE+.
%
%      Use: installMlep
%
%      In installMlep you need to specify whether you want to use the GUI
%      mode or the Manual mode. Set manualInstall = 0 if you do not want to
%      use the GUI for installation.
%      GUI (manualInstall = 1): A installation screen will pop up according
%      to your operating system (PC or UNIX)
%      MANUAL (manualInstall = 0): You need to specify the E+ and Java
%      directory for Windows machines and only the E+ directory for UNIX
%      systems.
%
%      To save your configurations permanently in Matlab, you need to have
%      admin privileges. If you get the following: "Warning: Unable to save
%      apth to file ..." You either need to run this script everytime you
%      open Matlab or pass a path to the savepath function at the end of
%      the script.
%
%   if ispc
%       % Windows
%       eplusPath = 'C:\EnergyPlusV8-3-0';
%       javaPath = 'C:\Program Files\Java\jre1.8.0_51\bin';
%   else
%       % Unix
%       eplusPath = '/Applications/EnergyPlus-8-3-0';
%   end
%
% Last Modified by Willy Bernal - Willy.BernalHeredia@nrel.gov 30-Jul-2015

%% MODIFY
% true = Install Manually
% fase = Install through GUI
manualInstall = true;

% Paths
if ispc
    % Windows
    % EnergyPlus path
    mlepFolder = mfilename('fullpath');    
    toolboxPath = strsplit(mlepFolder,filesep);
    toolboxPath = strjoin(toolboxPath(1:end-2),filesep);
    eplusPath = fullfile(toolboxPath,'EnergyPlusV8-9-0'); 
    
    % Java path    
    ver = winqueryreg('HKEY_LOCAL_MACHINE','software\JavaSoft\Java Runtime Environment','CurrentVersion');
    javaHome = winqueryreg('HKEY_LOCAL_MACHINE',['software\JavaSoft\Java Runtime Environment\' ver],'JavaHome');
    javaPath = fullfile(javaHome,'bin');  
    if ~exist(javaPath,'dir')
        error('Java Runtime Environment not found. Please install Java JRE.')
    end    
else
    % Unix
    eplusPath = '/Applications/EnergyPlus-8-6-0';
end

%% DO NOT MODIFY
% Extract MLE+ Main Path
filename = mfilename('fullpath');
[mlepPath, ~, ~] = fileparts(filename);

% Add Path
% addpath(mlepPath);
addpath(genpath(fullfile(mlepPath,'mlep','core')));
% addpath(fullfile(mlepPath,'gui'));
addpath(genpath(fullfile(mlepPath,'mlep','install')));
%addpath(fullfile(mlepPath,'settings'));
addpath(genpath(fullfile(mlepPath,'mlep','version')));
% addpath(fullfile(mlepPath,'mlepHelp'));
addpath(genpath(fullfile(mlepPath,'mlep','library')));
bcvtbPath = fullfile(mlepPath,'bcvtb');
addpath(genpath(bcvtbPath));

% Installation Dialog
if ~manualInstall %========================================================
    if ispc
        % WIN
        installationWin;
    else
        % UNIX
        installationUnix;
    end
else %=====================================================================
    % Manual Install
    if ispc
        % No Changes
    else
        % Java Path
        javaPath = '';
    end
    
    % Save Settings =======================================================
    mlepSaveSettings(mlepPath, eplusPath, javaPath, bcvtbPath);
    %%
    %{
    disp('================================');
    disp('        MLE+ COSIMULATION       ');
    disp('     INSTALLATION COMPLETED     ');    
    disp('================================');
    %}
end

% Save Paths
savepath;


