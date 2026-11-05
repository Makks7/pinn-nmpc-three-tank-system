function h_next = pinn_predict(h, u, c)
%PINN_PREDICT  One-step prediction for the cascaded three-tank system.
%
%   h_next = pinn_predict(h, u, c)
%     h : [h1;h2;h3]  levels at step k   [cm]
%     u : [u1;u2;u3]  pump + valve openings
%     c : [c2;c3]     leak valve openings
%
% The model used is picked with the application-data flag NMPC_MODEL:
%     setappdata(0,'NMPC_MODEL','pinn')   PINN            (default)
%     setappdata(0,'NMPC_MODEL','ann')    plain ANN       models/ann_weights.mat
%     setappdata(0,'NMPC_MODEL','fp')     first principles fp_predict.m
% or just call use_model('pinn' | 'ann' | 'fp').
%
% The forward pass is the same as in PyTorch:
%   xn = 2*(x - x_lo)./(x_hi - x_lo) - 1
%   a  = tanh(W1*xn + b1); ... ; yn = Wn*a + bn
%   y  = (yn + 1)/2 .* (y_hi - y_lo) + y_lo

persistent NET_PINN NET_ANN

mdl = getappdata(0, 'NMPC_MODEL');
if ~(ischar(mdl) || isstring(mdl)) || isempty(mdl)
    mdl = 'pinn';
end

switch lower(char(mdl))
    case 'fp'
        h_next = fp_predict(h, u, c);
        return

    case 'ann'
        if isempty(NET_ANN)
            NET_ANN = load_net('ann_weights.mat', 'ANN');
        end
        NET = NET_ANN;

    otherwise                                   % 'pinn'
        if isempty(NET_PINN)
            NET_PINN = load_net('pinn_weights.mat', 'PINN');
        end
        NET = NET_PINN;
end

x  = [h(:); u(:); c(:)];                        % 8x1 in training column order
xn = 2*(x - NET.x_lo)./(NET.x_hi - NET.x_lo) - 1;
a  = xn;
for i = 1:NET.n_layers-1
    a = tanh(NET.W{i}*a + NET.b{i});
end
yn = NET.W{NET.n_layers}*a + NET.b{NET.n_layers};
h_next = (yn + 1)/2 .* (NET.y_hi - NET.y_lo) + NET.y_lo;
end

% ------------------------------------------------------------------
function NET = load_net(fname, label)
here = fileparts(mfilename('fullpath'));
f = fullfile(here, '..', 'models', fname);
if ~exist(f, 'file')
    f = fullfile(here, 'models', fname);        % fallback
end
if ~exist(f, 'file')
    error('%s not found. Train the model first.', fname);
end
NET = load(f);
NET.W = cell(NET.n_layers, 1);
NET.b = cell(NET.n_layers, 1);
for i = 1:NET.n_layers
    NET.W{i} = NET.(sprintf('W%d', i));
    NET.b{i} = NET.(sprintf('b%d', i));
end
fprintf('pinn_predict: loaded %s, %d layers, Ts = %g s\n', label, NET.n_layers, NET.Ts);
end