
%% Create an  instance and configure it
ep = mlep;
ep.idfFile = 'SmOffPSZ';
ep.epwFile = 'USA_IL_Chicago-OHare.Intl.AP.725300_TMY3';
ep.useBus = false; % use vector I/O
ep.setup('init'); 

%% The main simulation loop
endTime = 4*24*60*60;
nRows = ceil(endTime / ep.timestep);
% use timeseries
logTable = table('Size',[0, 1 + ep.nOut],...
    'VariableTypes',repmat({'double'},1,1 + ep.nOut),...
    'VariableNames',[{'Time'}; ep.outputSigName]);
iLog = 1;
t = 0;

while t < endTime
    
    u = [20 25];
    
    % Send u, get y
    y = ep.step(u);        
    t = ep.time;

    % Save data to table
    logTable(iLog, :) = num2cell([t y']);
    iLog = iLog + 1;    
end
ep.release;

%% Plot

% Plot results
plot(seconds(table2array(logTable(:,1))),...
    table2array(logTable(:,2:end)));
xtickformat('hh:mm:ss');
legend(logTable.Properties.VariableNames(2:end),'Interpreter','none');

title(ep.idfFile);
xlabel('Time [hh:mm:ss]');
ylabel('Temperature [C]');

