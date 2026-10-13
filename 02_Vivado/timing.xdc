#=====================================================================
# timing.xdc -- timing constraints
#---------------------------------------------------------------------
# This project does NOT target a physical board, so there are no pin
# location or I/O standard constraints here.
#
# The one constraint that IS needed is the clock definition. Without it
# Vivado has no reference to measure against and every timing report
# comes back as "NA". Declaring a 100 MHz clock lets the tool compute
# real setup/hold slack and identify the critical path -- which for this
# design is expected to run through the ripple-carry chain.
#=====================================================================

create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk]

# The design is driven by a testbench, not by board I/O. Telling the tool
# not to worry about input/output delays keeps the report focused on the
# internal register-to-register paths, which is what actually matters here.
set_false_path -from [get_ports rst_n]
