function u = nmpc_pinn(y, r, u_prev)
%NMPC_PINN  One NMPC step with the PINN as the prediction model.
%
%   u = nmpc_pinn(y, r, u_prev)
%     y      : [h1;h2;h3] measured levels now      [cm]
%     r      : [r1;r2;r3] setpoints                [cm]
%     u_prev : [u1;u2;u3] input applied last step
%     u      : [u1;u2;u3] input to apply now
%
% This is a standalone solver that test_nmpc_offline uses. In Simulink the
% loop goes through nmpc.m / get_control_input.m. I wrote this one so I could
% test the loop in plain MATLAB first before wiring anything.
%
% Speed: the weights are kept in a persistent struct and the forward pass is
% written out inline here. That saves about 40 function calls and 40 isempty
% checks per cost evaluation, and it came out about 3-4x faster than calling
% pinn_predict in a loop.

persistent NMPC NET warm
if isempty(NMPC)
    NMPC = evalin('base','NMPC');
end
if isempty(NET)
    NET = load_net();
end

y = y(:); r = r(:); u_prev = u_prev(:);
Nc = NMPC.Nc;

if isempty(warm) || numel(warm) ~= 3*Nc
    warm = zeros(3*Nc,1);
end

lb = repmat(-NMPC.dumax, Nc, 1);
ub = repmat( NMPC.dumax, Nc, 1);

cost = @(dU) nmpc_cost(dU, y, r, u_prev, NMPC, NET);
[A, b] = abs_input_constraints(u_prev, NMPC);

try
    dU = fmincon(cost, warm, A, b, [], [], lb, ub, [], NMPC.opts);
catch
    dU = warm;                          % keep the previous plan if it fails
end

warm = [dU(4:end); zeros(3,1)];         % shift for the next step

u = min(max(u_prev + dU(1:3), NMPC.umin), NMPC.umax);
end


% =====================================================================
function J = nmpc_cost(dU, y, r, u_prev, N, NET)
J = 0;
u = u_prev;
h = y;
c = N.c;
Np = N.Np; Nc = N.Nc;
wy = N.wy; wdu = N.wdu;
ymin = N.ymin; ymax = N.ymax;
umin = N.umin; umax = N.umax;

for i = 1:Np
    if i <= Nc
        d = dU(3*(i-1)+1 : 3*i);
        u = min(max(u + d, umin), umax);
        J = J + d' * wdu * d;
    end

    % inlined PINN forward pass
    x  = [h; u; c];
    a  = 2*(x - NET.x_lo)./NET.x_rng - 1;
    for L = 1:NET.nL-1
        a = tanh(NET.W{L}*a + NET.b{L});
    end
    yn = NET.W{NET.nL}*a + NET.b{NET.nL};
    h  = (yn + 1)/2 .* NET.y_rng + NET.y_lo;
    % ----------------------------------------------------------------

    e = r - h;
    J = J + e' * wy * e;

    over  = max(h - ymax, 0);
    under = max(ymin - h, 0);
    J = J + 1e4 * (over'*over + under'*under);
end
end


% =====================================================================
function NET = load_net()
% Cache the weights and pre-compute the scaling ranges once.
here = fileparts(mfilename('fullpath'));
f = fullfile(here, '..', 'models', 'pinn_weights.mat');
if ~exist(f,'file'), f = fullfile(here, 'models', 'pinn_weights.mat'); end
if ~exist(f,'file')
    error('pinn_weights.mat not found. Run train_pinn.py first.');
end
S = load(f);
NET.nL = S.n_layers;
NET.W  = cell(NET.nL,1);
NET.b  = cell(NET.nL,1);
for i = 1:NET.nL
    NET.W{i} = S.(sprintf('W%d', i));
    NET.b{i} = S.(sprintf('b%d', i));
end
NET.x_lo  = S.x_lo;
NET.x_rng = S.x_hi - S.x_lo;
NET.y_lo  = S.y_lo;
NET.y_rng = S.y_hi - S.y_lo;
fprintf('nmpc_pinn: cached %d-layer network\n', NET.nL);
end


% =====================================================================
function [A, b] = abs_input_constraints(u_prev, N)
% Cumulative moves must keep u inside [umin, umax] at every step of the
% control horizon:   umin <= u_prev + sum_{j<=i} du(j) <= umax
Nc = N.Nc;
A = zeros(2*3*Nc, 3*Nc);
b = zeros(2*3*Nc, 1);
row = 1;
for i = 1:Nc
    S = zeros(3, 3*Nc);
    for j = 1:i
        S(:, 3*(j-1)+1 : 3*j) = eye(3);
    end
    A(row:row+2, :) =  S;  b(row:row+2) =   N.umax - u_prev;  row = row + 3;
    A(row:row+2, :) = -S;  b(row:row+2) = -(N.umin - u_prev); row = row + 3;
end
end