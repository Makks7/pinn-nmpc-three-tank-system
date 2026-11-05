function thesis_dump_cstr()
%THESIS_DUMP_CSTR  Runs the CSTR model again with logging on for every Scope,
% and saves CA, T, CA0, Q etc. as plain numbers in
% PINN_THREE_TANK/figures_pub/raw_cstr_scopes.mat. Takes a few minutes.
root = fileparts(fileparts(mfilename('fullpath')));
cstrDir = fullfile(fileparts(root), 'Nonlinear CSTR', 'matlab');
addpath(cstrDir);
here0 = pwd; restore = onCleanup(@() cd(here0)); cd(cstrDir);
mdl = 'A_SERVO_poly_shift2_u_ADAPT2_output';
evalin('base', sprintf('run(''%s'');', fullfile(cstrDir, 'setup_nmpc.m')));
wasLoaded = bdIsLoaded(mdl);
load_system(mdl);
sc = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'BlockType', 'Scope');
names = cell(numel(sc), 1);
for k = 1:numel(sc)
    names{k} = sprintf('scope%02d', k);
    set_param(sc{k}, 'DataLogging', 'on', 'DataLoggingVariableName', names{k}, ...
        'DataLoggingSaveFormat', 'StructureWithTime', 'DataLoggingLimitDataPoints', 'off');
    fprintf('%s = %s\n', names{k}, strrep(sc{k}, newline, ' '));
end
set_param(mdl, 'ReturnWorkspaceOutputs', 'on');
fprintf('Running %s ...\n', mdl);
o = sim(mdl);
R = struct();
R.scope_paths = char(strrep(sc, newline, ' '));
for k = 1:numel(names)
    try, x = o.get(names{k}); catch, x = []; end
    if isempty(x), continue, end
    R.([names{k} '_t']) = double(x.time);
    for j = 1:numel(x.signals)
        v = double(squeeze(x.signals(j).values)); if size(v, 1) ~= numel(x.time), v = v.'; end
        R.(sprintf('%s_in%d', names{k}, j)) = v;
        lab = ''; if isfield(x.signals(j), 'label'), lab = x.signals(j).label; end
        R.(sprintf('%s_in%d_label', names{k}, j)) = char(lab);
    end
end
outdir = fullfile(root, 'figures_pub'); if ~exist(outdir, 'dir'), mkdir(outdir); end
save(fullfile(outdir, 'raw_cstr_scopes.mat'), '-struct', 'R', '-v7');
fprintf('\nDone. Saved raw_cstr_scopes.mat in %s\n', outdir);
if ~wasLoaded, close_system(mdl, 0); end   % close without saving, so your model is not changed
end
