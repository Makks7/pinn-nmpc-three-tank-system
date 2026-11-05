# Cascaded three-tank system (case study 4)

PINN-NMPC for the cascaded three-tank rig in the lab, tested in simulation and
on the real rig.

- `base/` - plant S-functions (the fixed version used for data generation is
  three_tank_sfun_pinn.m) and the MATLAB PINN forward pass
- `python/` - training (train_pinn.py, train_ann.py), test/validation and the
  export check
- `control/` - NMPC files used in Simulink, plus nmpc_pinn.m and
  test_nmpc_offline.m to check the loop in plain MATLAB
- `helper/` - APRBS signal generation, data export and figure scripts
- `data/`, `models/`, `weights/`, `figures/`, `figures_pub/` - data, models and results
- `results/servo_runs_11Sep2026/` - saved servo runs from 11 Sep 2026

Run `setup_project.m` first to put everything on the path. For the real rig,
run the init script before pressing Run in Simulink.
