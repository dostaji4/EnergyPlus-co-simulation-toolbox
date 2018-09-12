function varargout = installationWin(varargin)
% INSTALLATIONWIN MATLAB code for installationWin.fig
%      INSTALLATIONWIN, by itself, creates a new INSTALLATIONWIN or raises the existing
%      singleton*.
%
%      H = INSTALLATIONWIN returns the handle to a new INSTALLATIONWIN or the handle to
%      the existing singleton*.
%
%      INSTALLATIONWIN('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in INSTALLATIONWIN.M with the given input arguments.
%
%      INSTALLATIONWIN('Property','Value',...) creates a new INSTALLATIONWIN or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before installationWin_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to installationWin_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help installationWin

% Last Modified by GUIDE v2.5 08-Aug-2013 10:35:31

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @installationWin_OpeningFcn, ...
                   'gui_OutputFcn',  @installationWin_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before installationWin is made visible.
function installationWin_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to installationWin (see VARARGIN)

% Choose default command line output for installationWin
handles.output = hObject;
handles.instructions =     {'1) Specify the path to EnergyPlus main directory.';...
                                '2) Speficy the path to the folder with Java binaries.';...
                                '3) Replace RunEPlus:';...
                                '      - Sets the Output file to be ./Outputs.';...
                                '      - Prevents deleting files with .mat extension.'};
% set(handles.instructionsEdit, 'String', handles.instructions);

handles.data.eplusPathCheck = 0;
handles.data.javaPathCheck = 0;
handles.data.replaceRunEPlusCheck = 0;
filename = mfilename('fullpath');
[dirPath, ~, ~] = fileparts(filename);
index = strfind(dirPath, [filesep 'install']);
handles.data.homePath = dirPath(1:index-1);
handles.data.bcvtbPath = [handles.data.homePath filesep 'bcvtb'];
% Update handles structure
guidata(hObject, handles);

% UIWAIT makes installationWin wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = installationWin_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --------------------------------------------------------------------


% --- Executes during object creation, after setting all properties.
function instructionsEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to instructionsEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
handles.textHandle = hObject;
guidata(hObject, handles);


% --------------------------------------------------------------------
function Installation_Callback(hObject, eventdata, handles)
% hObject    handle to installationwin (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in replaceEplus.
function replaceEplus_Callback(hObject, eventdata, handles)
% hObject    handle to replaceEplus (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
if handles.data.eplusPathCheck
    % Rename RunEPlus.bat to RunEPlus_orig.bat
    [status1,message,messageid] = copyfile([handles.data.eplusPath filesep 'RunEPlus.bat'] ,[handles.data.eplusPath filesep 'RunEPlus_orig.bat'], 'f');
        
    % Copy RunEPlus.bat
    [status2,message,messageid] = copyfile([handles.data.homePath filesep 'settings' filesep 'RunEPlus.bat'] ,[handles.data.eplusPath filesep 'RunEPlus.bat'], 'f');
    
    % Check if successfully copied.
    handles.data.replaceRunEPlusCheck = status1 & status2;
    
    if handles.data.replaceRunEPlusCheck == 1
        set(handles.WinInstall_RunEPlusEdit, 'Background', 'g');
        set(handles.WinInstall_RunEPlusEdit, 'String', [handles.data.eplusPath filesep 'RunEPlus.bat'])
    else
        MSG = 'Could not copy the RunEPlus.bat to your EnergyPlus directory.';
        errordlg(MSG, 'Replace RunEPlus.bar Error');
    end
else
    MSG = 'You need to specify the EnergyPlus Main Directory first (Step 1).';
    errordlg(MSG, 'Replace RunEPlus.bar Error');
end
guidata(hObject, handles);

% --- Executes on button press in selectJavaDir.
function selectJavaDir_Callback(hObject, eventdata, handles)
% hObject    handle to selectJavaDir (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Select Java Path
startPath = 'C:\';
[javaPath] = uigetdir(startPath,'Select Java\Bin Directory. (e.g. C:\Program Files\Java\jre1.6.0_22\bin)');

% Check Folder
if ischar(javaPath)
    % Check Path
    if exist([javaPath filesep 'java.dll'])
        handles.data.javaPath = javaPath;
        handles.data.javaPathCheck = 1;
        set(handles.JavaDirEdit, 'String', handles.data.javaPath, 'Background', 'g');
    else
        MSG = 'Java Directory Error. The folder does not contain java.dll. This is a required Java executable.';
        errordlg(MSG, 'Wrong Path');
    end
else
    MSG = 'Java Directory Error';
    errordlg(MSG, 'Wrong Path');
end

guidata(hObject, handles);

function JavaDirEdit_Callback(hObject, eventdata, handles)
% hObject    handle to JavaDirEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of JavaDirEdit as text
%        str2double(get(hObject,'String')) returns contents of JavaDirEdit as a double
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function JavaDirEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to JavaDirEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
guidata(hObject, handles);

% --- Executes on button press in selectEplusDir.
function selectEplusDir_Callback(hObject, eventdata, handles)
% hObject    handle to selectEplusDir (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
startPath = 'C:\';

[eplusPath] = uigetdir(startPath,'Select EnergyPlus Directory. (e.g. C:\EnergyPlusV8-0-0)');
if ischar(eplusPath)
    % Check Path
    if exist([eplusPath filesep 'RunEPlus.bat'])
        handles.data.eplusPath = eplusPath;
        handles.data.eplusPathCheck = 1;
        set(handles.EplusDirEdit, 'String', handles.data.eplusPath, 'Background', 'g');
    else
        MSG = 'EnergyPlus Directory Error. The folder does not contain RunEPlus.bat. This is a required E+ executable.';
        errordlg(MSG, 'Wrong Path');
    end
else
    MSG = 'EnergyPlus Directory Error';
    errordlg(MSG, 'Wrong Path');
end
% Update handles structure
guidata(hObject, handles);

function EplusDirEdit_Callback(hObject, eventdata, handles)
% hObject    handle to EplusDirEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of EplusDirEdit as text
%        str2double(get(hObject,'String')) returns contents of EplusDirEdit as a double


% --- Executes during object creation, after setting all properties.
function EplusDirEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to EplusDirEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
guidata(hObject, handles);


% --- Executes on button press in pushbutton4.
function pushbutton4_Callback(hObject, eventdata, handles)
% hObject    handle to pushbutton4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% Save Settings
mlepSaveSettings(handles.data.homePath, handles.data.eplusPath, handles.data.javaPath, handles.data.bcvtbPath);

% Deleting Main Figure
delete(gcf);


% --- Executes on button press in WinInstall_Help.
function WinInstall_Help_Callback(hObject, eventdata, handles)
% hObject    handle to WinInstall_Help (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
instructions =     {'Follow the steps in order.';...
                    ' ';...
                    '1) Specify the path to the main EnergyPlus directory.';...
                    ' ';...
                    '2) Speficy the path to the folder with Java binaries.';...
                    ' ';...
                    '3) Replace RunEPlus.bat.';...
                    '           We provide a modified RunEPlus.bar file that';...
                    '           changes two default seetings in EnergyPlus:';...
                    '               - Sets the Output file to be ./Outputs. All ';...
                    '                 EnergyPlus Output will be put in this folder';...
                    '               - Prevents deleting files with .mat extension. ';...
                    '                 EnergyPlus by default deletes files with the ';...
                    '                 .mat extension'};
helpdlg(instructions,'Installation')
% 
% url = '';
% web(url);
% Update handles structure
guidata(hObject, handles);

function WinInstall_RunEPlusEdit_Callback(hObject, eventdata, handles)
% hObject    handle to WinInstall_RunEPlusEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of WinInstall_RunEPlusEdit as text
%        str2double(get(hObject,'String')) returns contents of WinInstall_RunEPlusEdit as a double


% --- Executes during object creation, after setting all properties.
function WinInstall_RunEPlusEdit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to WinInstall_RunEPlusEdit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end
