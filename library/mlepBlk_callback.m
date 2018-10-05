%% MLEPSIMULINKBLK_CALLBACK - Implements callbacks for 'EnergyPlus' block
function varargout = mlepBlk_callback(block, callback, varargin)
    %% Setup
    % Default output = none
    varargout = {};

    %% Callbacks
    % Select and execute desired callback
    switch callback
        % Initialization
        case 'InitFcn'
            InitFcn(block, varargin{:});
            
        case 'PreSaveFcn'
            PreSaveFcn(block);
            
        case 'MaskConfig'
            MaskConfig(block);
            
        otherwise
            warning([block ':unimplementedCallback'], ...
                ['Callback ''' callback ''' not implemented.']);
        
    end
end

%% Subfunctions
function InitFcn(block, varargin)
    % Nothing happens here
end

function PreSaveFcn(block)
    % Clear UserData to avoid saving model with instantiated objects
    % (crashes Matlab)
    set_param(get_param(block,'handle'),'UserData',[]);
end

function MaskConfig(block)
    % Enables or disables the MLE+ configuration fields based on whether
    % the appropriate checkbox is checked
    
    % Get enables
    enab = get_param(block, 'MaskEnables');
    
    % Define the indices for parameters in the mask
    xEPLUSPATH = 9;
    xBCVTBDIR =  10;
    xPORT =    	 11;
    xHOST =      12;
    
    % MLE+ defaults
    if strcmp( get_param(block, 'mlep_defaults'), 'on' )
        % Values
        set_param(block, 'eplus_path', '');
        set_param(block, 'bcvtb_dir', '');
        set_param(block, 'port', '0');
        set_param(block, 'host', '');
        
        % Enables
        enab{xEPLUSPATH} =	'off';
        enab{xBCVTBDIR} =	'off';
        enab{xPORT} =       'off';
        enab{xHOST} =       'off';
    
    % MLE+ user settings
    else
        % Enables
        enab{xEPLUSPATH} =	'on';
        enab{xBCVTBDIR} =	'on';
        enab{xPORT} =       'on';
        enab{xHOST} =       'on';
    end
    
    % Set enables and aslo visibilities
    set_param(block, 'MaskEnables', enab);
    set_param(block, 'MaskVisibilities', enab);
end