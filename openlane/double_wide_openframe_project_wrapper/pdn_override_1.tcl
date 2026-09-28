# Double-wide wrapper PDN configuration for Neuromorphic_X1_wb.
#
# The macro's top power-pin layer is met3. The standard LibreLane macro grid
# connects met4 to met5, which leaves this macro's five PG pins disconnected.
# This configuration keeps the normal wrapper grid but connects macro met3
# power pins upward to met4.

source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

puts "DW_NEURO_PDN_FIX_V5: classifying all OpenFrame supplies and connecting macro met3 to met4"

# The OpenFrame boundary exposes additional supply domains that this user
# design does not consume internally.  They still have boundary pin shapes in
# pin_template.def, so mark their database nets as POWER/GROUND.  Otherwise the
# global signal router attempts to connect the repeated boundary shapes as
# ordinary high-degree signal nets, which creates artificial edge congestion.
foreach net_name {vccd vddio vdda} {
    set db_net [[ord::get_db_block] findNet $net_name]
    if {$db_net != "NULL"} {
        $db_net setSpecial
        $db_net setSigType "POWER"
    }
}

foreach net_name {vssd vssio vssa} {
    set db_net [[ord::get_db_block] findNet $net_name]
    if {$db_net != "NULL"} {
        $db_net setSpecial
        $db_net setSigType "GROUND"
    }
}

set secondary []
foreach vdd $::env(VDD_NETS) gnd $::env(GND_NETS) {
    if { $vdd != $::env(VDD_NET) } {
        lappend secondary $vdd

        set db_net [[ord::get_db_block] findNet $vdd]
        if {$db_net == "NULL"} {
            set db_net [odb::dbNet_create [ord::get_db_block] $vdd]
        }
        $db_net setSpecial
        $db_net setSigType "POWER"
    }

    if { $gnd != $::env(GND_NET) } {
        lappend secondary $gnd

        set db_net [[ord::get_db_block] findNet $gnd]
        if {$db_net == "NULL"} {
            set db_net [odb::dbNet_create [ord::get_db_block] $gnd]
        }
        $db_net setSpecial
        $db_net setSigType "GROUND"
    }
}

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET) \
    -secondary_power $secondary

if { $::env(FP_PDN_MULTILAYER) == 1 } {
    define_pdn_grid \
        -name stdcell_grid \
        -starts_with POWER \
        -voltage_domain CORE \
        -pins "$::env(FP_PDN_VERTICAL_LAYER) $::env(FP_PDN_HORIZONTAL_LAYER)"

    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(FP_PDN_VERTICAL_LAYER) \
        -width $::env(FP_PDN_VWIDTH) \
        -pitch $::env(FP_PDN_VPITCH) \
        -offset $::env(FP_PDN_VOFFSET) \
        -spacing $::env(FP_PDN_VSPACING) \
        -starts_with POWER -extend_to_core_ring

    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(FP_PDN_HORIZONTAL_LAYER) \
        -width $::env(FP_PDN_HWIDTH) \
        -pitch $::env(FP_PDN_HPITCH) \
        -offset $::env(FP_PDN_HOFFSET) \
        -spacing $::env(FP_PDN_HSPACING) \
        -starts_with POWER -extend_to_core_ring

    add_pdn_connect \
        -grid stdcell_grid \
        -layers "$::env(FP_PDN_VERTICAL_LAYER) $::env(FP_PDN_HORIZONTAL_LAYER)"
} else {
    define_pdn_grid \
        -name stdcell_grid \
        -starts_with POWER \
        -voltage_domain CORE \
        -pins $::env(FP_PDN_VERTICAL_LAYER)

    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(FP_PDN_VERTICAL_LAYER) \
        -width $::env(FP_PDN_VWIDTH) \
        -pitch $::env(FP_PDN_VPITCH) \
        -offset $::env(FP_PDN_VOFFSET) \
        -spacing $::env(FP_PDN_VSPACING) \
        -starts_with POWER -extend_to_core_ring
}

if { $::env(FP_PDN_ENABLE_RAILS) == 1 } {
    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(FP_PDN_RAIL_LAYER) \
        -width $::env(FP_PDN_RAIL_WIDTH) \
        -followpins \
        -starts_with POWER

    add_pdn_connect \
        -grid stdcell_grid \
        -layers "$::env(FP_PDN_RAIL_LAYER) $::env(FP_PDN_VERTICAL_LAYER)"
}

if { $::env(FP_PDN_CORE_RING) == 1 } {
    if { $::env(FP_PDN_MULTILAYER) == 1 } {
        add_pdn_ring \
            -grid stdcell_grid \
            -layers "$::env(FP_PDN_VERTICAL_LAYER) $::env(FP_PDN_HORIZONTAL_LAYER)" \
            -widths "$::env(FP_PDN_CORE_RING_VWIDTH) $::env(FP_PDN_CORE_RING_HWIDTH)" \
            -spacings "$::env(FP_PDN_CORE_RING_VSPACING) $::env(FP_PDN_CORE_RING_HSPACING)" \
            -core_offset "$::env(FP_PDN_CORE_RING_VOFFSET) $::env(FP_PDN_CORE_RING_HOFFSET)"
    } else {
        throw APPLICATION "FP_PDN_CORE_RING cannot be used when FP_PDN_MULTILAYER is false."
    }
}

define_pdn_grid \
    -macro \
    -default \
    -name macro \
    -starts_with POWER \
    -halo "$::env(FP_PDN_HORIZONTAL_HALO) $::env(FP_PDN_VERTICAL_HALO)"

# Neuromorphic_X1_wb power pins are on met3; connect them to met4.
add_pdn_connect \
    -grid macro \
    -layers "met3 met4"

