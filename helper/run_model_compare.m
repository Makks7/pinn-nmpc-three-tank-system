function R = run_model_compare(mdl)
%RUN_MODEL_COMPARE  Runs one Simulink model three times: PINN, ANN and first principles.
%
%   R = run_model_compare('SIM_THREE_TANK_SERVO')
%   R = run_model_compare('SIM_THREE_TANK_REGULATORY')
%
% It runs inside a function because the model's init script clears the base
% workspace, and that was wiping my loop variables. The auto-save in the
% model's StopFcn is switched off during the runs and put back after.

if nargin == 0, mdl = 'SIM_THREE_TANK_SERVO'; end
load_system(mdl);
cb = get_param(mdl, 'StopFcn');
set_param(mdl, 'StopFcn', '');
cleanup = onCleanup(@() set_param(mdl, 'StopFcn', cb));   % restored even on error

tags = {'pinn', 'ann', 'fp'};
R = table();
fprintf('\n%s\n model       h1       h2       h3     total\n', mdl);
for k = 1:numel(tags)
    use_model(tags{k});
    o   = sim(mdl);
    iae = local_iae(o);
    fprintf('%-5s %8.2f %8.2f %8.2f %8.2f\n', upper(tags{k}), iae, sum(iae));
    R = [R; table(string(upper(tags{k})), iae(1), iae(2), iae(3), sum(iae), ...
                  'VariableNames', {'model','h1','h2','h3','total'})]; %#ok<AGROW>
end
use_model('pinn');       % leave the session on the PINN
end

% ------------------------------------------------------------------
function iae = local_iae(o)
v = o.IAE;
if isa(v, 'timeseries')
    v = v.Data(end, :);
elseif isstruct(v) && isfield(v, 'signals')
    v = v.signals.values(end, :);
end
iae = double(v(:)).';
end