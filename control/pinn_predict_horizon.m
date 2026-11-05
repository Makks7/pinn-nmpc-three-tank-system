function [yk, hk] = pinn_predict_horizon(data, u)
% Rolls the PINN over the horizon. data.e is the output disturbance estimate
% from Dist_rejector and it is added to every predicted level.
Np = data.Np; Nu = data.Nu; ny = data.ny;
c = [0.333; 0.333];
if isfield(data,'c') && numel(data.c) == 2, c = data.c(:); end
e = zeros(1,ny);
if isfield(data,'e') && numel(data.e) == ny, e = data.e(:).'; end

h  = data.yo(:);
yk = zeros(Np, ny);
for i = 1:Np
    ui = u(min(i, Nu), :).';
    h  = pinn_predict(h, ui, c);
    yk(i,:) = h.' + e;
end
hk = data.ho;
end