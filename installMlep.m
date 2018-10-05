% INSTALLMLEP code to install "mlep"
function installMlep
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
% Last Modified by Willy Bernal - Willy.BernalHeredia@nrel.gov 30-Jul-2015

%% === Extract paths ======================================================

selectByDialog = 1;
if ispc
    % Windows
    
    % Toolbox path
    homePath = fileparts(mfilename('fullpath'));
    
    % EnergyPlus path
    rootFolder = 'C:\';
    eplusDirList = dirPlus(rootFolder,...
        'ReturnDirs', true,...
        'Depth',0,...
        'DirFilter', '^EnergyPlusV\d-\d-\d$');
    
    % Ask for assistance if necessary
    if numel(eplusDirList) == 1
        eplusPath = eplusDirList{1};
        if validEnergyPlusDir(eplusPath)
            answer = questdlg(sprintf('Found EnergyPlus installation "%s" do you want to use it?',eplusPath),...
                'Installing mlep');
            if strcmp(answer,'Yes')
                selectByDialog = 0;
            end
        end
    else
        if isempty(eplusDirList)
            f = helpdlg(['No EnergyPlus installation found.' newline ...
                'Please select the installation folder manually.'],...
                'Installing mlep');
            waitfor(f);
        else
            f = helpdlg(sprintf('Multiple EnergyPlus installations found \n"%s". \nPlease select the desired installation manually.',...
                strjoin(eplusDirList,'"\n"')),'Installing mlep');
            waitfor(f);
        end
    end
    
    % Select manually by dialog
    if selectByDialog
        eplusPath = getEplusDir(rootFolder);
        if isempty(eplusPath)
            error('mlep installation failed.');            
        end
    end
    
    % Java path (registry query)
    ver = winqueryreg('HKEY_LOCAL_MACHINE','software\JavaSoft\Java Runtime Environment','CurrentVersion');
    javaHome = winqueryreg('HKEY_LOCAL_MACHINE',['software\JavaSoft\Java Runtime Environment\' ver],'JavaHome');
    javaPath = fullfile(javaHome,'bin');
    if ~exist(javaPath,'dir')
        error('Java Runtime Environment not found. Please install Java JRE.')
    end
    
    % Get EnergyPlus command
    eplusCommand = dirPlus(eplusPath,...
        'FileFilter','^(?i)energyplus.exe(?-i)$',...
        'PrependPath', false);
else
    warndlg('Only Windows installation has been tested!','Installing mlep','modal');
    f = helpdlg('Select the EnergyPlus installation root folder',...
        'Installing mlep');
    waitfor(f);
    eplusPath = getEplusDir(rootFolder);
    javaPath = 'usr/bin/java';
    
    % Get EnergyPlus command
    eplusCommand = dirPlus(eplusPath,...
        'FileFilter','^(?i)energyplus(?-i)$',...
        'PrependPath', false);
end

%% === Save Settings ======================================================
% into global variable and file to load in all the following runs
global MLEPSETTINGS

MLEPSETTINGS = struct;

MLEPSETTINGS.versionProtocol = 2;     % Version of the BCVTB protocol

MLEPSETTINGS.program = eplusCommand; % Program name

bcvtbPath = fullfile(homePath,'bcvtb');

MLEPSETTINGS.env = {...
    {'ENERGYPLUS_DIR', eplusPath},...   % Path to the EnergyPlus folder
    {'BCVTB_HOME', bcvtbPath},...       % Path to the BCVTB
    {'PATH', [javaPath ';' eplusPath]}... % System path, should include E+ and JRE
    };

MLEPSETTINGS.eplusDir = eplusPath;
MLEPSETTINGS.javaDir = javaPath;
MLEPSETTINGS.homeDir = homePath;

% Save mlep settings
save(fullfile(homePath,'MLEPSETTINGS.mat'),'MLEPSETTINGS');

disp('================ mlep installation succesful ================');

%% =========================================================================
% EnergyPlus folder validation function
    function valid = validEnergyPlusDir(folder)
        valid = ~isempty(dirPlus(folder,'Depth',1,'FileFilter','^Energy\+\.idd'));
    end

% Select EP dir dialog
    function epPath = getEplusDir(rootFolder)
        isValidEplusDir = 0;
        while ~isValidEplusDir
            folder = {uigetdir(rootFolder,...
                'Select EnergyPlus installation folder')
                };
            if folder{1} == 0 % Cancel button
                epPath = [];
                return
            end
            isValidEplusDir = validEnergyPlusDir(folder{1});
            if ~isValidEplusDir
                f = helpdlg(['Selected EnergyPlus folder is not valid.' newline ...
                    'Please select the installation root folder (e.g. "EnergyPlusV8-9-0").'],...
                    'EnergyPlus folder selection');
                waitfor(f);
            else
                epPath = folder{1};
            end
            
        end
    end
end