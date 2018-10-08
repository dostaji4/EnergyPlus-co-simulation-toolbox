function writeVariableConfig(inputTable, outputTable, fullFilePath)
% Create XML definition of the variable exchange for the BCVTB protocol
docType = com.mathworks.xml.XMLUtils.createDocumentType('SYSTEM', [],'variables.dtd');
docNode = com.mathworks.xml.XMLUtils.createDocument([], 'BCVTB-variables', docType);
docNode.setEncoding('ISO-8859-1');
docNode.setVersion('1.0')

% INPUT to E+
docRootNode = docNode.getDocumentElement;
%docRootNode.setAttribute('SYSTEM','variables.dtd');
docRootNode.appendChild(docNode.createComment('INPUT to E+'));
for i=1:height(inputTable)
    
    %Example: <variable source="Ptolemy">
    thisElement = docNode.createElement('variable');
    thisElement.setAttribute('source','Ptolemy');
    
    %Example: <EnergyPlus schedule="TSetHea"/>
    newElement = docNode.createElement('EnergyPlus');
    newElement.setAttribute(inputTable.Name{i},... % schedule, actuator, variable
                            inputTable.Type{i});   % particular name
    
    thisElement.appendChild(newElement);
    docRootNode.appendChild(thisElement);
end

% OUTPUT from E+
docRootNode.appendChild(docNode.createComment('OUTPUT from E+'));
for i=1:height(outputTable)
    
    %Example: <variable source="EnergyPlus">
    thisElement = docNode.createElement('variable');
    thisElement.setAttribute('source','EnergyPlus');
    
    %Example: <EnergyPlus name="ZSF1" type="Zone Air Temperature"/>
    newElement = docNode.createElement('EnergyPlus');
    newElement.setAttribute('name',outputTable.Name{i}); % key value ('zone name')
    newElement.setAttribute('type',outputTable.Type{i}); % variable name ('signal')
    
    thisElement.appendChild(newElement);
    docRootNode.appendChild(thisElement);
end

xmlwrite(fullFilePath,docNode);
end