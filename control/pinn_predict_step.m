function [yk_step, hk] = pinn_predict_step(data, uk)
%PINN_PREDICT_STEP  Single-step PINN prediction.
%
% data.e is the output disturbance estimate from the Disturbance Rejector.
% This is what makes the loop offset-free. Without it, any steady-state
% mismatch between the model and the plant just stays as a tracking error.
% pinn_predict_horizon has to use the same correction, otherwise the cost
% function and the diagnostics will not agree on where the plant is going.

ny = data.ny;

if isfield(data,'c') && numel(data.c) == 2
    c = data.c(:);
else
    c = [0.333; 0.333];
end

if isfield(data,'e') && ~isempty(data.e)
    e = data.e(:);
    if numel(e) ~= ny, e = zeros(ny,1); end
else
    e = zeros(ny,1);
end

h = data.yo(:);
yk_step = pinn_predict(h, uk(:), c) + e;
hk = data.ho;
end