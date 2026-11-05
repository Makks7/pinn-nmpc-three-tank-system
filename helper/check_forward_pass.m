% check_forward_pass.m - checks if the exported PINN gives the same accuracy in MATLAB as in Python.
W = load('models/pinn_weights.mat');
fprintf('activation: %s | Ts: %g\n', W.activation, W.Ts);
disp('input_cols:');  disp(W.input_cols);
disp('output_cols:'); disp(W.output_cols);
disp('[x_lo x_hi]:'); disp([W.x_lo W.x_hi]);
disp('[y_lo y_hi]:'); disp([W.y_lo W.y_hi]);

d   = readtable('data/train01.csv');
idx = (round(0.85*height(d)):height(d))';            % validate slice
in  = string(W.input_cols);
N   = numel(idx);
X   = zeros(N, numel(in));
for j = 1:numel(in), X(:,j) = d.(in(j))(idx); end
H   = [d.h1(idx) d.h2(idx) d.h3(idx)];
sIdx = [find(in=="h1") find(in=="h2") find(in=="h3")];

% find scaler range and output type from one-step error
best = inf;
for sc = 1:2            % 1 = [0,1], 2 = [-1,1]
  for dm = 0:1          % 0 = outputs h(k+1), 1 = outputs dh
    Y = pinn_fwd(W, X(1:N-1,:), sc);
    if dm, Y = H(1:N-1,:) + Y; end
    r = sqrt(mean((Y - H(2:N,:)).^2));
    fprintf('scaler %d, delta %d -> one-step RMSE: %s\n', sc, dm, mat2str(r,3));
    if mean(r) < best, best = mean(r); SC = sc; DM = dm; end
  end
end
fprintf('\nUsing scaler %d, delta %d\n', SC, DM);

% free-run
Hp = zeros(N,3); Hp(1,:) = H(1,:);
for k = 1:N-1
    x = X(k,:); x(sIdx) = Hp(k,:);                  % feed back own prediction
    y = pinn_fwd(W, x, SC);
    Hp(k+1,:) = DM*Hp(k,:) + y;
end
err  = Hp - H;
rmse = sqrt(mean(err.^2));
r2   = 1 - sum(err.^2) ./ sum((H - mean(H)).^2);
fprintf('FREE-RUN RMSE  h1 %.3f  h2 %.3f  h3 %.3f cm\n', rmse);
fprintf('FREE-RUN R2    h1 %.4f h2 %.4f h3 %.4f\n', r2);

figure('Name','MATLAB PINN free-run'); nm = {'h1','h2','h3'};
for i = 1:3
    subplot(3,1,i); plot(H(:,i),'r--'); hold on; plot(Hp(:,i),'b');
    ylabel([nm{i} ' (cm)']); legend('data','MATLAB PINN'); grid on
end

% local function
function Y = pinn_fwd(W, X, sc)
    switch lower(strtrim(W.activation))
        case 'tanh', act = @tanh;
        case 'relu', act = @(z) max(z,0);
        case 'gelu', act = @(z) 0.5*z.*(1+erf(z/sqrt(2)));
        otherwise,   act = @(z) z./(1+exp(-z));   % silu/swish
    end
    a = ((X - W.x_lo') ./ (W.x_hi - W.x_lo)').';     % N x 8 -> 8 x N
    if sc == 2, a = 2*a - 1; end
    a = act(W.W1*a + W.b1);
    a = act(W.W2*a + W.b2);
    a = act(W.W3*a + W.b3);
    ys = (W.W4*a + W.b4).';                          % N x 3
    if sc == 2, ys = (ys + 1)/2; end
    Y = ys .* (W.y_hi - W.y_lo)' + W.y_lo';
end