function three_tank_sfun(block)
% Level-2 MATLAB S-function for Cascaded Three-Tank System with Gaussian Input Support
setup(block);

function setup(block)

    block.NumInputPorts  = 2; % U: [U1 U2 U3], D: [D1 D2 D3]
    block.NumOutputPorts = 1; % Output: [h1 h2 h3]
    block.NumContStates  = 3;
    block.NumDialogPrms  = 0;
    block.SampleTimes = [0 0];
    block.SimStateCompliance = 'DefaultSimState';

    % Input ports
    for i = 1:2
        block.InputPort(i).Dimensions = 3;
        block.InputPort(i).DatatypeID = 0;  % double
        block.InputPort(i).Complexity = 'Real';
        block.InputPort(i).DirectFeedthrough = true;
    end

    % Output port
    block.OutputPort(1).Dimensions = 3;
    block.OutputPort(1).DatatypeID = 0;
    block.OutputPort(1).Complexity = 'Real';

    block.RegBlockMethod('InitializeConditions', @InitializeConditions);
    block.RegBlockMethod('Outputs',              @Outputs);
    block.RegBlockMethod('Derivatives',          @Derivatives);
    block.RegBlockMethod('Terminate',            @Terminate);

function InitializeConditions(block)
    block.ContStates.Data = [1; 1; 1];

function Outputs(block)
    block.OutputPort(1).Data = block.ContStates.Data;

function Derivatives(block)
    U = block.InputPort(1).Data; % U1, U2, U3
    D = block.InputPort(2).Data; % D1, D2, D3

    % Clamp U inputs to safe physical bounds
    U1 = min(max(U(1), 5), 25);
    U2 = min(max(U(2), 0.2), 1);
    U3 = min(max(U(3), 0.2), 1);

    D1 = D(1);
    D2 = D(2);
    D3 = D(3);

    h = block.ContStates.Data;
    h1 = h(1); h2 = h(2); h3 = h(3);

    % Constants
    Sp = 1.267; g = 981; a = 25; b = 34.5; c = 10;
    w = 3.5; Hmax = 35; R = 36.4;

    % Flow exponents (from paper)
    % alpha1 = 0.4791; alpha2 = 0.4605; alpha3 = 0.4815;
    % alpha4 = 0.5;    alpha5 = 0.4581; alpha6 = 0.4831;

    alpha1 = 0.5; alpha2 = 0.5; alpha3 = 0.5;
    alpha4 = 0.5;    alpha5 = 0.5; alpha6 = 0.5;


    % Valve coefficients (from nominal config)
    C1 = 1; C2 = 0; C3 = 0; C4 = 1; C5 = 0; C6 = 0;

    % Area calculations
    A1 = a * w;
    A2 = c*w + (h2/Hmax)*b*w;
    h3_safe = min(max(h3, 0), R - 1e-6);
    A3 = max(w * sqrt(R^2 - (R - h3_safe)^2), 1e-3);

    % Outflows
    F1_out = C1*Sp*(2*g*h1)^alpha1 + C4*Sp*(2*g*h1)^alpha4;
    F2_out = U2*Sp*(2*g*h2)^alpha2 + C2*Sp*(2*g*h2)^alpha5;
    F3_out = U3*Sp*(2*g*h3)^alpha3 + C3*Sp*(2*g*h3)^alpha6;

    % Inflows
    F1_in = U1;
    F2_in = F1_out;
    F3_in = F2_out;

    % Derivatives
    dh1dt = (F1_in - F1_out ) / A1;
    dh2dt = (F2_in - F2_out ) / A2;
    dh3dt = (F3_in - F3_out ) / A3;

    block.Derivatives.Data = [dh1dt; dh2dt; dh3dt];

function Terminate(~)
    disp('Three-Tank S-function terminated.');
