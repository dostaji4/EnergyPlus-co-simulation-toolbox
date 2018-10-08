function writeSocketConfig(fullFilePath, serverSocket, hostname)
fid = fopen(fullFilePath, 'w');
if fid == -1
    % error
    serverSocket.close;
    error('Error while creating socket config file: %s', ferror(fid));
end

% Write socket config to file
socket_config = [...
    '<?xml version="1.0" encoding="ISO-8859-1"?>\n' ...
    '<BCVTB-client>\n' ...
    '<ipc>\n' ...
    '<socket port="%d" hostname="%s"/>\n' ...
    '</ipc>\n' ...
    '</BCVTB-client>'];
fprintf(fid, socket_config, serverSocket.getLocalPort, hostname);

[femsg, ferr] = ferror(fid);
if ferr ~= 0  % Error while writing config file
    serverSocket.close; 
    fclose(fid);
    error('Error while writing socket config file: %s', femsg);
end

fclose(fid);
end