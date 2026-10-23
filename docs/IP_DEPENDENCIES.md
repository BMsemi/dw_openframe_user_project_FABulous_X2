# IP dependency policy

The chip project owns integration; the ReRAM repository owns reusable IP views.

```text
dw_openframe_user_project_FABulous_X2
└── ip/sky130_bmlabs_reram  @ pinned commit
    └── sky130_bmlabs_reram__cim32x32
```

## Clone and update

```bash
git clone --recurse-submodules https://github.com/BMsemi/dw_openframe_user_project_FABulous_X2.git
# Existing clone:
git submodule update --init --recursive
```

To review an IP update:

```bash
git -C ip/sky130_bmlabs_reram fetch origin
git -C ip/sky130_bmlabs_reram checkout <reviewed-commit>
python3 ip/sky130_bmlabs_reram/scripts/check_views.py
git add ip/sky130_bmlabs_reram ip/dependencies.json
```

Update `ip/dependencies.json` to the same commit and rerun chip-level
simulation, hardening, DRC and LVS before merging.

## Ownership boundary

The IP repository owns GDS, LEF, Liberty, black-box Verilog, behavioral models
and cell-level documentation. This project owns the wrapper, GPIO mapping,
placement, PDN, timing constraints, NDR settings and signoff reports.
