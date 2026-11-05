"""
train_pinn.py - trains the three-tank PINN on the first 70% of the run.

    python train_pinn.py
    python train_pinn.py --epochs 8000 --w_phys 0.3
    python train_pinn.py --csv ../data/train01.csv --width 96 --depth 4
"""

import argparse, time
import numpy as np
import torch
import torch.nn as nn
from scipy.io import savemat
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from pinn_core import (ROOT, DATA_DIR, WEIGHTS, FIGS, MODELS, SPLIT, X_COLS, Y_COLS,
                       PINN, Scaler, ode_rhs, load_csv, make_pairs, split_idx,
                       evaluate)


def export_matlab(model, xs, ys, Ts):
    """
    MATLAB reproduces the forward pass exactly:
        xn = 2*(x - x_lo)./(x_hi - x_lo) - 1
        a  = tanh(W1*xn + b1);  ... ;  yn = Wn*a + bn
        y  = (yn + 1)/2 .* (y_hi - y_lo) + y_lo
    """
    Ws, bs = [], []
    for m in model.net:
        if isinstance(m, nn.Linear):
            Ws.append(m.weight.detach().numpy())
            bs.append(m.bias.detach().numpy()[:, None])
    d = {f"W{i+1}": W for i, W in enumerate(Ws)}
    d.update({f"b{i+1}": b for i, b in enumerate(bs)})
    d.update(dict(n_layers=len(Ws), activation="tanh",
                  x_lo=xs.lo[:, None], x_hi=xs.hi[:, None],
                  y_lo=ys.lo[:, None], y_hi=ys.hi[:, None],
                  Ts=Ts,
                  input_cols=np.array(X_COLS, dtype=object),
                  output_cols=np.array(Y_COLS, dtype=object)))
    savemat(str(MODELS / "pinn_weights.mat"), d)


def plot_history(h):
    fig, ax = plt.subplots(1, 2, figsize=(11, 3.6))
    ax[0].semilogy(h["ep"], h["tr_data"], label="train")
    ax[0].semilogy(h["ep"], h["te_data"], label="test")
    ax[0].set_title("data loss (scaled)"); ax[0].legend(); ax[0].grid(alpha=.3)
    ax[1].semilogy(h["ep"], h["tr_phys"], label="train")
    ax[1].semilogy(h["ep"], h["te_phys"], label="test")
    ax[1].set_title("physics residual loss"); ax[1].legend(); ax[1].grid(alpha=.3)
    for a in ax: a.set_xlabel("epoch")
    fig.tight_layout(); fig.savefig(FIGS / "train_history.png", dpi=150); plt.close(fig)


def main(args):
    print(f"project root: {ROOT}")
    torch.manual_seed(args.seed); np.random.seed(args.seed)

    df, Ts = load_csv(args.csv)
    X, Y, reset = make_pairs(df)
    n = len(X)
    tr = split_idx(n, "train")
    te = split_idx(n, "test")
    print(f"pairs {n}   train {len(tr)} ({SPLIT['train'][0]:.0%}-{SPLIT['train'][1]:.0%})"
          f"   test {len(te)} ({SPLIT['test'][0]:.0%}-{SPLIT['test'][1]:.0%})"
          f"   validate held out ({SPLIT['validate'][0]:.0%}-100%)")

    # scalers fitted on TRAIN only - no leakage from later slices
    xs = Scaler(X[tr]); ys = Scaler(Y[tr])
    Xn = torch.as_tensor(xs.fwd(X)); Yn = torch.as_tensor(ys.fwd(Y))
    Xp = torch.as_tensor(X)

    model = PINN(width=args.width, depth=args.depth)
    opt = torch.optim.Adam(model.parameters(), lr=args.lr,
                           weight_decay=args.weight_decay)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(
        opt, T_max=args.epochs, eta_min=args.lr*0.01)

    def losses(ids):
        xn, yn, xp = Xn[ids], Yn[ids], Xp[ids]
        pred_n = model(xn)
        L_data = ((pred_n - yn)**2).mean()
        pred_p = ys.inv_t(pred_n)
        h_k, u_k, c_k = xp[:, 0:3], xp[:, 3:6], xp[:, 6:8]
        h_mid = 0.5*(h_k + pred_p)
        resid = (pred_p - h_k)/Ts - ode_rhs(h_mid, u_k, c_k)
        L_phys = ((resid/args.resid_scale)**2).mean()
        return L_data, L_phys

    hist = {k: [] for k in ["ep","tr_data","tr_phys","te_data","te_phys"]}
    best, since_best, t0 = float("inf"), 0, time.time()

    for ep in range(1, args.epochs+1):
        model.train()
        perm = np.random.permutation(tr)
        ad = ap = 0.0
        for s in range(0, len(perm), args.batch):
            ids = perm[s:s+args.batch]
            Ld, Lp = losses(ids)
            L = args.w_data*Ld + args.w_phys*Lp
            opt.zero_grad(); L.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            ad += Ld.item()*len(ids); ap += Lp.item()*len(ids)
        sched.step()
        ad /= len(tr); ap /= len(tr)

        model.eval()
        with torch.no_grad():
            td, tp = losses(te)
        td, tp = td.item(), tp.item()
        for k, v in zip(["ep","tr_data","tr_phys","te_data","te_phys"],
                        [ep, ad, ap, td, tp]):
            hist[k].append(v)

        score = td + args.w_phys*tp
        if score < best:
            best, since_best = score, 0
            torch.save({"model": model.state_dict(),
                        "xs": vars(xs), "ys": vars(ys),
                        "Ts": Ts, "args": vars(args), "epoch": ep},
                       WEIGHTS / "pinn_3tank.pt")
        else:
            since_best += 1

        if ep % args.log_every == 0 or ep == 1:
            print(f"ep {ep:5d}  train data {ad:.3e} phys {ap:.3e} | "
                  f"test data {td:.3e} phys {tp:.3e} | "
                  f"lr {sched.get_last_lr()[0]:.2e} | {time.time()-t0:5.0f}s")

        if since_best >= args.patience:
            print(f"early stop at epoch {ep} "
                  f"(no test improvement for {args.patience} epochs)")
            break

    # ---- reload best and report on the TRAINING slice -------------------
    ck = torch.load(WEIGHTS / "pinn_3tank.pt", weights_only=False)
    model.load_state_dict(ck["model"]); model.eval()
    print(f"\nbest checkpoint from epoch {ck['epoch']}")

    plot_history(hist)
    evaluate(model, xs, ys, X[tr], Y[tr], Ts, "train", reset[tr])
    export_matlab(model, xs, ys, Ts)

    print(f"\nsaved {WEIGHTS/'pinn_3tank.pt'}")
    print(f"saved {MODELS/'pinn_weights.mat'}")
    print("\nnext:  python test_pinn.py       (70-85% slice)")
    print("       python validate_pinn.py   (85-100% slice, never seen)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=str(DATA_DIR / "train01.csv"))
    ap.add_argument("--epochs", type=int, default=6000)
    ap.add_argument("--batch", type=int, default=512)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--width", type=int, default=64)
    ap.add_argument("--depth", type=int, default=3)
    ap.add_argument("--w_data", type=float, default=1.0)
    ap.add_argument("--w_phys", type=float, default=0.1)
    ap.add_argument("--resid_scale", type=float, default=0.05,
                    help="typical |dh/dt| in cm/s used to normalise the residual")
    ap.add_argument("--weight_decay", type=float, default=1e-5)
    ap.add_argument("--patience", type=int, default=1500)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--log_every", type=int, default=100)
    main(ap.parse_args())