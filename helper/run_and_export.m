function run_and_export(run_id, Tsim)
% RUN_AND_EXPORT  Sets up logging, runs the simulation and writes a CSV for PyTorch.
%
%   run_and_export('train01', 20000)
%   run_and_export('smoke',   500)
%
% Steps:
%   1. turns on signal logging for u1,u2,u3,h1,h2,h3 (port level, from code)
%   2. sets StopTime and the choose_signal Constant to Tsim
%   3. runs the simulation
%   4. pulls the data from out.yout, subsamples to 2 s, does a quick check and writes the CSV
%
% The real tank height is 35 cm (I measured it on the rig).

if nargin < 1, run_id = 'train01'; end
if nargin < 2, Tsim   = 20000;     end

mdl      = 'three_tank_open_loop';
blkName  = 'Three tank system';
saveDir  = 'data';
HMAX     = 35;        % physical tank height [cm]
C2_VALUE = 0.333;
C3_VALUE = 0.333;
STRIDE   = 4;         % solver 0.5 s -> 2 s grid

if ~exist(saveDir,'dir'), mkdir(saveDir); end
if ~bdIsLoaded(mdl), load_system(mdl); end

%% ---- 1. enable logging on the six signals -------------------------
blk = [mdl '/' blkName];
try
    ph = get_param(blk,'PortHandles');
catch
    error('Block "%s" not found. Run: find_system(''%s'',''SearchDepth'',1,''BlockType'',''SubSystem'')', blkName, mdl);
end

% inputs: logging lives on the SOURCE port of the wire feeding each inport
for i = 1:3
    lh = get_param(ph.Inport(i),'Line');
    if lh == -1, error('Input port %d of %s has no wire.', i, blkName); end
    src = get_param(lh,'SrcPortHandle');
    set_param(lh,  'Name', sprintf('u%d',i));
    set_param(src, 'DataLogging', 'on');
    set_param(src, 'DataLoggingNameMode', 'SignalName');
end

% outputs: logging lives directly on the subsystem outports
for i = 1:3
    lh = get_param(ph.Outport(i),'Line');
    if lh ~= -1, set_param(lh,'Name',sprintf('h%d',i)); end
    set_param(ph.Outport(i), 'DataLogging', 'on');
    set_param(ph.Outport(i), 'DataLoggingNameMode', 'SignalName');
end

set_param(mdl, 'SignalLogging','on', 'SignalLoggingName','logsout');
set_param(mdl, 'ReturnWorkspaceOutputs','on');
set_param(mdl, 'StopTime', num2str(Tsim));

%% ---- 2. set the choose_signal constant to match Tsim ---------------
% Each generator subsystem has its own sim_time Constant. Stagger them so
% the five regime windows of u1/u2/u3 do not switch at the same instants.
consts = find_system(mdl,'SearchDepth',1,'BlockType','Constant');
big = {};
for k = 1:numel(consts)
    v = get_param(consts{k},'Value');
    if ~isempty(regexp(v,'^\d+(\.\d+)?$','once')) && str2double(v) >= 100
        big{end+1} = consts{k}; %#ok<AGROW>
    end
end
stagger = [1.0, 0.875, 1.125];      % 20000 -> 20000, 17500, 22500
for k = 1:numel(big)
    val = round(Tsim * stagger(min(k,3)));
    set_param(big{k},'Value',num2str(val));
    fprintf('set %s = %d\n', big{k}, val);
end
if isempty(big)
    warning('No sim_time Constant found. Set them by hand to ~%d.', Tsim);
end

save_system(mdl);

%% ---- 3. simulate -------------------------------------------------------
fprintf('\nSimulating %s for %d s ...\n', mdl, Tsim);
out = sim(mdl);

%% ---- 4. extract ---------------------------------------------------------
if ~isprop(out,'logsout') || isempty(out.logsout)
    error('out.logsout is empty after simulation. Logging did not take.');
end
ds    = out.logsout;
names = cellstr(ds.getElementNames());
fprintf('Logged: %s\n', strjoin(names, ', '));

want = {'h1','h2','h3','u1','u2','u3'};
missing = setdiff(want, names);
if ~isempty(missing)
    error('Missing from logsout: %s', strjoin(missing, ', '));
end

time = ds.get('h1').Values.Time(:);
N    = numel(time);
sig  = struct();
for i = 1:numel(want)
    v = ds.get(want{i}).Values.Data(:);
    if numel(v) ~= N, error('%s length %d vs time %d', want{i}, numel(v), N); end
    if all(v == 0), warning('%s is all zeros.', want{i}); end
    sig.(want{i}) = v;
end

idx  = 1:STRIDE:N;
time = time(idx);
for i = 1:numel(want), sig.(want{i}) = sig.(want{i})(idx); end
N = numel(time);
Ts = median(diff(time));

%% ---- 5. sanity report ---------------------------------------------------
fprintf('\n=== %s : %d samples, Ts = %g s ===\n', run_id, N, Ts);
fprintf('--- level coverage (tank height %d cm) ---\n', HMAX);
for nm = {'h1','h2','h3'}
    v = sig.(nm{1});
    fprintf('   %s: [%6.2f %6.2f]   mean %6.2f   std %5.2f\n', ...
            nm{1}, min(v), max(v), mean(v), std(v));
end
fprintf('--- input coverage ---\n');
fprintf('   u1: [%6.1f %6.1f]\n', min(sig.u1), max(sig.u1));
fprintf('   u2: [%6.3f %6.3f]\n', min(sig.u2), max(sig.u2));
fprintf('   u3: [%6.3f %6.3f]\n', min(sig.u3), max(sig.u3));

allh  = [sig.h1; sig.h2; sig.h3];
satHi = mean(allh > HMAX-1) * 100;
satLo = mean(allh < 0.5)    * 100;
fprintf('   above %d cm: %.1f%%    below 0.5 cm: %.1f%%\n', HMAX-1, satHi, satLo);
if satHi > 5, warning('%.1f%% at the ceiling - lower u1 upper band slightly.', satHi); end
if satLo > 5, warning('%.1f%% near empty.', satLo); end
if any(~isfinite(allh)), warning('non-finite values present'); end
if ~isreal(allh),        warning('COMPLEX values - a level went negative'); end

%% ---- 6. write -----------------------------------------------------------
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
base  = char(sprintf('sim_%s_%s', run_id, stamp));

T = table(time, sig.h1, sig.h2, sig.h3, sig.u1, sig.u2, sig.u3, ...
          repmat(C2_VALUE,N,1), repmat(C3_VALUE,N,1), ...
          repmat(string(run_id),N,1), repmat(Ts,N,1), ...
    'VariableNames', {'t','h1','h2','h3','u1','u2','u3','c2','c3','run_id','Ts'});

csvFile = char(fullfile(saveDir, [base '.csv']));
writetable(T, csvFile);
matFile = char(fullfile(saveDir, [base '.mat']));
save(matFile, 'sig', 'time', 'run_id', 'Ts');

fprintf('\nCSV: %s\nMAT: %s\n', csvFile, matFile);
end