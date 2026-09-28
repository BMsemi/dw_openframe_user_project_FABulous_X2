# System/Wishbone clock on GPIO14: 20 MHz.
create_clock -name sys_clk -period 50.000 [get_ports {gpio_in[14]}]
# External SPI mode-0 clock on GPIO15: maximum intended rate 5 MHz.
create_clock -name spi_sclk -period 200.000 [get_ports {gpio_in[15]}]
# The bridge contains explicit toggle synchronizers. The clocks are unrelated.
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks spi_sclk]
set_clock_uncertainty 1.000 [get_clocks sys_clk]
set_clock_uncertainty 2.000 [get_clocks spi_sclk]
# SPI chip-select and MOSI boundary timing.
set_input_delay -clock spi_sclk -max 20.000 \
    [get_ports {gpio_in[16] gpio_in[17]}]
set_input_delay -clock spi_sclk -min 0.000 \
    [get_ports {gpio_in[16] gpio_in[17]}]
# SPI MISO boundary timing.
set_output_delay -clock spi_sclk -max 20.000 \
    [get_ports {gpio_out[18]}]
set_output_delay -clock spi_sclk -min 0.000 \
    [get_ports {gpio_out[18]}]
# POR, external reset and scan/test controls are asynchronous or test-only.
set_false_path -from [get_ports {porb_h por_l porb_l resetb_h resetb_l}]
set_false_path -from [get_ports {gpio_in[21] gpio_in[22] gpio_in[35] gpio_in[36]}]
# CS_N asynchronously clears the SPI frame-local registers.  Keep its normal
# interface timing paths constrained, but do not time asynchronous-reset arcs.
# Without this exception the hold-repair step inserts hundreds of delay cells
# on RESET_B paths, creating a severe placement/routing hotspot.
set_false_path \
    -from [get_ports {gpio_in[16]}] \
    -to [get_pins -hierarchical */RESET_B]
