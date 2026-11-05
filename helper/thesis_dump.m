function thesis_dump()
%THESIS_DUMP  Runs the three-tank servo and regulatory models (FP, PINN, ANN)
% and the CSTR once, then saves all the logged signals as plain numbers in
% PINN_THREE_TANK/figures_pub/raw_*.mat. Takes a few minutes.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
cstrDir = fullfile(fileparts(root), 'Nonlinear CSTR', 'matlab');
if exist(cstrDir, 'dir'), addpath(cstrDir); end
here0 = pwd; restore = onCleanup(@() cd(here0));
outdir = fullfile(root, 'figures_pub'); if ~exist(outdir, 'dir'), mkdir(outdir); end
fprintf('Saving raw signals to %s\n', outdir);
tags = {'fp', 'pinn', 'ann'};
for m = {'SIM_THREE_TANK_SERVO', 'SIM_THREE_TANK_REGULATORY'}
    for k = 1:3
        fprintf('Running %s with %s ...\n', m{1}, upper(tags{k}));
        o = run_quiet(m{1}, tags{k});
        dump_run(o, fullfile(outdir, ['raw_' m{1} '_' tags{k} '.mat']));
    end
end
use_model('pinn');
CSTR = 'A_SERVO_poly_shift2_u_ADAPT2_output';
if exist(CSTR, 'file')
    fprintf('Running %s ...\n', CSTR);
    evalin('base', sprintf('run(''%s'');', fullfile(fileparts(which([CSTR '.slx'])), 'setup_nmpc.m')));
    o = run_quiet(CSTR, '');
    dump_run(o, fullfile(outdir, ['raw_' CSTR '.mat']));
else
    fprintf('CSTR model not found - skipped.\n');
end
fprintf('\nDone. %d raw files in %s\n', numel(dir(fullfile(outdir, 'raw_*.mat'))), outdir);
end

function o = run_quiet(mdl, tag)
f = which([mdl '.slx']); if isempty(f), f = which([mdl '.mdl']); end
if ~isempty(f), cd(fileparts(f)); end   % run from the model's own folder (relative paths in callbacks)
load_system(mdl);
cb = get_param(mdl, 'StopFcn'); set_param(mdl, 'StopFcn', '');
c = onCleanup(@() set_param(mdl, 'StopFcn', cb));
if ~isempty(tag), use_model(tag); end
set_param(mdl, 'SignalLogging', 'on', 'ReturnWorkspaceOutputs', 'on');
o = sim(mdl);
end

function dump_run(o, file)
R = struct();
names = o.who;
for i = 1:numel(names)
    nm = names{i}; x = o.get(nm);
    if strcmp(nm, 'logsout') && isa(x, 'Simulink.SimulationData.Dataset')
        for j = 1:x.numElements
            el = x.getElement(j); en = matlab.lang.makeValidName(['L_' el.Name]);
            try, [t, v] = unpack(el.Values); R.([en '_t']) = t; R.([en '_v']) = v; catch, end
        end
        continue
    end
    try, [t, v] = unpack(x); R.([nm '_t']) = t; R.([nm '_v']) = v; catch, end
end
save(file, '-struct', 'R', '-v7');
fprintf('  saved %s  (%d signals)\n', file, numel(fieldnames(R)) / 2);
end

function [t, v] = unpack(x)
if isa(x, 'timeseries')
    t = x.Time; v = squeeze(x.Data);
elseif isstruct(x) && isfield(x, 'signals')
    t = x.time; v = squeeze(x.signals(1).values);
elseif isa(x, 'Simulink.SimulationData.Dataset')
    [t, v] = unpack(x.getElement(1).Values);
else
    v = x; t = (0:size(x, 1) - 1).';
end
v = double(v); if size(v, 1) ~= numel(t), v = v.'; end
end
