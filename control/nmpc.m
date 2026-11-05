function [uopt, y_pred, fcost, Ecount, exitflag, xPx, Tconst, hk] = nmpc(y_set, ypast, yo, tp, ts, dist, upast, uo, u_set, ho, modelName)
uopt = [0;0;0];
fcost = 0;
y_pred = [0;0;0];
% Regression
u_reg = [upast(1) upast(2), upast(3);uo(1) uo(2),uo(3)];
y_reg =[ypast';yo'];
Ecount = 0 ;
exitflag = Inf ;
xPx = 0 ;
Tconst = 0 ;
hk = ho;
% Steady states
h1ss=y_set(1) ; h2ss=y_set(2) ; h3ss=y_set(3) ;
u1ss=u_set(1) ; u2ss=u_set(2) ; u3ss = u_set(3);
rhox = 20;
rhou=10;
Wy = [1/h1ss, 1/h2ss, 1/h3ss]*rhox;
% FIX 1: no penalty on (u - u_set). u_set is a fixed nominal point and does
% not move with the setpoints, so penalising it dragged u1 toward 100 and
% forced the disturbance integrator to wind up. Wdu keeps the moves smooth.
Wu    = [0, 0, 0];
Wdu   = [1/u1ss,10/u2ss, 10/u3ss]*rhou;
Wuerr = [0, 0, 0];
P1 =[
    0.3408    0.1556    0.0754;
    0.1556    0.4888    0.2504;
    0.0754    0.2504    0.6810;];
alpha1 = 20.4206;
P=P1;
alpha = alpha1*rhox;
nu = tp(1);
ny = tp(2);
Nu = tp(3);
Np = tp(4);
bounds = struct();
bounds.ymin =[0.1 ,0.1, 0.1];
bounds.ymax =[35 35 35];
% FIX 2: input bounds = PINN training range (x_lo/x_hi in pinn_weights.mat),
% so the optimiser never asks the network to extrapolate.
bounds.u_min = [55,  0.17, 0.11];
bounds.u_max = [148, 1.00, 0.87];
du = [10, 0.1, 0.1];
bounds.du_min =  -du;
bounds.du_max = du;
params = struct();
params.y_set = y_set;
params.u_set = u_set;
params.nu = nu;
params.ny = ny;
params.Nu = Nu;
params.Np = Np;
params.Wy = Wy;
params.Wdu = Wdu;
params.Wu = Wu;
params.Wuerr =Wuerr;
params.ts = ts;
params.P = P;
params.alpha = alpha;
params.modelName = modelName;
params.bounds = bounds;
params.dist = dist;
coder.extrinsic('get_control_input');
[uopt, y_pred, hk, fval, exitflag, elapsed, ~, ~] = get_control_input(y_reg, u_reg, ho, params);
% FIX 3: get_control_input returns PINN + dist. The scope should show the
% raw PINN prediction, so remove the disturbance term here. y_pred only
% feeds the scope; the controller is unaffected.
y_pred = y_pred(:) - dist(:);
fcost = fval;
Ecount = elapsed ;
end