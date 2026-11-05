"""
ann_vs_pinn.py - compares the ANN and the PINN on the validation slice (85-100%,
which neither model saw in training).

It reads python/weights/ann_3tank.pt and pinn_3tank.pt. Nothing is trained
or changed here. It writes:
    python/figures/ann_vs_pinn.csv
    python/figures/fig_ann_vs_pinn.png/.pdf        bar chart
    python/figures/fig_ann_vs_pinn_traces.png/.pdf free-run overlay

    python ann_vs_pinn.py
"""
import numpy as np, pandas as pd, torch
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

from pinn_core import (DATA_DIR, WEIGHTS, FIGS, PINN, Scaler, Y_COLS,
                       load_csv, make_pairs, split_idx, metrics,
                       predict_one_step, predict_free_run)

C_ANN, C_PINN = "#eb6834", "#2a78d6"          # colorblind-safe pair
INK, INK2, GRID, PLANT = "#0b0b0b", "#52514e", "#e6e5e1", "#0b0b0b"
plt.rcParams.update({"font.size": 9, "axes.titlesize": 10, "legend.frameon": False,
                     "figure.facecolor": "white", "savefig.facecolor": "white"})


def _style(ax):
    ax.set_axisbelow(True)
    ax.yaxis.grid(True, color=GRID, lw=0.8); ax.xaxis.grid(False)
    for s in ("top", "right"): ax.spines[s].set_visible(False)
    for s in ("left", "bottom"): ax.spines[s].set_color(GRID)
    ax.tick_params(colors=INK2, length=0)


def load_tag(tag):
    ck = torch.load(WEIGHTS / f"{tag}_3tank.pt", weights_only=False)
    m = PINN(width=ck["args"]["width"], depth=ck["args"]["depth"])
    m.load_state_dict(ck["model"]); m.eval()
    xs = Scaler(lo=ck["xs"]["lo"], hi=ck["xs"]["hi"])
    ys = Scaler(lo=ck["ys"]["lo"], hi=ck["ys"]["hi"])
    return m, xs, ys, ck


def main():
    df, Ts = load_csv(DATA_DIR / "train01.csv")
    X, Y, reset = make_pairs(df)
    iva = split_idx(len(X), "validate")
    Xv, Yv, rv = X[iva], Y[iva], reset[iva]
    print(f"\nvalidation slice: {len(iva)} pairs, never seen during training\n")

    rows, traces = [], {}
    for tag, label in (("ann", "ANN"), ("pinn", "PINN")):
        m, xs, ys, ck = load_tag(tag)
        one  = predict_one_step(m, xs, ys, Xv)
        free = predict_free_run(m, xs, ys, Xv, rv)
        M1, Mf = metrics(Yv, one, "one"), metrics(Yv, free, "free")
        traces[label] = free
        rows.append(dict(model=label, w_phys=ck["args"]["w_phys"], epoch=ck["epoch"],
                         one_rmse=M1.RMSE.mean(),
                         free_h1=Mf.RMSE.iloc[0], free_h2=Mf.RMSE.iloc[1],
                         free_h3=Mf.RMSE.iloc[2], free_rmse=Mf.RMSE.mean(),
                         free_r2=Mf.R2.mean(), free_max=Mf.max_err.max()))

    R = pd.DataFrame(rows)
    print(R.to_string(index=False, float_format=lambda v: f"{v:9.4f}"))
    R.to_csv(FIGS / "ann_vs_pinn.csv", index=False)
    a, p = R.free_rmse.iloc[0], R.free_rmse.iloc[1]
    win = "PINN" if p < a else "ANN"
    print(f"\n  free-run RMSE:  ANN {a:.4f} cm | PINN {p:.4f} cm "
          f"-> {win} better by {abs(a-p)/max(a, p)*100:.1f}%")
    print(f"wrote {FIGS/'ann_vs_pinn.csv'}")

    # ---- bar chart, per tank + mean
    labels = ["h1", "h2", "h3", "mean"]
    ann  = [R.free_h1[0], R.free_h2[0], R.free_h3[0], R.free_rmse[0]]
    pinn = [R.free_h1[1], R.free_h2[1], R.free_h3[1], R.free_rmse[1]]
    x = np.arange(4); w = 0.34
    fig, ax = plt.subplots(figsize=(6.2, 3.6))
    for vals, off, c, lab in ((ann, -w/2-0.01, C_ANN, "ANN (data loss only)"),
                              (pinn, w/2+0.01, C_PINN, "PINN (data + physics loss)")):
        b = ax.bar(x + off, vals, w, color=c, label=lab)
        for r in b:
            ax.annotate(f"{r.get_height():.3f}",
                        (r.get_x()+r.get_width()/2, r.get_height()),
                        xytext=(0, 3), textcoords="offset points",
                        ha="center", fontsize=8, color=INK2)
    ax.set_xticks(x); ax.set_xticklabels(labels, color=INK)
    ax.set_ylabel("free-run RMSE [cm]", color=INK)
    ax.set_title("Free-run prediction error on held-out validation data",
                 loc="left", color=INK, pad=10)
    ax.set_ylim(0, max(ann + pinn)*1.3)
    ax.legend(loc="upper left", labelcolor=INK2)
    _style(ax)
    for ext in ("png", "pdf"):
        fig.savefig(FIGS / f"fig_ann_vs_pinn.{ext}", dpi=300, bbox_inches="tight")
    plt.close(fig)

    # ---- free-run overlay
    n = min(600, len(Yv)); t = np.arange(n)*Ts
    fig, axes = plt.subplots(3, 1, figsize=(7.2, 6.0), sharex=True)
    for i, (ax, nm) in enumerate(zip(axes, Y_COLS)):
        ax.plot(t, Yv[:n, i], color=PLANT, lw=1.4, label="plant")
        ax.plot(t, traces["ANN"][:n, i],  color=C_ANN,  lw=1.6, ls="--", label="ANN")
        ax.plot(t, traces["PINN"][:n, i], color=C_PINN, lw=1.6, ls=":",  label="PINN")
        ax.set_ylabel(f"{nm} [cm]", color=INK); _style(ax)
        if i == 0:
            ax.legend(ncol=3, loc="upper right", labelcolor=INK2)
    axes[-1].set_xlabel("time [s]", color=INK2)
    fig.suptitle("Free-run prediction on held-out data", color=INK,
                 x=0.005, ha="left", y=0.995)
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(FIGS / f"fig_ann_vs_pinn_traces.{ext}", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"wrote {FIGS/'fig_ann_vs_pinn.png'} and {FIGS/'fig_ann_vs_pinn_traces.png'}")


if __name__ == "__main__":
    main()