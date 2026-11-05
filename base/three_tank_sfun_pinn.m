function three_tank_sfun_pinn(block)
% Level-2 MATLAB S-Function for the cascaded three-tank system.
% Fixed version of three_tank_sfun_no_dist.m that I used to generate the
% PINN training data.
%
% It has the same 5 ports as three_tank_sfun_no_dist, so it can be dropped
% into the model without rewiring anything.
%
% What I fixed:
%   1. Took out the fprintf in Derivatives. It was printing millions of lines
%      and slowing the long simulations to a crawl
%   2. Initial state is now a column vector (it was the row [5,5,5])
%   3. Added guards for negative h1 and h2. Before, when h went below zero,
%      (2*g*h)^alpha gave complex numbers
%   4. A2 is clamped at Hmax so the area does not keep growing past the real tank
%   5. Initial levels now come from the block dialog parameter
%      (e.g. model_const.x_0) and are no longer hard-coded
%
% The physics, constants and identified alphas are the same as the original.
%
% Inputs (all scalar):
%   1: U1  pump flowrate            [cm^3/s]
%   2: U2  prop. valve 2 opening    [-]
%   3: U3  prop. valve 3 opening    [-]
%   4: C2  leak valve, tank 2       [-]   (4-position valve 1)
%   5: C3  leak valve, tank 3       [-]   (4-position valve 2)
% Dialog parameter:
%   1: x0  initial levels [h1; h2; h3]   [cm]
% Output:
%   1: [h1; h2; h3]                 [cm]
setup(block);

function setup(block)
    block.NumInputPorts  = 5;
    block.NumOutputPorts = 1;
    block.NumContStates  = 3;
    % CHANGE 1: one dialog parameter = initial levels
    block.NumDialogPrms  = 1;
    for i = 1:5
        block.InputPort(i).Dimensions        = 1;
        block.InputPort(i).DirectFeedthrough = false;
    end
    block.OutputPort(1).Dimensions = 3;
    block.SampleTimes = [0 0];
    block.SimStateCompliance = 'DefaultSimState';
    block.RegBlockMethod('InitializeConditions', @InitializeConditions);
    block.RegBlockMethod('Start',                @Start);
    block.RegBlockMethod('Outputs',              @Outputs);
    block.RegBlockMethod('Derivatives',          @Derivatives);
    block.RegBlockMethod('Terminate',            @Terminate);

function InitializeConditions(block)
    % CHANGE 2: initial levels from the dialog parameter, as a column vector
    x0 = block.DialogPrm(1).Data;
    block.ContStates.Data = x0(:);

function Start(~)
    disp('Starting simulation of cascaded three-tank system...');

function Outputs(block)
    block.OutputPort(1).Data = block.ContStates.Data;

function Derivatives(block)
    U1 = block.InputPort(1).Data;
    U2 = block.InputPort(2).Data;
    U3 = block.InputPort(3).Data;
    C2 = block.InputPort(4).Data;
    C3 = block.InputPort(5).Data;
    h = block.ContStates.Data;
    % FIX 3: clamp non-negative so (2*g*h)^alpha stays real
    h1 = max(h(1), 0);
    h2 = max(h(2), 0);
    h3 = max(h(3), 0);
    %% Constants from paper
    Sp = 1.267;   g = 981;
    a = 25;       b = 34.5;     c = 10;      w = 3.5;
    Hmax = 35;    R = 36.4;
    C1 = 0.5838;  C4 = 0;
    alpha1 = 0.4791;  alpha2 = 0.4605;  alpha3 = 0.4815;
    alpha4 = 0.5;     alpha5 = 0.4581;  alpha6 = 0.4831;
    %% Area calculations
    % FIX 1: fprintf removed from here
    A1 = a * w;
    % FIX 4: cap h2 at Hmax so area stops growing past the physical tank
    A2 = c*w + (min(h2, Hmax)/Hmax)*b*w;
    h3_safe = max(min(h3, R), 0);
    inner   = max(R^2 - (R - h3_safe)^2, 1e-6);
    A3      = max(w * sqrt(inner), 1e-3);
    %% Outflows
    F1_out = C1*Sp*(2*g*h1)^alpha1 + C4*Sp*(2*g*h1)^alpha4;
    F2_out = U2*Sp*(2*g*h2)^alpha2 + C2*Sp*(2*g*h2)^alpha5;
    F3_out = U3*Sp*(2*g*h3)^alpha3 + C3*Sp*(2*g*h3)^alpha6;
    %% Inflows
    F1_in = U1;
    F2_in = F1_out;
    F3_in = F2_out;
    %% Derivatives
    dh1dt = (F1_in - F1_out) / A1;
    dh2dt = (F2_in - F2_out) / A2;
    dh3dt = (F3_in - F3_out) / A3;
    % one-sided guard: an empty tank cannot drain further
    if h(1) <= 0, dh1dt = max(dh1dt, 0); end
    if h(2) <= 0, dh2dt = max(dh2dt, 0); end
    if h(3) <= 0, dh3dt = max(dh3dt, 0); end
    block.Derivatives.Data = [dh1dt; dh2dt; dh3dt];

function Terminate(~)
    disp('Three-tank system simulation terminated.');