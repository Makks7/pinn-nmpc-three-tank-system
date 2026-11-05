"""
export_check.py - saves some test inputs and the PyTorch outputs, so MATLAB
can check its forward pass against them. Run it from python/ after training.

    python export_check.py

It writes ../models/pinn_check.mat. After that run verify_pinn in MATLAB.
"""
import numpy as np, torch
from scipy.io import savemat
from pinn_core import MODELS, DATA_DIR, load_csv, make_pairs, load_model, X_COLS

model, xs, ys, Ts, targs = load_model()

# real operating points from the dataset, plus a few intentional edge cases
df, _ = load_csv(DATA_DIR / "train01.csv", verbose=False)
X, _, _ = make_pairs(df)
rng = np.random.default_rng(0)
X_test = X[rng.choice(len(X), 40, replace=False)]

edge = np.array([
    [ 0.5,  0.5,  0.5,  55.0, 0.20, 0.20, 0.333, 0.333],   # near empty
    [32.0, 32.0, 32.0, 148.0, 1.00, 1.00, 0.333, 0.333],   # near full
    [14.29,13.51,16.06,100.0, 0.40, 0.20, 0.333, 0.333],   # paper nominal
    [ 5.0, 25.0,  5.0, 100.0, 0.50, 0.50, 0.333, 0.333],   # mixed
])
X_test = np.vstack([X_test, edge])

with torch.no_grad():
    Y = ys.inv_t(model(torch.as_tensor(xs.fwd(X_test)))).numpy()

savemat(str(MODELS / "pinn_check.mat"),
        dict(X_test=X_test, Y_python=Y, input_cols=np.array(X_COLS, dtype=object)))
print(f"wrote {MODELS/'pinn_check.mat'}  ({len(X_test)} test points)")
print("now run  verify_pinn  in MATLAB")