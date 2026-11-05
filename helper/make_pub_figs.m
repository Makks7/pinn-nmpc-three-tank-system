function make_pub_figs(simOut, tag, varargin)
%MAKE_PUB_FIGS  Figures for the thesis/paper from a PINN-NMPC run.
%
%   make_pub_figs(out, 'rt_startup')
%   make_pub_figs(out, 'sim_servo', 'Width', 8.5)        % single column
%   make_pub_figs(out, 'rt_servo', 'Font', 'Arial')
%
% Saves to   figures/<tag>_*.pdf  (vector, for the thesis / paper)
%       and  figures/<tag>_*.png  (600 dpi, for slides and for sending on Telegram)
% and also   figures/<tag>_captions.txt with a caption and source line for
%            each figure, so I can paste them under the figures.
%
% Figures it makes (if the signals are there):
%   1  <tag>_servo      3x2  levels vs setpoints | manipulated inputs
%   2  <tag>_predict    3x1  measured vs PINN one-step prediction
%   3  <tag>_error      3x1  prediction error with +/-1 sigma band
%   4  <tag>_solver     2x1  solver time and fmincon exit flag
%   5  <tag>_dist       3x1  output disturbance estimate
%
% Line styles, so the figures still read well when printed in black and white:
%   plant / measured : solid,   black
%   setpoint         : dashed,  dark red
%   prediction       : dash-dot, dark blue
%   inputs           : solid,   black, stairs
p = inputParser;
p.addParameter('OutDir',  'figures');
p.addParameter('Width',   17);         % cm. 17 = double column, 8.5 = single
p.addParameter('Font',    'Times New Roman');
p.addParameter('FontSize', 9);
p.addParameter('Source',  '');         % extra text for the source line
p.parse(varargin{:});
o = p.Results;

if ~exist(o.OutDir, 'dir'), mkdir(o.OutDir); end

S = struct('font', o.Font, 'fs', o.FontSize, 'w', o.Width, 'dir', o.OutDir, ...
           'tag', tag);

% signals
sig = struct();
sig.ymeas = grab(simOut, {'ymeas','y','h','ymeas_log','y_meas'});
sig.yset  = grab(simOut, {'yset','y_set','r','ysp','setpoint'});
sig.u     = grab(simOut, {'u','uopt','u_log','uk'});
sig.ypred = grab(simOut, {'y_pred','ypred','yhat','y_hat'});
sig.ydist = grab(simOut, {'y_dist','ydist','dist','d_hat'});
sig.eflag = grab(simOut, {'exitflag','exit_flag','Exit flag','eflag'});
sig.stime = grab(simOut, {'solver_time','solvertime','solver time','Ecount'});

if isempty(sig.ymeas)
    error(['No measured-level signal found. Mark the ymeas line with ' ...
           '"Log Selected Signals", or rename it to one of: ymeas, y, h.']);
end
t = sig.ymeas.t;

fprintf('make_pub_figs: %d samples, %.0f s', numel(t), t(end)-t(1));
got = fieldnames(sig);
have = got(~structfun(@isempty, sig));
fprintf('   signals: %s\n', strjoin(have', ', '));

caps = {};

% 1 servo
if ~isempty(sig.u)
    f = newfig(S, S.w, 13);
    T = tiledlayout(f, 3, 2, 'TileSpacing','compact', 'Padding','compact');

    ynm = {'h_1','h_2','h_3'};
    unm = {'u_1  [cm^3 s^{-1}]','u_2  [-]','u_3  [-]'};

    for i = 1:3
        % left column: level and setpoint
        ax = nexttile(T, 2*i-1);
        hold(ax,'on');
        if ~isempty(sig.yset)
            stairs(ax, sig.yset.t, sig.yset.y(:,i), '--', ...
                   'Color',[0.70 0.10 0.10], 'LineWidth',0.9);
        end
        plot(ax, t, sig.ymeas.y(:,i), '-', 'Color','k', 'LineWidth',1.1);
        ylabel(ax, sprintf('%s  [cm]', ynm{i}));
        axfix(ax, S);
        if i == 1
            if ~isempty(sig.yset)
                legend(ax, {'setpoint','plant'}, 'Location','southeast', ...
                       'Box','off', 'FontSize',S.fs-1);
            end
        end
        if i == 3, xlabel(ax, 'time  [s]'); else, ax.XTickLabel = []; end

        % right column: manipulated input
        ax = nexttile(T, 2*i);
        stairs(ax, sig.u.t, sig.u.y(:,i), '-', 'Color','k', 'LineWidth',1.0);
        ylabel(ax, unm{i});
        axfix(ax, S);
        if i == 3, xlabel(ax, 'time  [s]'); else, ax.XTickLabel = []; end
    end
    caps{end+1} = savefig_(f, S, 'servo', ...
        'Closed-loop response of the cascaded three-tank system under PINN-NMPC. Left: tank levels against their setpoints. Right: manipulated inputs (pump flowrate and the two proportional valve openings).', o.Source);
end

% 2 predict
if ~isempty(sig.ypred)
    f = newfig(S, S.w*0.82, 12);
    T = tiledlayout(f, 3, 1, 'TileSpacing','compact', 'Padding','compact');
    ynm = {'h_1','h_2','h_3'};
    for i = 1:3
        ax = nexttile(T);
        hold(ax,'on');
        plot(ax, t, sig.ymeas.y(:,i), '-',  'Color','k', 'LineWidth',1.1);
        plot(ax, sig.ypred.t, sig.ypred.y(:,i), '-.', ...
             'Color',[0.00 0.20 0.60], 'LineWidth',1.0);
        ylabel(ax, sprintf('%s  [cm]', ynm{i}));
        axfix(ax, S);
        if i == 1
            legend(ax, {'measured','PINN prediction'}, 'Location','best', ...
                   'Box','off', 'FontSize',S.fs-1);
        end
        if i == 3, xlabel(ax, 'time  [s]'); else, ax.XTickLabel = []; end
    end
    caps{end+1} = savefig_(f, S, 'predict', ...
        'One-step-ahead PINN prediction against the measured tank levels during closed-loop operation.', o.Source);

    % 3 error
    [tc, Ym, Yp] = align2(t, sig.ymeas.y, sig.ypred.t, sig.ypred.y);
    E = Yp - Ym;
    f = newfig(S, S.w*0.82, 11);
    T = tiledlayout(f, 3, 1, 'TileSpacing','compact', 'Padding','compact');
    for i = 1:3
        ax = nexttile(T); hold(ax,'on');
        s = std(E(:,i), 'omitnan');
        fill(ax, [tc; flipud(tc)], [s*ones(size(tc)); -s*ones(size(tc))], ...
             [0.85 0.85 0.85], 'EdgeColor','none');
        plot(ax, tc, E(:,i), '-', 'Color','k', 'LineWidth',0.8);
        yline(ax, 0, '-', 'Color',[0.4 0.4 0.4], 'LineWidth',0.6);
        ylabel(ax, sprintf('e_{h%d}  [cm]', i));
        axfix(ax, S);
        text(ax, 0.985, 0.90, sprintf('RMSE %.3f cm', rms_(E(:,i))), ...
             'Units','normalized', 'HorizontalAlignment','right', ...
             'FontName',S.font, 'FontSize',S.fs-1);
        if i == 3, xlabel(ax, 'time  [s]'); else, ax.XTickLabel = []; end
    end
    caps{end+1} = savefig_(f, S, 'error', ...
        'Prediction error of the PINN during closed-loop operation. The shaded band is one standard deviation.', o.Source);
end

% 4 solver
if ~isempty(sig.eflag)
    f = newfig(S, S.w*0.82, 7.5);
    T = tiledlayout(f, 2, 1, 'TileSpacing','compact', 'Padding','compact');

    ax = nexttile(T);
    if ~isempty(sig.stime)
        stairs(ax, sig.stime.t, sig.stime.y(:,1), '-', 'Color','k', 'LineWidth',0.9);
        ylabel(ax, 'solve time  [s]');
    else
        axis(ax,'off');
    end
    axfix(ax, S); ax.XTickLabel = [];

    ax = nexttile(T);
    stairs(ax, sig.eflag.t, sig.eflag.y(:,1), '-', 'Color','k', 'LineWidth',0.9);
    ylabel(ax, 'exit flag  [-]');
    xlabel(ax, 'time  [s]');
    ylim(ax, [min(sig.eflag.y(:,1))-0.5, max(sig.eflag.y(:,1))+0.5]);
    axfix(ax, S);
    caps{end+1} = savefig_(f, S, 'solver', ...
        'Solver diagnostics. Top: time taken by fmincon at each control step. Bottom: fmincon exit flag, where 2 denotes a converged solution and a negative value denotes failure to find a feasible point.', o.Source);
end

% 5 dist
if ~isempty(sig.ydist)
    f = newfig(S, S.w*0.82, 10);
    T = tiledlayout(f, 3, 1, 'TileSpacing','compact', 'Padding','compact');
    for i = 1:3
        ax = nexttile(T);
        stairs(ax, sig.ydist.t, sig.ydist.y(:,i), '-', 'Color','k', 'LineWidth',0.9);
        ylabel(ax, sprintf('d_{h%d}  [cm]', i));
        axfix(ax, S);
        if i == 3, xlabel(ax, 'time  [s]'); else, ax.XTickLabel = []; end
    end
    caps{end+1} = savefig_(f, S, 'dist', ...
        'Output-disturbance estimate produced by the disturbance rejector, which is what makes the loop offset-free.', o.Source);
end

% captions
cf = fullfile(S.dir, sprintf('%s_captions.txt', tag));
fid = fopen(cf, 'w');
for k = 1:numel(caps), fprintf(fid, '%s\n\n', caps{k}); end
fclose(fid);
fprintf('\nwrote %d figures (pdf + png) and %s\n', numel(caps), cf);
end


% =====================================================================
function f = newfig(S, wcm, hcm)
f = figure('Units','centimeters', 'Position',[2 2 wcm hcm], ...
           'Color','w', 'PaperUnits','centimeters', ...
           'PaperSize',[wcm hcm], 'PaperPosition',[0 0 wcm hcm]);
end

function axfix(ax, S)
set(ax, 'FontName',S.font, 'FontSize',S.fs, 'Box','on', ...
        'LineWidth',0.6, 'TickDir','in', 'XGrid','on', 'YGrid','on', ...
        'GridAlpha',0.12, 'Layer','top');
end

function cap = savefig_(f, S, name, text_, src)
base = fullfile(S.dir, sprintf('%s_%s', S.tag, name));
exportgraphics(f, [base '.pdf'], 'ContentType','vector', 'BackgroundColor','w');
exportgraphics(f, [base '.png'], 'Resolution',600,      'BackgroundColor','w');
close(f);
if isempty(src)
    src = sprintf('Source: %s, generated %s.', S.tag, datestr(now,'dd mmm yyyy'));
else
    src = sprintf('Source: %s', src);
end
cap = sprintf('%s\n%s\n%s', upper(name), text_, src);
fprintf('   %s.pdf / .png\n', base);
end

function r = rms_(x)
x = x(~isnan(x)); r = sqrt(mean(x.^2));
end

function [tc, A, B] = align2(ta, a, tb, b)
% put two signals on the shorter common time base
n = min(numel(ta), numel(tb));
tc = ta(1:n); A = a(1:n,:); B = b(1:n,:);
end

function s = grab(simOut, names)
% Find a logged signal by any of several names. Looks in logsout, then
% yout, then the base workspace. Returns [] if nothing matches.
s = [];
srcs = {};
if isa(simOut,'Simulink.SimulationOutput')
    if isprop(simOut,'logsout') && ~isempty(simOut.logsout), srcs{end+1} = simOut.logsout; end
    if isprop(simOut,'yout')    && ~isempty(simOut.yout),    srcs{end+1} = simOut.yout;    end
elseif isa(simOut,'Simulink.SimulationData.Dataset')
    srcs{end+1} = simOut;
end

for k = 1:numel(srcs)
    ds = srcs{k};
    try
        have = cellstr(ds.getElementNames());
    catch
        continue
    end
    for j = 1:numel(names)
        hit = find(strcmpi(have, names{j}), 1);
        if ~isempty(hit)
            el = ds.get(have{hit});
            s.t = el.Values.Time(:);
            d  = el.Values.Data;
            if ndims(d) == 3, d = squeeze(d)'; end     %#ok<ISMAT>
            if size(d,1) ~= numel(s.t), d = d.'; end
            s.y = d;
            return
        end
    end
end

% last resort: a timeseries sitting in the base workspace
for j = 1:numel(names)
    nm = matlab.lang.makeValidName(names{j});
    if evalin('base', sprintf('exist(''%s'',''var'')', nm))
        v = evalin('base', nm);
        if isa(v,'timeseries')
            s.t = v.Time(:); s.y = v.Data; return
        end
    end
end
end