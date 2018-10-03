
%% Create an  instance and configure it
ep = so_mlepBlk;
ep.idfFile = 'SmOffPSZ';
ep.epwFile = 'USA_IL_Chicago-OHare.Intl.AP.725300_TMY3';
ep.useBus = false; % use vector I/O
%% The main simulation loop
try
    ep.setup('init');
    
    endTime = 4*24*60*60;
    nRows = ceil(endTime / ep.timestep);
    % use timeseries
    logTable = table('Size',[0, 1 + ep.nOut],...
                        'VariableTypes',repmat({'double'},1,1 + ep.nOut),...
                        'VariableNames',[{'Time'}; ep.outputSigName]);    
    iLog = 1;
    time = 0;    
    while time < endTime
        u = [20 25];
        [flag, time, outputs] = ep.step(u);        
        if flag ~= 0, break, end
        logTable(iLog, :) = num2cell([time outputs']);
        iLog = iLog + 1;
    end
catch me
    % Stop EnergyPlus
    ep.release;
    rethrow(me)
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

