function gen_aprbs_3tank(batch, Tsim, seed)
% GEN_APRBS_3TANK  APRBS excitation signals for the cascaded three-tank rig.
%
% Set up for three_tank_sfun_pinn / three_tank_sfun_no_dist, which take
%   5 scalar inputs: U1, U2, U3, C2, C3
%
%   gen_aprbs_3tank('nominal', 10000, 1)
%   gen_aprbs_3tank('edge',    10000, 2)
%   gen_aprbs_3tank('dist',    10000, 3)
%
% It creates u1_ts u2_ts u3_ts c2_ts c3_ts (timeseries), Ts and batch_name
% in the base workspace.
%
% The bounds come from the identified parameters in the S-function
% (C1=0.5838, C4=0, alpha1=0.4791, alpha2=0.4605, alpha3=0.4815,
%  alpha5=0.4581, alpha6=0.4831).
%
%   h1 depends only on U1:  U1=100 -> h1=14.29 cm (same as the paper nominal)
%   h1 goes above 28 cm once U1 ~= 138, so that is the upper bound on U1

if nargin < 1, batch = 'nominal'; end
if nargin < 2, Tsim  = 10000;     end
if nargin < 3, seed  = 1;         end
rng(seed);

Ts = 2;
t  = (0:Ts:Tsim)';
N  = numel(t);

Sp = 1.267; g = 981;
alpha2 = 0.4605; alpha3 = 0.4815;
alpha5 = 0.4581; alpha6 = 0.4831;

switch batch
    case 'edge'
        U1_lo = 42;  U1_hi = 136;
        hband = [1.5 29.0];
        Thold = [25 70];
    otherwise
        U1_lo = 55;  U1_hi = 130;
        hband = [2.5 27.0];
        Thold = [40 90];
end

C2_nom = 0.333;  C3_nom = 0.333;

% valve opening that places the steady level at h, given U1 and leak Cl
valve_for_h = @(U1, h, av, Cl, ac) ...
    max(0.05, (U1 - Cl*Sp*(2*g*h)^ac) / (Sp*(2*g*h)^av));

u1 = zeros(N,1); u2 = zeros(N,1); u3 = zeros(N,1);

k = 1;
while k <= N
    hold_n = round((Thold(1) + rand*diff(Thold)) / Ts);
    idx    = k : min(k+hold_n-1, N);

    a1 = U1_lo + rand*(U1_hi - U1_lo);

    lo2 = valve_for_h(a1, hband(2), alpha2, C2_nom, alpha5);
    hi2 = valve_for_h(a1, hband(1), alpha2, C2_nom, alpha5);
    lo3 = valve_for_h(a1, hband(2), alpha3, C3_nom, alpha6);
    hi3 = valve_for_h(a1, hband(1), alpha3, C3_nom, alpha6);

    lo2 = max(lo2, 0.10); hi2 = min(hi2, 1.0);
    lo3 = max(lo3, 0.10); hi3 = min(hi3, 1.0);
    if hi2 <= lo2, hi2 = min(1.0, lo2 + 0.05); end
    if hi3 <= lo3, hi3 = min(1.0, lo3 + 0.05); end

    u1(idx) = a1;
    u2(idx) = lo2 + rand*(hi2 - lo2);
    u3(idx) = lo3 + rand*(hi3 - lo3);

    k = idx(end) + 1;
end

c2 = C2_nom * ones(N,1);
c3 = C3_nom * ones(N,1);

if strcmp(batch,'dist')
    levels = [0 0.333 0.666 1.0];      % 4-position leak valves
    kk = 1;
    while kk <= N
        seg = round((300 + rand*400)/Ts);
        idx = kk : min(kk+seg-1, N);
        c2(idx) = levels(randi(numel(levels)));
        c3(idx) = levels(randi(numel(levels)));
        kk = idx(end) + 1;
    end
end

assignin('base','u1_ts', timeseries(u1,t));
assignin('base','u2_ts', timeseries(u2,t));
assignin('base','u3_ts', timeseries(u3,t));
assignin('base','c2_ts', timeseries(c2,t));
assignin('base','c3_ts', timeseries(c3,t));
assignin('base','Ts', Ts);
assignin('base','batch_name', batch);

fprintf('APRBS batch "%s": %d samples, Ts=%g s, Tsim=%g s\n', batch, N, Ts, Tsim);
fprintf('   u1 [%6.1f %6.1f]   u2 [%.2f %.2f]   u3 [%.2f %.2f]\n', ...
        min(u1),max(u1), min(u2),max(u2), min(u3),max(u3));
fprintf('   c2 [%.3f %.3f]   c3 [%.3f %.3f]\n', ...
        min(c2),max(c2), min(c3),max(c3));
end
