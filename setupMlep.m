function setupMlep
%SETUPMLEP Setup mlep tool. 
%Search for all necessary paths and save them for future use. The script is
%ran automatically, but run it manually when settings need to be changed.
%The settings are stored to the toolbox directory into a MLEPSETTINGS.mat
%file.

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved. See the license file.

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
        if validateEnergyPlusDir(eplusPath)
            answer = questdlg(sprintf('Found EnergyPlus installation "%s" do you want to use it?',eplusPath),...
                'Installing mlep');
            if strcmp(answer,'Yes')
                selectByDialog = 0;
            end
        end
    else
        if isempty(eplusDirList)
            f = helpdlg(['No EnergyPlus installation found.' newline ...
                'Please install it or select the installation folder manually.'],...
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
    
    % Get EnergyPlus version
    [~,iddPath] = validateEnergyPlusDir(eplusPath);
    versionEnergyPlus = mlep.getEPversion(iddPath);        
    
    % Java path - use Matlab internal JRE
    javaPath = dirPlus(fullfile(matlabroot,'sys','java'),'FileFilter','java.exe');
    if ~isempty(javaPath)
        javaPath = fileparts(javaPath{1});
    else
        error('Java Runtime Environment not found. Please change the installation script to provide path to a Java JRE.')
    end
    
    % Get EnergyPlus command
    eplusCommand = dirPlus(eplusPath,...
        'FileFilter','^(?i)energyplus.exe(?-i)$',...
        'PrependPath', false);
    assert(~isempty(eplusCommand));
else
    rootFolder = '/';
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
    assert(~isempty(eplusCommand));
end

%% === Save Settings ======================================================
% into file to load in all the following runs
MLEPSETTINGS = struct;

MLEPSETTINGS.versionProtocol = 2;     % Version of the BCVTB protocol

MLEPSETTINGS.versionEnergyPlus = versionEnergyPlus; % EnergyPlus version

MLEPSETTINGS.program = eplusCommand{1}; % Program name

bcvtbPath = fullfile(homePath,'bcvtb');

MLEPSETTINGS.env = {...
    {'ENERGYPLUS_DIR', eplusPath},...   % Path to the EnergyPlus folder
    {'BCVTB_HOME', bcvtbPath},...       % Path to the BCVTB
    {'PATH', [javaPath ';' eplusPath]}... % System path, should include E+ and JRE
    };

MLEPSETTINGS.eplusDir = eplusPath;
MLEPSETTINGS.javaDir = javaPath;
MLEPSETTINGS.homeDir = homePath;        %#ok<STRNU>

% Save mlep settings
save(fullfile(homePath,'MLEPSETTINGS.mat'),'MLEPSETTINGS');
disp(' ------------------------------------------------------------- ');
disp('|    EnergyPlus Co-simulation Toolbox setup successfull       |');
disp(' ------------------------------------------------------------- ');


%% === Helper functions ===================================================
% EnergyPlus folder validation function
    function [valid, idd_path] = validateEnergyPlusDir(folder)
        idd_path = dirPlus(folder,'Depth',1,'FileFilter','^Energy\+\.idd');        
        valid = ~isempty(idd_path);
        if valid
            idd_path = idd_path{1};
        end
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
            isValidEplusDir = validateEnergyPlusDir(folder{1});
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