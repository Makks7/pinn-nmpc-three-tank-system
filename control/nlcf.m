function [c, ceq] = nlcf(u, data)
% NLCF - Nonlinear inequality constraints for the PINN-NMPC three-tank problem
%
% INPUT:
%   u    : [Nu x nu] stacked control inputs over the control horizon
%   data : struct from build_data with fields
%          Nu, Np, ny, nu, uo, u_set, y_set, ts, alpha, P
%          du_min, du_max, u_min, u_max, y_min, y_max
%
% OUTPUT:
%   c   : all the inequality constraints together (c <= 0)
%   ceq : empty (no equality constraints)
%
% This uses pinn_predict_horizon, the same as the cost function. If the
% constraints and the cost used different predictions, fmincon would be
% getting two different stories about the trajectory and it converges badly.
du = reshape([u(1,:) - data.uo; diff(u)], data.Nu, data.nu);   % [Nu x nu]

% 2. Predict the output trajectory with the PINN
[yk, ~] = pinn_predict_horizon(data, u);                       % [Np x ny]

% 3. Inequality constraints, all in the form c <= 0
ineq_du_min = repmat(data.du_min, data.Nu, 1) - du;    % du >= du_min
ineq_du_max = du - repmat(data.du_max, data.Nu, 1);    % du <= du_max
ineq_u_min  = repmat(data.u_min,  data.Nu, 1) - u;     % u  >= u_min
ineq_u_max  = u - repmat(data.u_max,  data.Nu, 1);     % u  <= u_max
ineq_y_min  = repmat(data.y_min,  data.Np, 1) - yk;    % y  >= y_min
ineq_y_max  = yk - repmat(data.y_max, data.Np, 1);     % y  <= y_max

% 4. Terminal Lyapunov constraint
%    Inside the terminal region: shrink V below alpha.
%    Outside it: require V to be decreasing along the predicted trajectory.
y_end = yk(end,:);
x_end = y_end - data.y_set;
V_end = x_end * data.P * x_end';

x0 = data.yo - data.y_set;
V0 = x0 * data.P * x0';

if V0 > data.alpha
    xend   = (y_end - data.yo)/0.01;
    Vdot   = 2 * x0 * data.P * (xend / data.ts)';
    g_term = Vdot + 15 * abs(V0 / 100);
else
    g_term = V_end - data.alpha;
end

c = [
    ineq_du_min(:);
    ineq_du_max(:);
    ineq_u_min(:);
    ineq_u_max(:);
    % ineq_y_min(:);
    % ineq_y_max(:);
    g_term(:);
    ];

ceq = [];
end