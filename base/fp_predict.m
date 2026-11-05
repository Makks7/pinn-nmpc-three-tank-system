function h_next = fp_predict(h, u, c)
% First-principles one-step prediction (Ts = 2 s), same physics as
% three_tank_sfun_pinn. RK4 with 4 sub-steps of 0.5 s, to match ode4 at 0.5 s.
Ts = 2; nsub = 4; dt = Ts/nsub;
x = h(:);
for k = 1:nsub
    k1 = f(x, u, c);
    k2 = f(x + dt/2*k1, u, c);
    k3 = f(x + dt/2*k2, u, c);
    k4 = f(x + dt*k3, u, c);
    x  = x + dt/6*(k1 + 2*k2 + 2*k3 + k4);
end
h_next = x;
end

function dx = f(h, u, c)
Sp = 1.267; g = 981; a = 25; b = 34.5; cc = 10; w = 3.5; Hmax = 35; R = 36.4;
C1 = 0.5838; C4 = 0;
al1 = 0.4791; al2 = 0.4605; al3 = 0.4815; al4 = 0.5; al5 = 0.4581; al6 = 0.4831;
h1 = max(h(1),0); h2 = max(h(2),0); h3 = max(h(3),0);
A1 = a*w;
A2 = cc*w + (min(h2,Hmax)/Hmax)*b*w;
h3s = max(min(h3,R),0);
A3 = max(w*sqrt(max(R^2-(R-h3s)^2,1e-6)),1e-3);
F1 = C1*Sp*(2*g*h1)^al1 + C4*Sp*(2*g*h1)^al4;
F2 = u(2)*Sp*(2*g*h2)^al2 + c(1)*Sp*(2*g*h2)^al5;
F3 = u(3)*Sp*(2*g*h3)^al3 + c(2)*Sp*(2*g*h3)^al6;
dx = [(u(1)-F1)/A1; (F1-F2)/A2; (F2-F3)/A3];
end