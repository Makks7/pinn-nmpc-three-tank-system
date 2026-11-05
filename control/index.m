%% index.m - initialisation for the PINN-NMPC three-tank model
% Runs on its own through the model's InitFcn callback. On the real rig I
% still run this first before pressing Run in Simulink, just to be safe.
%
% This takes the place of the GRU setup from the earlier version. The PINN
% has no hidden states, so there is nothing to initialise for it and no
% weights to load here. pinn_predict loads models/pinn_weights.mat by itself
% the first time it is called and keeps it.

clc;
clear;

%% ---- sampling time -------------------------------------------------
% must be 2 s: the PINN was trained as a one-step map over Ts = 2 s.
% Running the loop at any other rate makes every prediction wrong.
model_const = struct();
model_const.ts = 2;

%% ---- operating point ------------------------------------------------
% Nominal point from Bamimore et al. (2021) Section 4.1
y_set = [14.29; 13.51; 16.06];      % tank levels [cm]
u_set = [100; 0.4; 0.2];            % pump [cm^3/s], valve 2, valve 3
d     = [0; 0; 0];                  % output-disturbance estimate

model_const.u_0   = u_set;
model_const.u_set = u_set;
model_const.x_0   = y_set;
model_const.y_set = y_set;
model_const.y_0   = y_set;
model_const.d_0   = d;

% leak valves (4-position valves) at nominal opening
model_const.c = [0.333; 0.333];

%% ---- disturbance rejector -------------------------------------------
adaptParam = 0.15;

%% ---- model identifier ------------------------------------------------
% Kept so the modelName port still has a signal. pinn_predict resolves the
% weight file by path, so this string is not used for dispatch.
networkModelName = "models/pinn_weights.mat";

description = "PINN-based NMPC for the cascaded three-tank system. " + ...
              "One-step predictor h(k+1) = f(h(k), u(k), c), Ts = 2 s.";

%% ---- hidden state placeholder ---------------------------------------
% The GRU needed a recurrent state threaded through the horizon. The PINN
% does not, but the NMPC block still has ho/hk ports, so feed them a scalar.
hiddenStates = 0;

%% ---- EKF / observer settings ----------------------------------------
% Retained from the predecessor's setup in case the Disturbance Rejector
% or a state estimator references them.
x0            = [1e-6; 1e-6; 1e-6; 0; 0; 0];
initial_covar = 1e-2*ones(6,1);

state_dist_noise = 1e-8*ones(3,1);
process_noise    = 1e-1*ones(3,1);
state_noise      = [process_noise; state_dist_noise];
output_noise     = 0.2*ones(3,1);

%% ---- report ----------------------------------------------------------
fprintf('index.m: PINN-NMPC initialised\n');
fprintf('   Ts = %g s   (must match the PINN training Ts)\n', model_const.ts);
fprintf('   y_set = [%.2f %.2f %.2f] cm\n', y_set);
fprintf('   u_set = [%.1f %.2f %.2f]\n', u_set);
fprintf('   leak valves c = [%.3f %.3f]\n', model_const.c);