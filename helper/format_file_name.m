function formatted_name = format_file_name(input_name, include_date_time)
% FORMAT_FILE_NAME - Cleans and formats a file name with optional timestamp
%
% Usage:
%   formatted_name = format_file_name('my model@name!')
%   formatted_name = format_file_name('my model@name!', false)
%
% Examples:
%   format_file_name('my model@name!')
%     -> "MyModelName_2025_08_09T14_45_12"
%   format_file_name('my model@name!', false)
%     -> "MyModelName"
%
% Inputs:
%   input_name        - Original file name (string or char)
%   include_date_time - Logical flag to include timestamp (default: true)
%
% Output:
%   formatted_name - Cleaned, formatted name as a string

arguments
    input_name {mustBeText}
    include_date_time (1,1) logical = true  % Default now set to TRUE
end

% Convert to char and trim
input_name = strtrim(char(input_name));

% Replace non-alphanumeric (except underscore) with space
cleaned = regexprep(input_name, '[^a-zA-Z0-9_]', ' ');

% Split into words
parts = regexp(cleaned, '[\s_]+', 'split');

% Capitalize each part
for i = 1:length(parts)
    if ~isempty(parts{i})
        parts{i} = [upper(parts{i}(1)), lower(parts{i}(2:end))];
    end
end

% Concatenate into one string
formatted_name = strjoin(parts, '_');

% Default fallback if empty
if isempty(formatted_name)
    formatted_name = 'Model';
end

% Add date-time stamp if required
if include_date_time
    t = datetime('now');
    dt_str = datestr(t, 'yyyy_mm_ddTHH_MM_SS');
    formatted_name = [formatted_name, '_', dt_str];
end

% Return as string
formatted_name = string(formatted_name);

end
