function test_nmpc_offline()
%TEST_NMPC_OFFLINE  NMPC + PINN against the true plant, in plain MATLAB.
%
% I followed the test in Bamimore et al. (2021) Section 4.6 so that the IAE
% can be compared with their Table 3:
%   - track the nominal setpoints 14.29 / 13.51 / 16.06 cm from near-empty
%   - setpoints step to 20 cm at t = 400 / 800 / 1100 s (staggered)
%   - 1500 s run, Ts = 2 s
% In the paper the simulated NMPC got a total IAE of 1323 and the LMPC 1396.
%
% One difference from the paper: the tanks start at 1 cm, not 0. The PINN
% was trained on levels >= 1 cm, so 0 is outside its range. 1 cm is
% practically empty anyway and the network does not have to extrapolate in
% the first few seconds.
%
% The plant is integrated with ode45 (with error control). A fixed 2 s RK4
% step does not work well here because tank 3 is parabolic. Its cross
% section goes to zero as h3 -> 0, so the ODE gets stiff close to empty.

setup_nmpc();
NMPC = evalin('base','NMPC');
Ts = NMPC.Ts;
Tsim = 1500;
nk = round(Tsim/Ts);

% paper setpoint schedule
r_seq = repmat([14.29; 13.51; 16.06], 1, nk);
r_seq(1, round( 400/Ts):end) = 20;
r_seq(2, round( 800/Ts):end) = 20;
r_seq(3, round(1100/Ts):end) = 20;

h = [1; 1; 1];              % near-empty, inside the PINN's training range
u = [100; 0.4; 0.2];        % paper nominal inputs

H = zeros(3, nk); U = zeros(3, nk); T = (0:nk-1)*Ts;
odeopts = odeset('RelTol',1e-6,'AbsTol',1e-8);

fprintf('running %d NMPC steps...\n', nk);
tic
for k = 1:nk
    u = nmpc_pinn(h, r_seq(:,k), u);
    h = plant_step(h, u, NMPC.c, Ts, odeopts);
    H(:,k) = h; U(:,k) = u;
    if mod(k, 100) == 0, fprintf('  k = %d/%d\n', k, nk); end
end
cpu = toc;
fprintf('done in %.1f s  (%.1f ms per step, budget %g ms)\n', ...
        cpu, 1000*cpu/nk, 1000*Ts);

iae = sum(abs(r_seq - H), 2) * Ts;
fprintf('\nIAE:  h1 %.1f   h2 %.1f   h3 %.1f   total %.1f\n', iae, sum(iae));
fprintf('Bamimore et al. (2021) simulation:  NMPC 1323   LMPC 1396\n');
if sum(iae) < 1323
    fprintf('--> %.1f%% lower than the paper NMPC\n', 100*(1323-sum(iae))/1323);
else
    fprintf('--> %.1f%% higher than the paper NMPC\n', 100*(sum(iae)-1323)/1323);
end

assignin('base','servo_result', struct('T',T,'H',H,'U',U,'R',r_seq,'IAE',iae));

% plot
figure('Position',[80 80 1000 720], 'Color','w');
nm = {'h_1','h_2','h_3'};
un = {'u_1  [cm^3/s]','u_2  [-]','u_3  [-]'};
ulim = {[50 150], [0 1], [0 1]};

for i = 1:3
    ax = subplot(3,2,2*i-1);
    plot(T, r_seq(i,:), 'r--', 'LineWidth',1.4); hold on
    plot(T, H(i,:),     'k',   'LineWidth',1.3);
    ylabel([nm{i} '  [cm]']); grid on; box on
    ylim([0 25]); xlim([0 Tsim]);
    ax.YTick = 0:5:25;
    if i==1
        legend('setpoint','plant','Location','southeast');
        title('Servo response');
    end
    if i==3, xlabel('time [s]'); end

    ax = subplot(3,2,2*i);
    stairs(T, U(i,:), 'b', 'LineWidth',1.2);
    ylabel(un{i}); grid on; box on
    ylim(ulim{i}); xlim([0 Tsim]);
    if i==1, title('Manipulated inputs'); end
    if i==3, xlabel('time [s]'); end
end
end


% =====================================================================
function h = plant_step(h, u, c, Ts, opts)
% Integrate the true plant over one sample with error control.
[~, X] = ode45(@(t,x) three_tank_ode(x, u, c), [0 Ts], h, opts);
h = max(X(end,:).', 0);
end

function dh = three_tank_ode(h, u, c)
Sp=1.267; g=981; a=25; b=34.5; cc=10; w=3.5; Hmax=35; R=36.4;
C1=0.5838; C4=0;
a1=0.4791; a2=0.4605; a3=0.4815; a4=0.5; a5=0.4581; a6=0.4831;
h1=max(h(1),0); h2=max(h(2),0); h3=max(h(3),0);
U1=u(1); U2=u(2); U3=u(3); C2=c(1); C3=c(2);
A1 = a*w;
A2 = cc*w + (min(h2,Hmax)/Hmax)*b*w;
h3s = max(min(h3,R-1e-6),0);
A3 = max(w*sqrt(max(R^2-(R-h3s)^2,1e-6)),1e-3);
F1o = C1*Sp*(2*g*h1)^a1 + C4*Sp*(2*g*h1)^a4;
F2o = U2*Sp*(2*g*h2)^a2 + C2*Sp*(2*g*h2)^a5;
F3o = U3*Sp*(2*g*h3)^a3 + C3*Sp*(2*g*h3)^a6;
dh = [(U1-F1o)/A1; (F1o-F2o)/A2; (F2o-F3o)/A3];
end