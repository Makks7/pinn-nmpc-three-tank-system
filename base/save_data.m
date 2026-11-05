%% save_regression_data.m
% Extract simulation data from base workspace and save dataset

%% === User Parameters ===
sim_out_name = 'out';                    % Variable name (in base workspace) containing simulation data
var_label    = {"h1","h2","h3","u1","u2","u3"}; % Labels of signals to extract
saveFolder   = 'data';                         % Folder to save data
data_type    = 'sim_train';

% Create save folder if it doesn't exist
if ~exist(saveFolder, 'dir')
    mkdir(saveFolder);
end

%% === Step 1: Check if sim_out_name exists in base workspace ===
if ~evalin('base', ['exist(''' sim_out_name ''', ''var'')'])
    error('Variable "%s" not found in base workspace. Run simulation first.', sim_out_name);
end

% Retrieve the data structure from the base workspace
try
    dataStruct = evalin('base', sim_out_name);
catch ME
    error('Failed to retrieve "%s" from base workspace. Error: %s', sim_out_name, ME.message);
end

%% === Step 2: Extract time and signal data ===
disp('Extracting variables...');

% Extract time vector
time = dataStruct.dataset.time;
if isempty(time)
    error('Time data is empty or not found.');
end

data_len = length(time);
disp(['Data length: ', num2str(data_len)]);

% Initialize a structure to hold extracted signals
signals = struct();
disp(dataStruct.dataset.signals(1).label)
% Loop over each variable label and extract corresponding signal
for i = 1:length(var_label)
    var = var_label{i};
    item = get_struct_item_by_label(dataStruct.dataset.signals, var);
    
    if isempty(item)
        warning('Label "%s" not found in signals. Skipping.', var);
        signals.(var) = NaN(data_len, 1); % or leave out, or error
    else
         fprintf('Label "%s"  found in signals. Reading.\n', var);
        signals.(var) = item.values;
        
        % Ensure data length matches time
        if length(signals.(var)) ~= data_len
            warning('Length mismatch for "%s". Truncating/padding to match time.', var);
            if length(signals.(var)) < data_len
                temp = NaN(data_len, 1);
                temp(1:length(signals.(var))) = signals.(var);
                signals.(var) = temp;
            else
                signals.(var) = signals.(var)(1:data_len);
            end
        end
    end
end

%% === Step 3: Save data ===
timestampedName = format_file_name([data_type,'_','data'], true);
saveFile = fullfile(saveFolder, [timestampedName, '.mat']);
save_filename  =  saveFile(1);

% Save all extracted variables
% Prepare variables to save
data_size = data_len;  % Use safe name instead of 'size'

% Save to .mat file
save(save_filename, 'signals', 'time', 'data_size', 'var_label');

disp(['Data saved to ', saveFile]);