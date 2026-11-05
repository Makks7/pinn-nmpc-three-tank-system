# pinn-nmpc-three-tank-system

Physics-informed neural network (PINN) nonlinear model predictive control (NMPC) of a cascaded three-tank rig, developed in simulation with MATLAB/Simulink and PyTorch and then run on the physical laboratory rig.

The PINN is a one-step model of the plant that is trained on both data and the tank volume balances. It replaces the first-principles model inside the NMPC. It is compared with an identical network trained on data alone (ANN) and with an NMPC that uses the exact plant equations (FP-NMPC).

This repository is the three-tank case study (case study 4) of my final-year thesis on PINN-NMPC for process systems, supervised by Dr. A. Bamimore at Obafemi Awolowo University, Ile-Ife, Nigeria.

## Results

All numbers below are from closed-loop simulation of the same plant, with the same controller settings, for the three controllers. IAE is the integral of absolute error summed over the three tank levels (lower is better).

| **Test** | **PINN-NMPC** | **FP-NMPC** | **ANN-NMPC** |
|---|---|---|---|
| Servo (setpoint tracking), IAE in cm s | 412 | 334 | 938 |
| Regulatory (leak-valve closure), IAE in cm s | 1,302.5 | 1,300.9 | 1,411.1 |

- In setpoint tracking, the PINN cuts the ANN's error by 56% and comes within 24% of FP-NMPC, which has exact knowledge of the plant.
- In disturbance rejection, the PINN is within 0.12% of FP-NMPC. The leak-valve closure was never seen in training.
- Free-run prediction on unseen data has a mean RMSE of 0.116 cm for the PINN and 0.791 cm for the ANN (6.8 times higher).
- The median NMPC solve time is 0.26 s for the PINN and 1.48 s for the ANN. The ANN controller exceeded the 2 s sampling interval seven times, and the PINN never did.

Real-time results on the rig are preliminary and are described under [Real rig](#real-rig).

## The plant

Three tanks of different shapes, each 35 cm tall, stand in series: a cuboid, a trapezoidal prism and a circular segment. A pump feeds the first tank at flow rate `u1`. Proportional valves with openings `u2` and `u3` drain the second and third tanks, and two manual leak valves act as disturbances. The levels `h1`, `h2` and `h3` are the states and the controlled outputs. The rig follows Bamimore et al. (2021), cited below.

The process is hard to control for three reasons. It is multivariable and interacting, the outflows follow a power law in the level, and the changing tank cross-sections make the process gain vary widely across the operating range.

Operating point: `h = (14.29, 13.51, 16.06)` cm at `u1 = 100` cm³/s, `u2 = 0.40`, `u3 = 0.20`, with both leak valves at 0.333.

## Method

**Data.** An open-loop Simulink model of the corrected plant is excited with piecewise-constant random inputs held for 20 to 100 s. A 20,000 s run logged every 2 s gives 10,001 samples, and samples near tank-2 overflow are removed. The data are split 70/15/15 in time order into training, test (early stopping) and validation sets, so the validation score is not inflated by neighbouring samples.

**PINN.** A fully connected network (8-64-64-64-3, tanh) takes the three levels, the three inputs and the two leak-valve positions, and predicts the levels one sample later. The loss is the data error plus 0.1 times the midpoint-form residual of the volume balances. It is trained with Adam and a cosine learning-rate decay, with at most 6,000 epochs. The ANN baseline is the same network with the physics weight set to zero, trained on the same data, split, scaling, seed and optimiser.

**NMPC.** Sampling interval 2 s, prediction horizon 40 samples (80 s), control horizon 2 samples, with input, move and output bounds and a Lyapunov-type terminal constraint. The problem is solved by SQP (`fmincon`).

**Audit of the inherited plant model.** The original Simulink S-function was checked against the source paper before any data were generated. Four faults were found and fixed: a wrong discharge coefficient, a wrong pump input range, disturbance inputs that were read but never used, and a save routine that wrote every run to the same file. The tank height was also measured on the rig (35 cm), because the two source papers disagreed.

## Repository structure

| **Folder or file** | **Contents** |
|---|---|
| `base/` | Plant S-functions (the fixed version used for data generation is `three_tank_sfun_pinn.m`) and the MATLAB PINN forward pass |
| `python/` | Training (`train_pinn.py`, `train_ann.py`), test and validation scripts, `ann_vs_pinn.py` and the export check |
| `control/` | NMPC files used in Simulink, plus `nmpc_pinn.m` and `test_nmpc_offline.m` to check the loop in plain MATLAB |
| `helper/` | APRBS signal generation, data export and figure scripts |
| `data/`, `models/`, `weights/` | Training data, exported network weights and scaling |
| `figures/`, `figures_pub/` | Result figures and publication-quality versions |
| `results/servo_runs_11Sep2026/` | Saved Simulink servo runs from 11 September 2026 |
| `setup_project.m` | Puts every folder on the MATLAB path |

## Getting started

### Requirements

- Python 3 with PyTorch, NumPy, SciPy, pandas and Matplotlib
- MATLAB with Simulink and the Optimization Toolbox (developed on R2025b)

### Reproduce the simulation results

1. Run `setup_project` in MATLAB first, to put everything on the path.
2. Generate the training data with the scripts in `helper/` (for example `run_and_export('train01', 20000)`).
3. Train the PINN with `python python/train_pinn.py` and the ANN baseline with `python python/train_ann.py`. The weights and the scaling parameters must stay together in the exported `.mat` file, because a scaling mismatch fails silently.
4. Check accuracy with `python python/test_pinn.py` and `python python/validate_pinn.py`, and compare the two networks with `python python/ann_vs_pinn.py`.
5. Run the NMPC from the Simulink models in `control/`, or check the loop offline with `test_nmpc_offline.m`.

## Real rig

The rig uses a microcontroller (Arduino) that reads the tank level sensors, receives the control moves computed by the NMPC in Simulink, and drives the pump and the proportional valves. Run the initialisation script before pressing Run in Simulink.

TODO: name the real-time Simulink model and the initialisation script, and add a wiring or block diagram and a photo of the rig.

Status: the PINN-NMPC tracked setpoints on the physical rig in its first real-time run. Early rig runs were limited by a sagging power supply (about 12 V falling to about 11.5 V), and repair and further tests are in progress, so no real-time performance figures are reported here.

## Limitations

- The controller comparison is from simulation. Real-time results on the rig are not yet complete.
- The NMPC solver options and estimator gain were carried over from an earlier GRU-based controller and were not retuned for the PINN.
- Results are for one plant and one operating region.

## References

- Bamimore, A., Osinuga, A. B., Kehinde-Abajo, T. E., Osunleke, A. S. and Taiwo, O. (2021). A comparison of two artificial neural networks for modelling and predictive control of a cascaded three-tank system. *IFAC-PapersOnLine*, 54(21), 145-150.
- Raissi, M., Perdikaris, P. and Karniadakis, G. E. (2019). Physics-informed neural networks. *Journal of Computational Physics*, 378, 686-707.

## Citation

If you use this work, please cite the repository. A DOI will be added once the code is archived on Zenodo.

## License

MIT. See `LICENSE`.

## Contact

Emmanuel Alao, [github.com/Makks7](https://github.com/Makks7)
