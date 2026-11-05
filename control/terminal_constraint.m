function [xPx, Tconst] = terminal_constraint(u_end, data)
% TERMINAL_CONSTRAINT - Lyapunov terminal diagnostics for the NMPC solution.
%
% INPUT:
%   u_end : [1 x nu] last input of the optimal control sequence
%   data  : NMPC data struct from build_data
%
% OUTPUT:
%   xPx    : terminal Lyapunov value x'Px at the end of the horizon
%   Tconst : xPx - alpha, which is the terminal constraint margin
%            (<= 0 means the predicted terminal state is inside the
%             terminal region)
%
% This is only for diagnostics. The constraint that actually affects the
% control law is in nlcf.m. These two values go to the scopes so I can see
% if the terminal region is being reached.
u_hor = repmat(u_end(:).', data.Nu, 1);
[yk, ~] = pinn_predict_horizon(data, u_hor);

y_term = yk(end,:);
x_term = y_term - data.y_set;

xPx    = x_term * data.P * x_term';
Tconst = xPx - data.alpha;
end