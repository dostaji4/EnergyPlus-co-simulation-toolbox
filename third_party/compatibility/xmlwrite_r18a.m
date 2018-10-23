function varargout=xmlwrite_r18a(varargin)
%XMLWRITE  Serialize an XML Document Object Model node.
%   XMLWRITE(FILENAME,DOMNODE) serializes the DOMNODE to file FILENAME.
%
%   S = XMLWRITE(DOMNODE) returns the node tree as a character vector.
%
%   Example: 
%   % Create a sample XML document.
%   docNode = com.mathworks.xml.XMLUtils.createDocument('root_element')
%   docRootNode = docNode.getDocumentElement;
%   docRootNode.setAttribute('attribute','attribute_value');
%   for i=1:20
%      thisElement = docNode.createElement('child_node');
%      thisElement.appendChild(docNode.createTextNode(sprintf('%i',i)));
%      docRootNode.appendChild(thisElement);
%   end
%   docNode.appendChild(docNode.createComment('this is a comment'));
%
%   % Save the sample XML document.
%   xmlFileName = [tempname,'.xml'];
%   xmlwrite(xmlFileName,docNode);
%   edit(xmlFileName);
%
%   See also XMLREAD, XSLT.

%   Copyright 1984-2016 The MathWorks, Inc.

%    Advanced use:
%       FILENAME can also be a URN, java.io.OutputStream or
%                java.io.Writer object
%       SOURCE can also be a SAX InputSource, JAXP Source,
%              InputStream, or Reader object

% This is the XML that the help example creates:
% <?xml version="1.0" encoding="UTF-8"?>
% <root_element>
%     <child_node>1</child_node>
%     <child_node>2</child_node>
%     <child_node>3</child_node>
%     <child_node>4</child_node>
%     ...
%     <child_node>18</child_node>
%     <child_node>19</child_node>
%     <child_node>20</child_node>
% </root_element>
% <!--this is a comment-->

filename = [];

returnString = false;
if length(varargin)==1
    returnString = true;
    result = java.io.StringWriter;
    source = varargin{1};
else
    result = varargin{1};
    if ischar(result)
        filename = result;
        result = xmlstringinput(result,false);
        % This strips off the extra stuff in the resolved file.  Then,
        % we are going to use java to put it in the right form.
        if strncmp(result, 'file:', 5)
           result = regexprep(result, '^file:///(([a-zA-Z]:)|[\\/])','$1');
           result = strrep(result, 'file://', '');
           temp = java.io.File(result);
           result = char(temp.toURI());
        end
    elseif ~isa(result, 'java.io.Writer') && ~isa(result, 'java.io.OutputStream')
            error(message('MATLAB:xmlwrite:IncorrectFilenameType'));
    end
    
    source = varargin{2};
    if ischar(source)
        source = xmlstringinput(source,true);
    end
end

% The JAXP-approved way to serialize a 
% document is to run a null transform.
% This is a JAXP-compliant static convenience method
% which does exactly that.
javaMethod('serializeXML',...
    'com.mathworks.xml.XMLUtils',...
    source,result);

if returnString
    varargout{1}=char(result.toString);
else
    %this notifies the operating system of a file system change.  This
    %probably doesn't work if the user passed in the filename in the form
    %of file://filename, but it would probably be more trouble than it is
    %worth to resolve it.  It should be harmless in that case.
    if ischar(result) && strncmp(result, 'file:', 5)
        fschange(fileToDirectory(filename));
    end
end

function out = xmlstringinput(xString,isFullSearch,varargin)
%XMLSTRINGINPUT Determine whether a string is a file or URL
%   RESULT = XMLSTRINGINPUT(STRING) will return STRING if
%   it contains "://", indicating that it is a URN.  Otherwise,
%   it will search the path for a file identified by STRING.
%
%   RESULT = XMLSTRINGINPUT(STRING,FULLSEARCH) will
%   process STRING to return a RESULT appropriate for passing
%   to an XML process.   STRING can be a URN, full path name,
%   or file name.
%
%   If STRING is a  filename, FULLSEARCH will control how 
%   the full path is built.  If TRUE, the XMLSTRINGINPUT 
%   will search the entire MATLAB path for the filename
%   and return an error if the file can not be found.
%   This is useful for source documents which are assumed
%   to exist.  If FALSE, only the current directory will
%   be searched.  This is useful for result documents which
%   may not exist yet.  FULLSEARCH is TRUE if omitted.
%
%   This utility is used by XSLT, XMLWRITE, and XMLREAD

%   Copyright 1984-2009 The MathWorks, Inc.

%Note: the varargin in the signature is to support a legacy input argument
%which returned the result as a java.io.File object.  This turned out to
%be worse than useless, causing multiple encoding and escaping problems so
%it was removed.  Leave the varargin here in case anyone was calling 
%the function with the third argument.

if isempty(xString)
    error(message('MATLAB:xmlstringinput:EmptyFilename'));
elseif contains(xString,'://')
    %xString is already a URL, most likely prefaced by file:// or http://
    out = xString;
    return;
end

if nargin<2 || isFullSearch
    if ~exist(xString,'file')
        %search to see if xString exists when isFullSearch
        error(message('MATLAB:xml:FileNotFound', xString));
    else
        out = which(xString);
        if isempty(out)
            out = xString;
        end
    end
else
    out = xString;
end

temp = java.io.File(out);

if ~temp.isAbsolute()
    out = fullfile(pwd,out);
end

%Return as a URN
if strncmp(out,'\\',2)
    % SAXON UNC filepaths need to look like file:///\\\server-name\
    out = ['file:///',out];
elseif strncmp(out,'/',1)
    % SAXON UNIX filepaths need to look like file:///root/dir/dir
    out = ['file://',out];
else
    % DOS filepaths need to look like file:///d:/foo/bar
    out = ['file:///',strrep(out,'\','/')];
end

function final_name = fileToDirectory(orig_name)
% This is adequate to resolve the full path since the call above to xmlstringinput 
% does not search the path when looking to write the file.
temp = fileparts(orig_name);
if isempty(temp)
    final_name = pwd;
else
    final_name = temp;
end

