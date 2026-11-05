function setup_nmpc()
%SETUP_NMPC  Puts the NMPC tuning parameters in the base workspace.
% Run it once before simulating the closed loop.
%
% The tuning is from Bamimore et al. (2021) Section 4.5.3, which was done on
% this same rig. I only tightened the input bounds to stay inside the range
% the PINN was trained on.

N.Np = 40;                 % prediction horizon (80 s at Ts = 2 s)
N.Nc = 2;                  % control horizon
N.Ts = 2;                  % sampling time [s]

N.wy   = diag([1 1 1]);            % output tracking weights
N.wdu  = diag([0.005 1000 1000]);  % move suppression: pump cheap, valves expensive

% input bounds
% IMPORTANT: these are the PINN's TRAINING range, not the actuator range.
% The pump can physically do 10-200 cm^3/s, but the network only ever saw
% 55-148. Letting the optimiser leave that box means extrapolating, and
% neural networks extrapolate badly. Retrain on wider data before widening.
N.umin = [ 55; 0.05; 0.05];
N.umax = [145; 1.00; 0.95];

% move-rate limits (per sample)
N.dumax = [20; 0.1; 0.1];

% output constraints [cm]
N.ymin = [ 1;  1;  1];
N.ymax = [33; 33; 33];     % 35 cm tanks, 2 cm margin

% leak valves held at nominal unless a disturbance test overrides
N.c = [0.333; 0.333];

% fmincon options
N.opts = optimoptions('fmincon', ...
    'Algorithm','sqp', ...
    'Display','off', ...
    'MaxIterations',30, ...
    'OptimalityTolerance',1e-4, ...
    'StepTolerance',1e-6);

assignin('base','NMPC',N);

% nominal operating point from the paper, for reference
assignin('base','u_nominal', [100; 0.4; 0.2]);
assignin('base','y_nominal', [14.29; 13.51; 16.06]);

fprintf(['NMPC configured: Np=%d Nc=%d Ts=%gs\n' ...
         '   u1 in [%g %g]  u2 in [%g %g]  u3 in [%g %g]  (PINN training envelope)\n'], ...
        N.Np, N.Nc, N.Ts, N.umin(1),N.umax(1), N.umin(2),N.umax(2), N.umin(3),N.umax(3));
end