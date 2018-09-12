%% REMOVE all EP generated folders and files

%delete the "Output" folders from \examples
disp('============== Removing EnergyPlus generated files =================')
cp = fileparts(mfilename('fullpath'));
dirFilter = '.*Output';
dirList = dirPlus(fullfile(cp,'examples'),'ReturnDirs',true,'DirFilter',dirFilter,'RecurseInvalid',true);
for i = 1:numel(dirList)    
    delete(fullfile(dirList{i},'*'));
    [status, msg] = rmdir(dirList{i});
    if status
        fprintf('Removing folder "%s".\n',dirList{i});
    else
        warning('Folder "%s" could not be removed.', dirList{i});
    end
end
disp('==============               Done                  =================')