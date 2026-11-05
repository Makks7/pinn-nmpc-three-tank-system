function verify_pinn()
%VERIFY_PINN  Checks that the MATLAB forward pass matches PyTorch to machine precision.
%
% Run export_check.py in python/ first. It writes models/pinn_check.mat with
% some test inputs and the outputs PyTorch gave for them.
%
% If they do not match, then a transpose, a scaling vector or the layer order
% is wrong somewhere. Better to find it here than after the NMPC is already
% wired up, that one cost me a full day the first time.

here = fileparts(mfilename('fullpath'));
f = fullfile(here, '..', 'models', 'pinn_check.mat');
if ~exist(f,'file'), f = fullfile(here,'models','pinn_check.mat'); end
if ~exist(f,'file')
    error('pinn_check.mat not found. Run:  python export_check.py');
end
S = load(f);

X = S.X_test;          % N x 8
Ypy = S.Y_python;      % N x 3
N = size(X,1);

Yml = zeros(N,3);
for k = 1:N
    Yml(k,:) = pinn_predict(X(k,1:3)', X(k,4:6)', X(k,7:8)')';
end

d = abs(Yml - Ypy);
fprintf('\n--- MATLAB vs PyTorch, %d test points ---\n', N);
fprintf('   max abs difference : %.3e cm\n', max(d(:)));
fprintf('   mean abs difference: %.3e cm\n', mean(d(:)));

if max(d(:)) < 1e-9
    fprintf('   PASS - identical to machine precision.\n\n');
else
    fprintf(2,'   FAIL - the two implementations disagree.\n');
    fprintf(2,'   Check: weight transposes, x_lo/x_hi order, layer count.\n\n');
    for k = 1:min(5,N)
        fprintf('   pt %d  MATLAB [%8.4f %8.4f %8.4f]  Python [%8.4f %8.4f %8.4f]\n', ...
                k, Yml(k,:), Ypy(k,:));
    end
end
end