function data = build_data(y_reg, u_reg, h, params)
% BUILD_DATA - Creates the NMPC data struct for GRU-based prediction & optimization
%
% INPUTS:
%   y_reg   [nReg x ny]  : recent output regressors [oldest...latest]
%   u_reg   [nReg x nu]  : recent input regressors [oldest...latest]
%   h       [H x L]     : current GRU hidden state
%   params  struct with fields:
%            .y_set   [1 x ny]     : tank level setpoints
%            .Nu, .Np, .ny, .nu, .ts, .alpha [scalar]
%            .modelName [string]
%            .dist: disturbance [scalar]
%            .Wy, .Wu, .Wdu, .Wuerr [scalar]/ [1 x (ny/nu)]
%            .P [ny x ny]
%            .u_set [1 x nu]
%            .norm_settings (cell {xmin, xmax})
%            .bounds with fields:
%                .ymin, .ymax        [1 x ny]
%                .u_min, .u_max      [1 x nu]
%                .du_min, .du_max    [1 x nu]
%
% OUTPUT:
%   data struct with fields ready for compute_cost, constraints, and prediction

% Dimensions and timing
data.Nu     = params.Nu;
data.Np     = params.Np;
data.ts     = params.ts;
data.ny     = params.ny;
data.nu     = params.nu;
% I/O and GRU model state
data.ho         = h;
% Scale input/output

data.y_reg      = y_reg; 
data.u_reg      = u_reg;
yo =  y_reg(end,:);
uo = u_reg(end,:);
% Extract upast from regression
u_size =size(u_reg);
nReg = u_size(1);

if nReg>1
    upast = u_reg(1:end-1,:);
    ypast =  y_reg(1:end-1,:);
else
    upast = u_reg;
    ypast = y_reg;
end

data.upast = upast;
data.ypast = ypast;
data.yo         = yo;        % last output measurement [1 x ny]
data.uo         = uo;        % last applied control [1 x nu]
data.y_set      = params.y_set';
data.u_set      = params.u_set';
%
data.modelName  = params.modelName;
data.e          = params.dist;

% NMPC weight matrices
data.Wy     = params.Wy;
data.Wu     = params.Wu;
data.Wdu    =  params.Wdu;
data.Wuerr  =  params.Wuerr;
data.P      = params.P;
data.alpha  = params.alpha;

% Constraints over prediction/control horizon [ny x Np]/[nu x Nu]
b            = params.bounds;
data.y_min   = b.ymin;
data.y_max   = b.ymax;
data.u_min   = b.u_min;
data.u_max   = b.u_max;
data.du_min  = b.du_min;
data.du_max  = b.du_max;

% Initial params for solver
data.u_min_horizon   = repmat(b.u_min, params.Nu, 1);% [Nu x nu]

data.u_max_horizon   = repmat(b.u_max, params.Nu, 1);% [Nu x nu]

% data.u_initial_horizon = u_reg; % [Nu x nu]
data.u_initial_horizon = repmat(uo ,params.Nu ,1); % [Nu x nu]

% Saving horizon prediction to prevent two loop calls
data.horizon_pred = zeros(params.Np,params.ny);
end
