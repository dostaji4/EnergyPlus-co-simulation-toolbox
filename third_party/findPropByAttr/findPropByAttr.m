function [props, metaprops] = findPropByAttr(classnameOrObject,varargin)
% FINDPROPBYATTR - Find class properties by their attributes.
%
%  Syntax: [props, metaprops] = findPropByAttr(classnameOrObject,"Name,Value,..")
% 
%  Inputs:
% classnameOrObject - class name (as character array) or an instantiated
%                     object.
% "Name, Value,..." - specify class property attribute value filter. The 
%                     attribute values should match a variable type of the 
%                     metaproperty (e.q. char -> char). The value of the 
%                     attribute "DefiningClass" is specified as a character
%                     array.
% 
% Outputs:
%             props - list of names of properties suiting the requirements.
%         metaprops - metaproperty objects for the listed properties.
% 
% Example:
% 
%   % --- List property attributes
%   [~,mp] = findPropByAttr('table');
%   mp(1)
% 
%   % --- List 'Copyable' properties
%   p = findPropByAttr('table','NonCopyable',0)
% 
%   % or equivalently
%   t = table; % instantiate and object
%   p = findPropByAttr(t,'NonCopyable',0)
% 
%   % --- List 'GetAccess' = 'private' or 'protected' properties defined by the
%   % class itself. Multiple options can be specified using a cell array. 
%   p = findPropByAttr('table',...
%                    'GetAccess',{'private','protected'},...
%                    'DefiningClass','table')
%
% See also: FINDPROP, METACLASS, META.PROPERTY

% Copyright (c) 2018, Jiri Dostal (jiri.dostal@cvut.cz)
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are 
% met:
%
% 1. Redistributions of source code must retain the above copyright notice,
%    this list of conditions and the following disclaimer.
% 2. Redistributions in binary form must reproduce the above copyright 
%    notice, this list of conditions and the following disclaimer in the 
%    documentation and/or other materials provided with the distribution.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
% "AS IS". NO WARRANTIES ARE GRANTED.
%
% Based on web(fullfile(docroot, 'matlab/matlab_oop/getting-information-about-properties.html'))

if ischar(classnameOrObject)
    mc = meta.class.fromName(classnameOrObject);
elseif isobject(classnameOrObject)
    mc = metaclass(classnameOrObject);
end

nAttr = numel(varargin);
assert(mod(nAttr,2)==0,'Invalid "Name, Value" argument.');

attrName = varargin(1:2:nAttr);
attrValue = varargin(2:2:nAttr);


nProps = length(mc.PropertyList);
props = cell(1,nProps);
metaprops(nProps) = matlab.system.CustomMetaProp;
ii = 0;
for  c = 1:nProps
    mp = mc.PropertyList(c);
    % Get all property attributes
    availableAttr = properties(mp);
    valid = 0;
    if all(ismember(attrName, availableAttr))
        valid = 1;
        % Check attribute values
        for iAttr = 1:numel(attrName)
            objValue = mp.(attrName{iAttr});
            desiredValue = attrValue{iAttr};
            
            try
                if ischar(desiredValue) || isstring(desiredValue) || iscellstr(desiredValue)
                    % Special case for 'DefiningClass' property
                    if strcmpi(attrName{iAttr},'DefiningClass')
                        objValue = objValue.Name; % Get defining class name
                    end
                    
                    if ~any(contains(objValue,desiredValue,'IgnoreCase',true))
                        valid = 0; break
                    end
                else
                    % Try isequal
                    if ~isequal(objValue,desiredValue)
                        valid = 0; break
                    end
                end
            catch
                valid = 0; break
            end
        end
    end
    %Add to output
    if valid
        ii = ii + 1;
        props(ii) = {mp.Name};
        metaprops(ii) = mp;
    end
end
% Squeeze the output array
props = props(1:ii);
metaprops = metaprops(1:ii);
end