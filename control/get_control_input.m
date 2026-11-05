function [uk, yk, hk, fval, exitflag, elapsed, xPx, Tconst] = get_control_input(y_reg, u_reg, h, params)
% GET_CONTROL_INPUT - Solves the NMPC problem with the PINN as the predictor
%
% INPUTS:
%   y_reg  : Regressed output [nReg x ny]
%   u_reg  : Regressed input  [nReg x nu]
%   h      : Hidden state (the PINN does not use it, just passed through)
%   params : struct built in nmpc.m
%
% OUTPUTS:
%   uk       [1 x nu]  : first optimal control move
%   yk       [ny x 1]  : one-step predicted output
%   hk                 : hidden state, unchanged
%   fval, exitflag, elapsed, xPx, Tconst : diagnostics
%
% The PINN only needs the current state, so only the last row of the
% regressors is used. The older lags in y_reg/u_reg are still there because
% the GRU version this was built on used them, and I did not want to change
% the block interface.
data = build_data(y_reg, u_reg, h, params);

% Optimisation options
% Display is off: at Ts = 2 s a 1500 s run is 750 solves, and a convergence
% table per solve floods the Command Window and slows the simulation.
opts = optimoptions('fmincon', ...
    'Algorithm', 'sqp', ...
    'Display', 'off', ...
    'MaxIterations', 1000, ...
    'StepTolerance', 1e-3, ...
    'FunctionTolerance', 1e-3, ...
    'ConstraintTolerance', 1e-3, ...
    'FiniteDifferenceStepSize', 1e-3, ...
    'FiniteDifferenceType', 'central');

% Solve the NMPC problem
tic;
[uopt, fval, exitflag] = fmincon(...
    @(u) compute_cost(u, data), ...
    data.u_initial_horizon, [], [], [], [], ...
    data.u_min_horizon, data.u_max_horizon, ...
    @(u) nlcf(u, data), ...
    opts);
elapsed = toc;

% Terminal Lyapunov diagnostics
[xPx, Tconst] = terminal_constraint(uopt(end, :), data);

% First move of the optimal sequence
uk = uopt(1,:);

% If the solver failed, fall back to the last applied input
if exitflag <= 0
    warning('NMPC did not converge (flag=%d). Using previous input.', exitflag);
    uk = data.uo;
    yk = data.yo;
    hk = data.ho;
    return;
end

% One-step prediction with the PINN
[yk_step, hk] = pinn_predict_step(data, uk);
yk = double(yk_step);
end