"""
pinn_core.py - shared code for the three-tank PINN.
train_pinn.py, test_pinn.py and validate_pinn.py all import from here.

DATA SPLIT (in time order, never shuffled):
    train     0 - 70 %     used for the gradient updates
    test     70 - 85 %     watched during training for early stopping
    validate 85 - 100 %    not seen at all during training, these are the numbers I report
"""

import sys
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

torch.set_default_dtype(torch.float64)

# ---------------------------------------------------------------- paths
HERE = Path(__file__).resolve().parent
ROOT = next((p for p in [HERE, *HERE.parents] if (p / "data").is_dir()), None)
if ROOT is None:
    sys.exit("Could not find the project root (no data/ folder above this script).")
DATA_DIR = ROOT / "data"
WEIGHTS  = ROOT / "python" / "weights"
FIGS     = ROOT / "python" / "figures"
MODELS   = ROOT / "models"
for d in (WEIGHTS, FIGS, MODELS):
    d.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- split
SPLIT = dict(train=(0.00, 0.70), test=(0.70, 0.85), validate=(0.85, 1.00))

X_COLS = ["h1", "h2", "h3", "u1", "u2", "u3", "c2", "c3"]
Y_COLS = ["h1", "h2", "h3"]

# ------------------------------------------------- physics (matches the S-function)
P = dict(Sp=1.267, g=981.0, a=25.0, b=34.5, c=10.0, w=3.5, Hmax=35.0, R=36.4,
         C1=0.5838, C4=0.0,
         alpha1=0.4791, alpha2=0.4605, alpha3=0.4815,
         alpha4=0.5,    alpha5=0.4581, alpha6=0.4831)

def ode_rhs(h, u, c):
    """torch version, differentiable, safe at h -> 0. Returns dh/dt [cm/s]."""
    g, Sp, eps = P["g"], P["Sp"], 1e-6
    h1 = h[:, 0].clamp(min=0.0); h2 = h[:, 1].clamp(min=0.0); h3 = h[:, 2].clamp(min=0.0)
    U1, U2, U3 = u[:, 0], u[:, 1], u[:, 2]
    C2, C3 = c[:, 0], c[:, 1]
    A1 = P["a"] * P["w"]
    A2 = P["c"]*P["w"] + (h2.clamp(max=P["Hmax"])/P["Hmax"])*P["b"]*P["w"]
    h3s = h3.clamp(max=P["R"] - eps)
    A3 = (P["w"]*torch.sqrt((P["R"]**2 - (P["R"]-h3s)**2).clamp(min=eps))).clamp(min=1e-3)
    q1 = (2*g*h1).clamp(min=eps); q2 = (2*g*h2).clamp(min=eps); q3 = (2*g*h3).clamp(min=eps)
    F1o = P["C1"]*Sp*q1**P["alpha1"] + P["C4"]*Sp*q1**P["alpha4"]
    F2o = U2*Sp*q2**P["alpha2"]      + C2*Sp*q2**P["alpha5"]
    F3o = U3*Sp*q3**P["alpha3"]      + C3*Sp*q3**P["alpha6"]
    return torch.stack([(U1-F1o)/A1, (F1o-F2o)/A2, (F2o-F3o)/A3], dim=1)

def ode_rhs_np(h, u, c):
    """numpy version for diagnostics."""
    g, Sp, eps = P["g"], P["Sp"], 1e-6
    h1 = np.clip(h[:,0],0,None); h2 = np.clip(h[:,1],0,None); h3 = np.clip(h[:,2],0,None)
    U1,U2,U3 = u[:,0],u[:,1],u[:,2]; C2,C3 = c[:,0],c[:,1]
    A1 = P["a"]*P["w"]
    A2 = P["c"]*P["w"] + (np.minimum(h2,P["Hmax"])/P["Hmax"])*P["b"]*P["w"]
    h3s = np.minimum(h3, P["R"]-eps)
    A3 = np.maximum(P["w"]*np.sqrt(np.maximum(P["R"]**2-(P["R"]-h3s)**2,eps)),1e-3)
    q1,q2,q3 = [np.maximum(2*g*x,eps) for x in (h1,h2,h3)]
    F1o = P["C1"]*Sp*q1**P["alpha1"] + P["C4"]*Sp*q1**P["alpha4"]
    F2o = U2*Sp*q2**P["alpha2"] + C2*Sp*q2**P["alpha5"]
    F3o = U3*Sp*q3**P["alpha3"] + C3*Sp*q3**P["alpha6"]
    return np.stack([(U1-F1o)/A1, (F1o-F2o)/A2, (F2o-F3o)/A3], axis=1)

# ---------------------------------------------------------------- scaling
class Scaler:
    """min-max to [-1,1]; constant columns get an artificial unit range."""
    def __init__(self, arr=None, lo=None, hi=None):
        if arr is not None:
            self.lo = arr.min(axis=0); self.hi = arr.max(axis=0)
            rng = self.hi - self.lo
            self.lo = np.where(rng < 1e-12, self.lo-0.5, self.lo)
            self.hi = np.where(rng < 1e-12, self.hi+0.5, self.hi)
        else:
            self.lo = np.asarray(lo).ravel(); self.hi = np.asarray(hi).ravel()
    def fwd(self, a):   return 2*(a-self.lo)/(self.hi-self.lo) - 1
    def inv(self, a):   return (a+1)/2*(self.hi-self.lo) + self.lo
    def fwd_t(self, t): return 2*(t-torch.as_tensor(self.lo))/torch.as_tensor(self.hi-self.lo) - 1
    def inv_t(self, t): return (t+1)/2*torch.as_tensor(self.hi-self.lo) + torch.as_tensor(self.lo)

# ---------------------------------------------------------------- model
class PINN(nn.Module):
    def __init__(self, n_in=8, n_out=3, width=64, depth=3):
        super().__init__()
        layers, d = [], n_in
        for _ in range(depth):
            layers += [nn.Linear(d, width), nn.Tanh()]; d = width
        layers += [nn.Linear(d, n_out)]
        self.net = nn.Sequential(*layers)
    def forward(self, x): return self.net(x)

# ---------------------------------------------------------------- data
def load_csv(path, hmax_filter=34.0, verbose=True):
    path = Path(path)
    if not path.exists():
        found = sorted(DATA_DIR.glob("*.csv"))
        sys.exit(f"CSV not found: {path}\nFiles in {DATA_DIR}:\n  " +
                 "\n  ".join(f.name for f in found))
    df = pd.read_csv(path)
    n0 = len(df)
    bad = (df[["h1","h2","h3"]] > hmax_filter).any(axis=1)
    bad = bad | bad.shift(-1, fill_value=False)
    df = df[~bad].reset_index(drop=True)
    Ts = float(df["Ts"].iloc[0])
    if verbose:
        print(f"loaded {path.name}: {n0} rows, kept {len(df)} after overflow filter "
              f"(>{hmax_filter} cm), Ts={Ts}s")
    return df, Ts

def make_pairs(df):
    """
    (x_k, y_{k+1}) pairs, formed only between rows that are consecutive in time.
    The overflow filter can remove rows, leaving gaps; pairing across a gap
    would ask the network to predict a 20+ s jump as if it were one 2 s step.
    Returns X, Y and a boolean `reset` that is True where a new contiguous
    segment starts (free-run restarts from the true state there).
    """
    t  = df["t"].to_numpy(); Ts = float(df["Ts"].iloc[0])
    X  = df[X_COLS].to_numpy(); Y = df[Y_COLS].to_numpy()
    ok = np.isclose(np.diff(t), Ts, rtol=0, atol=1e-6)
    idx = np.where(ok)[0]
    reset = np.ones(len(idx), bool); reset[1:] = np.diff(idx) != 1
    n_gap = int((~ok).sum())
    if n_gap:
        print(f"   {n_gap} time gap(s) from filtering -> {reset.sum()} contiguous segments")
    return X[:-1][ok], Y[1:][ok], reset

def split_idx(n, which):
    lo, hi = SPLIT[which]
    return np.arange(int(lo*n), int(hi*n))

def add_sensor_noise(df, seed=0, quant=0.075, sigma=0.02):
    """12-bit level sensors: ~0.075 cm per count plus a little electrical noise."""
    rng = np.random.default_rng(seed)
    out = df.copy()
    for c in ["h1","h2","h3"]:
        v = out[c].to_numpy() + rng.normal(0, sigma, len(out))
        out[c] = np.round(v/quant)*quant
    return out

# ---------------------------------------------------------------- inference
def load_model():
    ck_path = WEIGHTS / "pinn_3tank.pt"
    if not ck_path.exists():
        sys.exit(f"No checkpoint at {ck_path}. Run train_pinn.py first.")
    ck = torch.load(ck_path, weights_only=False)
    m = PINN(width=ck["args"]["width"], depth=ck["args"]["depth"])
    m.load_state_dict(ck["model"]); m.eval()
    xs = Scaler(lo=ck["xs"]["lo"], hi=ck["xs"]["hi"])
    ys = Scaler(lo=ck["ys"]["lo"], hi=ck["ys"]["hi"])
    return m, xs, ys, ck["Ts"], ck["args"]

def predict_one_step(model, xs, ys, X):
    with torch.no_grad():
        return ys.inv_t(model(torch.as_tensor(xs.fwd(X)))).numpy()

def predict_free_run(model, xs, ys, X, reset=None):
    """Feed the network's own prediction back in; only u,c come from data.
    Restarts from the true state wherever `reset` is True (segment boundary)."""
    out = np.zeros((len(X), 3)); h = X[0, 0:3].copy()
    with torch.no_grad():
        for k in range(len(X)):
            if reset is not None and reset[k]:
                h = X[k, 0:3].copy()
            x = np.concatenate([h, X[k, 3:8]])
            h = ys.inv_t(model(torch.as_tensor(xs.fwd(x))[None]))[0].numpy()
            out[k] = h
    return out

# ---------------------------------------------------------------- metrics
def metrics(true, pred, mode=""):
    rows = []
    for i, nm in enumerate(Y_COLS):
        t, p = true[:,i], pred[:,i]; e = p - t
        ss_res = (e**2).sum(); ss_tot = ((t-t.mean())**2).sum()
        rng = t.max() - t.min()
        rows.append(dict(mode=mode, state=nm,
                         RMSE=np.sqrt((e**2).mean()),
                         MAE=np.abs(e).mean(),
                         max_err=np.abs(e).max(),
                         R2=1 - ss_res/ss_tot,
                         NRMSE_pct=100*np.sqrt((e**2).mean())/rng))
    return pd.DataFrame(rows)

def report(true, one, free, tag):
    M = pd.concat([metrics(true, one, "one-step"),
                   metrics(true, free, "free-run")], ignore_index=True)
    print("\n" + "="*78)
    print(f"  {tag}")
    print("="*78)
    print(M.to_string(index=False, float_format=lambda v: f"{v:10.4f}"))
    print("="*78)
    M.to_csv(FIGS / f"metrics_{tag}.csv", index=False)
    return M

def physics_check(X, one, Ts):
    res = (one - X[:,0:3])/Ts - ode_rhs_np(0.5*(X[:,0:3]+one), X[:,3:6], X[:,6:8])
    print("\nphysics residual of the PINN's own predictions [cm/s]:")
    for i, nm in enumerate(Y_COLS):
        print(f"   {nm}: RMS {np.sqrt((res[:,i]**2).mean()):.5f}   max {np.abs(res[:,i]).max():.5f}")
    return res

# ---------------------------------------------------------------- plots
def plot_timeseries(true, one, free, Ts, tag, M=None):
    t = np.arange(len(true))*Ts
    fig, ax = plt.subplots(3,1, figsize=(11,7.5), sharex=True)
    for i, nm in enumerate(Y_COLS):
        ax[i].plot(t, true[:,i], "k",   lw=1.3, label="plant")
        ax[i].plot(t, one[:,i],  "b--", lw=1.0, label="PINN one-step")
        ax[i].plot(t, free[:,i], "r:",  lw=1.2, label="PINN free-run")
        ax[i].set_ylabel(f"{nm} [cm]"); ax[i].grid(alpha=.3)
    ax[0].legend(ncol=3); ax[-1].set_xlabel("time [s]")
    if M is not None:
        fr = M[M["mode"]=="free-run"]
        fig.suptitle(f"{tag}   free-run:  " +
                     "   ".join(f"{r.state} RMSE {r.RMSE:.3f} cm, $R^2$ {r.R2:.4f}"
                                for r in fr.itertuples()), y=1.0, fontsize=10)
    fig.tight_layout(); fig.savefig(FIGS / f"{tag}_timeseries.png", dpi=150); plt.close(fig)

def plot_parity(true, free, M, tag):
    fr = M[M["mode"]=="free-run"]
    fig, ax = plt.subplots(1,3, figsize=(12,4.2))
    for i, nm in enumerate(Y_COLS):
        ax[i].scatter(true[:,i], free[:,i], s=2, alpha=.3)
        lim = [min(true[:,i].min(), free[:,i].min()), max(true[:,i].max(), free[:,i].max())]
        ax[i].plot(lim, lim, "k--", lw=1)
        r2 = fr[fr.state==nm].R2.iloc[0]; rm = fr[fr.state==nm].RMSE.iloc[0]
        ax[i].set_title(f"{nm}   $R^2$={r2:.4f}   RMSE={rm:.3f} cm")
        ax[i].set_xlabel("plant [cm]"); ax[i].set_ylabel("PINN free-run [cm]")
        ax[i].grid(alpha=.3); ax[i].set_aspect("equal","box")
    fig.tight_layout(); fig.savefig(FIGS / f"{tag}_parity.png", dpi=150); plt.close(fig)

def plot_error(true, free, Ts, tag):
    t = np.arange(len(true))*Ts
    fig, ax = plt.subplots(3,1, figsize=(11,6), sharex=True)
    for i, nm in enumerate(Y_COLS):
        e = free[:,i]-true[:,i]
        ax[i].plot(t, e, lw=.8)
        ax[i].axhline(0, color="k", lw=.6)
        ax[i].fill_between(t, -e.std(), e.std(), alpha=.15, color="gray",
                           label=f"$\\pm1\\sigma$ = {e.std():.3f} cm")
        ax[i].set_ylabel(f"{nm} err [cm]"); ax[i].legend(loc="upper right", fontsize=8)
        ax[i].grid(alpha=.3)
    ax[-1].set_xlabel("time [s]")
    fig.suptitle(f"{tag}: free-run error", y=1.0)
    fig.tight_layout(); fig.savefig(FIGS / f"{tag}_error.png", dpi=150); plt.close(fig)

def evaluate(model, xs, ys, X, Y, Ts, tag, reset=None):
    """One call: predict, report metrics, physics check, all three plots."""
    one  = predict_one_step(model, xs, ys, X)
    free = predict_free_run(model, xs, ys, X, reset)
    M = report(Y, one, free, tag)
    physics_check(X, one, Ts)
    plot_timeseries(Y, one, free, Ts, tag, M)
    plot_parity(Y, free, M, tag)
    plot_error(Y, free, Ts, tag)
    print(f"\nwrote {FIGS}/{tag}_timeseries.png, {tag}_parity.png, {tag}_error.png, "
          f"metrics_{tag}.csv")
    return M, one, free