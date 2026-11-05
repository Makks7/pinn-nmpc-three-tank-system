function make_pub_figures(what)
%MAKE_PUB_FIGURES  Cleaner versions of the Simulink result figures for the thesis/paper.
%
%   make_pub_figures('list')     % run this first, it prints all the logged signal names
%   make_pub_figures('tank')     % three-tank servo + regulatory (PINN, ANN, FP overlaid)
%   make_pub_figures('cstr')     % non-isothermal CSTR Lyapunov NMPC servo
%   make_pub_figures('diagram')  % vector export of the Simulink block diagrams
%   make_pub_figures('all')
%
% Keep this file in PINN_THREE_TANK/helper (setup_project puts it on the path).
% Each figure is drawn at print size (6.5 in wide), Times New Roman 9 pt, and
% saved as vector PDF + 600 dpi PNG in PINN_THREE_TANK/figures_pub/.
%
% If it cannot find a signal it stops and prints the names it did find. Put
% the correct name in the SIGNAL NAMES block below and run it again.

if nargin == 0, what = 'all'; end

% PATHS
% The script finds the project itself, so it runs from any current folder.
root = fileparts(fileparts(mfilename('fullpath')));        % ...\PINN_THREE_TANK
for sub = {'control', 'base', 'helper', 'models', 'python', 'data'}
    p = fullfile(root, sub{1}); if exist(p, 'dir'), addpath(p); end
end
addpath(root);
cstrDir = fullfile(fileparts(root), 'Nonlinear CSTR', 'matlab');  % ...\Desktop\Nonlinear CSTR\matlab
if exist(cstrDir, 'dir'), addpath(cstrDir); end
if ~exist('SIM_THREE_TANK_SERVO', 'file')
    error('Cannot see SIM_THREE_TANK_SERVO.slx under %s\\control. Check the folder name.', root);
end
here0 = pwd; restore = onCleanup(@() cd(here0));             % always return to where you were

outdir = fullfile(root, 'figures_pub');
if ~exist(outdir, 'dir'), mkdir(outdir); end

% SIGNAL NAMES
% First name that exists is used. Edit these lists if 'list' shows other names.
S.ymeas  = {'ymeas', 'y_meas', 'h', 'y'};          % measured levels [3 x N]
S.yset   = {'yset', 'y_set', 'ysp'};               % setpoints
S.u      = {'u', 'u_applied'};                     % pump, valve 2, valve 3
S.ydist  = {'y_dist', 'dist', 'h_dist', 'd_hat'};  % disturbance estimate
S.tsolve = {'solver_time', 'solverTime', 'tsolve', 'solve_time'};
S.exitf  = {'exit_flag', 'exitflag', 'exitFlag'};
% CSTR (supervisor's Lyapunov NMPC model)
S.cstr_y    = {'y', 'ymeas', 'x', 'states'};       % [CA; T]
S.cstr_yset = {'y_set', 'yset', 'r'};
S.cstr_u    = {'u', 'uo'};                         % [CA0; Q]

TANK = 'SIM_THREE_TANK_SERVO'; REG = 'SIM_THREE_TANK_REGULATORY';
CSTR = 'A_SERVO_poly_shift2_u_ADAPT2_output';

switch lower(what)
    case 'list'
        for mdl = {TANK, REG}
            o = run_quiet(mdl{1}, 'pinn'); list_signals(o, mdl{1});
        end
        if exist(CSTR, 'file'), o = run_quiet(CSTR, ''); list_signals(o, CSTR); end
    case 'tank',    tank_figs(TANK, REG, S, outdir);
    case 'cstr',    cstr_fig(CSTR, S, outdir);
    case 'diagram', diagram_figs({TANK, REG, CSTR}, outdir);
    case 'all'
        tank_figs(TANK, REG, S, outdir); cstr_fig(CSTR, S, outdir); diagram_figs({TANK, REG, CSTR}, outdir);
end
fprintf('\nFigures written to %s\n', outdir);
end

% three-TANK
function tank_figs(TANK, REG, S, outdir)
tags = {'fp', 'pinn', 'ann'};
names = {'FP-NMPC', 'PINN-NMPC', 'ANN-NMPC'};
[col, ls] = palette();
for m = {TANK, REG}
    mdl = m{1}; isreg = contains(mdl, 'REGULATORY');
    R = struct();
    for k = 1:3
        o = run_quiet(mdl, tags{k});
        [R(k).t, R(k).y] = getsig(o, S.ymeas, mdl);
        [~, R(k).u]      = getsig(o, S.u, mdl);
        if k == 2   % PINN run only
            [ts, ysp] = getsig(o, S.yset, mdl); R(k).tsp = ts; R(k).ysp = ysp;
            try, [R(k).td, R(k).d] = getsig(o, S.ydist, mdl); catch, R(k).d = []; end
            try, [R(k).tt, R(k).tsol] = getsig(o, S.tsolve, mdl); catch, R(k).tsol = []; end
            try, [R(k).te, R(k).ef] = getsig(o, S.exitf, mdl); catch, R(k).ef = []; end
        end
    end
    use_model('pinn');

    % levels (3 x 1) and inputs (3 x 1), all three models overlaid
    f = newfig(6.5, 4.6);
    tl = tiledlayout(f, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ylab = {'$h_1$ (cm)', '$h_2$ (cm)', '$h_3$ (cm)'};
    ulab = {'$u_1$ (cm$^3$ s$^{-1}$)', '$u_2$ (--)', '$u_3$ (--)'};
    for i = 1:3
        ax = nexttile(tl, 2*i - 1); hold(ax, 'on');
        stairs(ax, R(2).tsp, R(2).ysp(:, i), 'Color', [0.5 0.5 0.5], 'LineStyle', '--', 'LineWidth', 0.8);
        for k = 1:3
            plot(ax, R(k).t, R(k).y(:, i), 'Color', col{k}, 'LineStyle', ls{k}, 'LineWidth', 1.0);
        end
        ylabel(ax, ylab{i}, 'Interpreter', 'latex'); style(ax);
        if i == 1, legend(ax, [{'Setpoint'}, names], 'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off'); end
        if i == 3, xlabel(ax, 'Time (s)'); end
        ax = nexttile(tl, 2*i); hold(ax, 'on');
        for k = 1:3
            stairs(ax, R(k).t, R(k).u(:, i), 'Color', col{k}, 'LineStyle', ls{k}, 'LineWidth', 1.0);
        end
        ylabel(ax, ulab{i}, 'Interpreter', 'latex'); style(ax);
        if i == 3, xlabel(ax, 'Time (s)'); end
    end
    tag = ternary(isreg, 'tank_regulatory', 'tank_servo');
    export(f, fullfile(outdir, tag));

    % PINN run: solver time + exit flag, and disturbance estimate
    if ~isempty(R(2).tsol)
        f = newfig(6.5, 2.6);
        tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        ax = nexttile(tl); stairs(ax, R(2).tt, R(2).tsol, 'Color', col{2}, 'LineWidth', 0.8); hold(ax, 'on');
        yline(ax, 2, '--', 'T_s = 2 s', 'Color', [0.5 0.5 0.5], 'LabelHorizontalAlignment', 'left', 'FontSize', 8);
        ylabel(ax, 'Solve time (s)'); style(ax);
        ax = nexttile(tl); stairs(ax, R(2).te, R(2).ef, 'Color', 'k', 'LineWidth', 0.8);
        ylabel(ax, 'Exit flag (--)'); xlabel(ax, 'Time (s)'); ylim(ax, [0 3]); style(ax);
        export(f, fullfile(outdir, [tag '_solver']));
    end
    if ~isempty(R(2).d)
        f = newfig(6.5, 3.0);
        tl = tiledlayout(f, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        dl = {'$\hat{d}_1$ (cm)', '$\hat{d}_2$ (cm)', '$\hat{d}_3$ (cm)'};
        for i = 1:3
            ax = nexttile(tl); stairs(ax, R(2).td, R(2).d(:, i), 'Color', col{2}, 'LineWidth', 1.0);
            ylabel(ax, dl{i}, 'Interpreter', 'latex'); style(ax);
            if i == 3, xlabel(ax, 'Time (s)'); end
        end
        export(f, fullfile(outdir, [tag '_disturbance']));
    end
end
end

% CSTR
function cstr_fig(CSTR, S, outdir)
if ~exist(CSTR, 'file')
    fprintf('CSTR model %s not on the path - add the Nonlinear CSTR/matlab folder and rerun.\n', CSTR); return
end
o = run_quiet(CSTR, '');
[t, y] = getsig(o, S.cstr_y, CSTR);
[~, u] = getsig(o, S.cstr_u, CSTR);
try, [tsp, ysp] = getsig(o, S.cstr_yset, CSTR); catch, tsp = []; ysp = []; end
[col, ~] = palette();
f = newfig(6.5, 3.6);
tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
lab = {'$C_A$ (kmol m$^{-3}$)', '$T$ (K)'}; ulab = {'$C_{A0}$ (kmol m$^{-3}$)', '$Q$ ($\times 10^5$ kJ h$^{-1}$)'};
for i = 1:2
    ax = nexttile(tl, i); hold(ax, 'on');
    if ~isempty(ysp), plot(ax, tsp, ysp(:, i), '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 0.8); end
    plot(ax, t, y(:, i), 'Color', col{2}, 'LineWidth', 1.0);
    ylabel(ax, lab{i}, 'Interpreter', 'latex'); style(ax);
    if i == 1 && ~isempty(ysp), legend(ax, {'Setpoint', 'PINN-NMPC'}, 'Box', 'off', 'Location', 'best'); end
    ax = nexttile(tl, i + 2);
    sc = 1; if i == 2, sc = 1e-5; end
    stairs(ax, t(1:size(u,1)), u(:, i) * sc, 'Color', 'k', 'LineWidth', 0.9);
    ylabel(ax, ulab{i}, 'Interpreter', 'latex'); xlabel(ax, 'Time (h)'); style(ax);
end
export(f, fullfile(outdir, 'cstr_lyapunov_nmpc'));
end

% DIAGRAMS
function diagram_figs(mdls, outdir)
for k = 1:numel(mdls)
    if exist(mdls{k}, 'file')
        load_system(mdls{k});
        print(['-s' mdls{k}], '-dpdf', fullfile(outdir, ['diagram_' mdls{k} '.pdf']));
        print(['-s' mdls{k}], '-dpng', '-r600', fullfile(outdir, ['diagram_' mdls{k} '.png']));
    end
end
end

% HELPERS
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

function list_signals(o, mdl)
fprintf('\n==== %s ====\nSimulationOutput fields: %s\n', mdl, strjoin(o.who, ', '));
if any(strcmp(o.who, 'logsout'))
    L = o.get('logsout');
    fprintf('logsout elements: %s\n', strjoin(L.getElementNames, ', '));
end
end

function [t, v] = getsig(o, cands, mdl)
w = o.who;
L = []; if any(strcmp(w, 'logsout')), L = o.get('logsout'); end
for c = cands
    nm = c{1};
    if ~isempty(L) && any(strcmp(L.getElementNames, nm))
        ts = L.getElement(nm).Values; [t, v] = unpack(ts); return
    end
    if any(strcmp(w, nm)), [t, v] = unpack(o.get(nm)); return, end
end
list_signals(o, mdl);
error('make_pub_figures:signal', 'None of {%s} found in %s. Edit the SIGNAL NAMES block.', strjoin(cands, ', '), mdl);
end

function [t, v] = unpack(x)
if isa(x, 'timeseries')
    t = x.Time; v = squeeze(x.Data);
elseif isstruct(x) && isfield(x, 'signals')
    t = x.time; v = x.signals.values;
elseif isa(x, 'Simulink.SimulationData.Dataset')
    [t, v] = unpack(x.getElement(1).Values);
else
    v = x; t = (0:size(x, 1) - 1).';
end
v = double(v); if size(v, 1) ~= numel(t), v = v.'; end
end

function f = newfig(w, h)
f = figure('Units', 'inches', 'Position', [1 1 w h], 'Color', 'w');
set(f, 'DefaultAxesFontName', 'Times New Roman', 'DefaultAxesFontSize', 9, ...
       'DefaultTextFontName', 'Times New Roman', 'DefaultLegendFontSize', 8);
end

function style(ax)
set(ax, 'FontName', 'Times New Roman', 'FontSize', 9, 'Box', 'on', 'TickDir', 'in', ...
        'LineWidth', 0.6, 'XMinorTick', 'off', 'YMinorTick', 'off', 'TickLabelInterpreter', 'latex');
axis(ax, 'tight'); yl = ylim(ax); pad = 0.06 * diff(yl); if pad == 0, pad = 1; end
ylim(ax, yl + [-pad pad]); grid(ax, 'off');
end

function [col, ls] = palette()
col = {[0 158 115]/255, [0 114 178]/255, [213 94 0]/255};   % FP green, PINN blue, ANN vermillion
ls  = {':', '-', '--'};
end

function export(f, base)
exportgraphics(f, [base '.pdf'], 'ContentType', 'vector');
exportgraphics(f, [base '.png'], 'Resolution', 600);
fprintf('saved %s\n', base);
close(f);
end

function r = ternary(c, a, b), if c, r = a; else, r = b; end, end
