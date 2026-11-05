"""
validate_pinn.py - evaluates the trained PINN on the validation slice (85-100%).

    python validate_pinn.py
    python validate_pinn.py --noise
    python validate_pinn.py --csv ../data/valid_stair.csv --whole

The model never saw this slice during training. It was not used for the
gradients, for early stopping or for fitting the scalers, so these are the
numbers I quote.
"""

import argparse
from pinn_core import (DATA_DIR, load_csv, make_pairs, split_idx,
                       load_model, evaluate, add_sensor_noise)


def main(a):
    model, xs, ys, Ts_ck, targs = load_model()
    print(f"loaded model: width {targs['width']}, depth {targs['depth']}, "
          f"w_phys {targs['w_phys']}")

    df, Ts = load_csv(a.csv)
    if a.noise:
        df = add_sensor_noise(df, a.seed, a.quant, a.sigma)
        print(f"sensor noise: quantisation {a.quant} cm, sigma {a.sigma} cm")

    X, Y, reset = make_pairs(df)
    if a.whole:
        idx = range(len(X)); slice_name = "whole file"
    else:
        idx = split_idx(len(X), "validate"); slice_name = "validate slice 85-100%"
    X, Y, reset = X[idx], Y[idx], reset[idx]
    print(f"evaluating {slice_name}: {len(X)} pairs")

    tag = a.tag or ("validate_noisy" if a.noise else "validate")
    M, one, free = evaluate(model, xs, ys, X, Y, Ts, tag, reset)

    fr = M[M["mode"] == "free-run"]
    print("\n--- headline numbers (free-run, unseen data) ---")
    for r in fr.itertuples():
        print(f"   {r.state}:  RMSE {r.RMSE:.4f} cm   R2 {r.R2:.5f}   "
              f"NRMSE {r.NRMSE_pct:.2f}%")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=str(DATA_DIR / "train01.csv"))
    ap.add_argument("--tag", default=None)
    ap.add_argument("--whole", action="store_true",
                    help="use the whole file instead of the 85-100% slice")
    ap.add_argument("--noise", action="store_true")
    ap.add_argument("--quant", type=float, default=0.075)
    ap.add_argument("--sigma", type=float, default=0.02)
    ap.add_argument("--seed", type=int, default=0)
    main(ap.parse_args())