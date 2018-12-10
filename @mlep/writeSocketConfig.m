function writeSocketConfig(fullFilePath, hostname, port)
% WRITESOCKETCONFIG Create socket configuration file. 
%Create a BCVTB communication configuration file. 
%
%  Syntax: writeSocketConfig(fullFilePath, serverSocket, hostname)
%
%  Inputs:
%   fullFilePath - A path to write the configuration to. 
%       hostname - Hostname.
%           port - Port on the host.
%
%   See also: MLEP.MAKESOCKET
%
% (C) 2015, Willy Bernal (Willy.BernalHeredia@nrel.gov)
%     2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved. Usage must follow the license given in the class
% definition.

fid = fopen(fullFilePath, 'w');
if fid == -1
    % error
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
fprintf(fid, socket_config, port, hostname);

[femsg, ferr] = ferror(fid);
if ferr ~= 0  % Error while writing config file
    fclose(fid);
    error('Error while writing socket config file: %s', femsg);
end

fclose(fid);
end