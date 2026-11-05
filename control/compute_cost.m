function cost = compute_cost(u, data)
% COMPUTE_COST - NMPC cost for the 3-tank system with the PINN as predictor
%
% The total cost is made up of:
%   - output tracking (cost_y)
%   - input tracking error (cost_uerr)
%   - input rate penalty (cost_du)
%   - terminal Lyapunov penalty (cost_term)
%
% INPUT:
%   u    : [Nu x nu] stacked control inputs over the control horizon
%   data : struct from build_data with fields
%          Nu, Np, ny, nu, uo, u_set, y_set, Wy, Wu, Wuerr, Wdu, P
%
% OUTPUT:
%   cost : total NMPC cost [scalar]

Wy     = data.Wy;
Wu     = data.Wu;
Wuerr  = data.Wuerr;
Wdu    = data.Wdu;

% 1. Input moves over the control horizon
du = reshape([u(1,:) - data.uo; diff(u)], data.Nu, data.nu);   % [Nu x nu]

% 2. Predict the output trajectory with the PINN
[yk,~] = pinn_predict_horizon(data, u);                        % [Np x ny]

% 3. Output tracking cost
y_set_horizon = repmat(data.y_set, data.Np, 1);
e_y = yk - y_set_horizon;
cost_y = sum(diag(e_y*diag(Wy)*e_y'));

% 4. Input tracking cost
u_set_horizon = repmat(data.u_set, data.Nu, 1);
e_u = u_set_horizon - u;
cost_uerr = sum(diag(e_u*diag(Wuerr)*e_u'));

% 5. Input move cost
cost_du = sum(diag(du*diag(Wdu)*du'));

% 6. Terminal Lyapunov cost
y_term = yk(end,:);
e_term = data.y_set - y_term;
cost_term = e_term * data.P * e_term';

% 7. Control magnitude penalty (available, not currently summed in)
cost_u = sum(diag(u*diag(Wu)*u'));  %#ok<NASGU>

% 8. Total
v_low = max(repmat(data.y_min, data.Np, 1)-yk, 0);
v_high = max(yk - repmat(data.y_max, data.Np, 1) - yk, 0);
viol = [v_low(:); v_high(:)];
cost_soft = 1e3*sum(viol) + 1e4*sum(viol.^2);
cost = cost_y + cost_du + cost_uerr + cost_term + cost_soft;
end


function Wout = broadcast_weight(W, dim, horizon)
if isscalar(W)
    Wout = repmat(W,dim,horizon);
elseif isvector(W) && length(W) == dim
    Wout = repmat(W(:), 1, horizon);
elseif isequal(size(W), [dim, horizon])
    Wout = W;
else
    error('Invalid weight size: expected scalar, [%d x 1], or [%d x %d]', dim, dim, horizon);
end
end