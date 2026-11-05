function set_servo(mdl, varargin)
% Servo schedule with a startup ramp from empty tanks.
%   set_servo('REAL_THREE_TANK')
% The setpoint ramps from 0 to the operating point over 'Ramp' s, holds, then steps.
if nargin < 1 || isempty(mdl), mdl = bdroot; end
p = inputParser;
p.addParameter('Steps', [400 800 1200]);
p.addParameter('Start', [14.29 13.51 16.06]);
p.addParameter('Final', [20 20 20]);
p.addParameter('Ramp',  150);
p.addParameter('Tsim',  1500);
p.addParameter('Block', '');
p.parse(varargin{:});
o = p.Results;

open_system(mdl);
blk = o.Block;
if isempty(blk)
    hits = find_system(mdl,'LookUnderMasks','all','IncludeCommented','on','MaskType','Sigbuilder block');
    if isempty(hits)
        hits = find_system(mdl,'SearchDepth',1,'IncludeCommented','on','Name','Servo');
    end
    if isempty(hits), error('No Signal Builder found in %s.', mdl); end
    blk = hits{1};
end
open_system(blk);

T = cell(3,1); D = cell(3,1);
for i = 1:3
    ts   = o.Steps(i);
    T{i} = [0, o.Ramp,     ts,         ts,         o.Tsim];
    D{i} = [0, o.Start(i), o.Start(i), o.Final(i), o.Final(i)];
end
signalbuilder(blk, 'set', 1:3, 1, T, D);
set_param(mdl, 'StopTime', num2str(o.Tsim));
save_system(mdl);
fprintf('Servo set: ramp 0 -> start over %g s, steps at %s s, stop %g s\n', ...
        o.Ramp, mat2str(o.Steps), o.Tsim);
end