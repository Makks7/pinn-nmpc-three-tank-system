function item = get_struct_item_by_label(dataStruct, targetLabel)
%GET_STRUCT_ITEM_BY_LABEL Find and return the struct element with matching label.
%
% Syntax:
%   item = get_struct_item_by_label(dataStruct, targetLabel)
%
% Inputs:
%   dataStruct   - Array of structs, each expected to have a 'label' field
%   targetLabel  - Label string to match
%
% Output:
%   item         - First matching struct element (returns [] if not found)

    % Validate input
    if ~isstruct(dataStruct)
        error('First input must be a struct array.');
    end

    if ~isfield(dataStruct, 'label')
        error('Struct array must contain a "label" field.');
    end

    % Default return
    item = [];

    % Search through the struct array
    for i = 1:numel(dataStruct)
        if ischar(dataStruct(i).label) || isstring(dataStruct(i).label)
            if strcmpi(string(dataStruct(i).label), string(targetLabel))
                item = dataStruct(i);
                return;
            end
        end
    end
end
