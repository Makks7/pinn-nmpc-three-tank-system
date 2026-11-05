function three_tank_sfun_no_dist(block)

% Level-2 MATLAB S-Function for Cascaded Three-Tank System
% Implements nonlinear dynamics from:
% "Design, Fabrication and Interfacing of a Cascaded Three-Tank System..."
%
% Inputs: U1 (pump flow), U2 (valve 2 opening), U3 (valve 3 opening)
% Output: [h1; h2; h3] - tank levels in cm
% States: Continuous (h1, h2, h3)

setup(block);

function setup(block)

    % Block configuration
    block.NumInputPorts  = 5;
    block.NumOutputPorts = 1;
    block.NumContStates  = 3;

    % Input ports
    for i = 1:5
        block.InputPort(i).Dimensions = 1;
        block.InputPort(i).DirectFeedthrough = false;
    end

    % Output port
    block.OutputPort(1).Dimensions = 3;

    % Sample time (continuous)
    block.SampleTimes = [0 0];

    % SimState compliance
    block.SimStateCompliance = 'DefaultSimState';

    % Register methods
    block.RegBlockMethod('InitializeConditions', @InitializeConditions);
    block.RegBlockMethod('Start',              @Start);
    block.RegBlockMethod('Outputs',            @Outputs);
    block.RegBlockMethod('Derivatives',        @Derivatives);
    block.RegBlockMethod('Terminate',          @Terminate);

% end

%% Initialize Conditions
function InitializeConditions(block)
    % Initial levels: [h1; h2; h3] in cm
    % block.ContStates.Data = [14.29; 13.51; 16.06]; % Nominal operating point
    block.ContStates.Data = [5, 5, 5];
% end

%% Start Method
function Start(~)
    % Optional: Initialization before simulation starts
    disp('Starting simulation of cascaded three-tank system...');
% end
% 
%% Outputs
function Outputs(block)
    block.OutputPort(1).Data = block.ContStates.Data;
% end

%% Derivatives
function Derivatives(block)
    U1 = block.InputPort(1).Data;
    U2 = block.InputPort(2).Data;
    U3 = block.InputPort(3).Data;
    C2 = block.InputPort(4).Data; % 0.333;   
    C3 = block.InputPort(5).Data;% 0.333; 

    h = block.ContStates.Data;
    h1 = h(1); h2 = h(2); h3 = h(3);

    %% Constants from paper
    Sp = 1.267;   g = 981;
    a = 25;       b = 34.5;     c = 10;      w = 3.5;
    Hmax = 35;    R = 36.4;

    C1 = 0.5838;   C4 = 0;

    alpha1 = 0.4791;  alpha2 = 0.4605;  alpha3 = 0.4815;
    alpha4 = 0.5;     alpha5 = 0.4581;  alpha6 = 0.4831;

    %% Area Calculations
    A1 = a * w;
    fprintf("The area is: %d",A1)

    A2 = c*w + (h2/Hmax)*b*w;

    h3_safe = max(min(h3, R), 0);  % Clamp h3
    inner = R^2 - (R - h3_safe)^2;
    inner = max(inner, 1e-6);  % Avoid sqrt(negative)
    A3 = w * sqrt(inner);
    A3 = max(A3, 1e-3);  % Prevent division by zero

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

    block.Derivatives.Data = [dh1dt; dh2dt; dh3dt];
% end

%% Terminate
function Terminate(~)
    disp('Three-tank system simulation terminated.');
% end