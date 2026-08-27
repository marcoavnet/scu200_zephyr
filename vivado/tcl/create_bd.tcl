# Proc to create BD system
proc cr_bd_system { parentCell } {

  # CHANGE DESIGN NAME HERE
  set design_name system

  common::send_gid_msg -ssname BD::TCL -id 2010 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

  create_bd_design $design_name

  set bCheckIPsPassed 1
  ##################################################################
  # CHECK IPs
  ##################################################################
  set bCheckIPs 1
  if { $bCheckIPs == 1 } {
     set list_check_ips "\ 
  xilinx.com:ip:microblaze_riscv:*\
  xilinx.com:ip:lmb_v10:*\
  xilinx.com:ip:lmb_bram_if_cntlr:*\
  xilinx.com:ip:blk_mem_gen:*\
  xilinx.com:ip:axi_timer:*\
  xilinx.com:ip:axi_gpio:*\
  xilinx.com:ip:axi_uartlite:*\
  xilinx.com:ip:axi_quad_spi:*\
  xilinx.com:ip:smartconnect:*\
  xilinx.com:ip:axi_iic:*\
  xilinx.com:ip:clk_wiz:*\
  xilinx.com:ip:proc_sys_reset:*\
  xilinx.com:ip:lpddrmc:*\
  xilinx.com:ip:axi_intc:*\
  xilinx.com:ip:mdm_riscv:*\
  xilinx.com:inline_hdl:ilconcat:*\
  "

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

  }

  if { $bCheckIPsPassed != 1 } {
    common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
    return 3
  }

  
# Hierarchical cell: irpt_dbg
proc create_hier_cell_irpt_dbg { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_irpt_dbg() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:mbinterrupt_rtl:1.0 interrupt

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:mbdebug_rtl:3.0 MBDEBUG_0


  # Create pins
  create_bd_pin -dir I -type clk s_axi_aclk
  create_bd_pin -dir I -type rst s_axi_aresetn
  create_bd_pin -dir O -type rst Debug_SYS_Rst
  create_bd_pin -dir I -from 0 -to 0 trpt_timer
  create_bd_pin -dir I -from 0 -to 0 irpt_uart
  create_bd_pin -dir I -from 0 -to 0 irpt_spi_flash
  create_bd_pin -dir I -from 0 -to 0 irpt_i2c

  # Create instance: microblaze_riscv_0_axi_intc, and set properties
  set microblaze_riscv_0_axi_intc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc microblaze_riscv_0_axi_intc ]
  set_property CONFIG.C_HAS_FAST {0} $microblaze_riscv_0_axi_intc


  # Create instance: mdm_1, and set properties
  set mdm_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mdm_riscv mdm_1 ]

  # Create instance: microblaze_riscv_0_concat, and set properties
  set microblaze_riscv_0_concat [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat microblaze_riscv_0_concat ]
  set_property CONFIG.NUM_PORTS {4} $microblaze_riscv_0_concat


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins microblaze_riscv_0_axi_intc/interrupt] [get_bd_intf_pins interrupt]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins microblaze_riscv_0_axi_intc/s_axi] [get_bd_intf_pins s_axi]
  connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins mdm_1/MBDEBUG_0] [get_bd_intf_pins MBDEBUG_0]

  # Create port connections
  connect_bd_net -net In0_1  [get_bd_pins irpt_uart] \
  [get_bd_pins microblaze_riscv_0_concat/In0]
  connect_bd_net -net In1_1  [get_bd_pins trpt_timer] \
  [get_bd_pins microblaze_riscv_0_concat/In1]
  connect_bd_net -net In2_1  [get_bd_pins irpt_spi_flash] \
  [get_bd_pins microblaze_riscv_0_concat/In2]
  connect_bd_net -net In3_1  [get_bd_pins irpt_i2c] \
  [get_bd_pins microblaze_riscv_0_concat/In3]
  connect_bd_net -net mdm_1_Debug_SYS_Rst  [get_bd_pins mdm_1/Debug_SYS_Rst] \
  [get_bd_pins Debug_SYS_Rst]
  connect_bd_net -net microblaze_riscv_0_concat_dout  [get_bd_pins microblaze_riscv_0_concat/dout] \
  [get_bd_pins microblaze_riscv_0_axi_intc/intr]
  connect_bd_net -net s_axi_aclk_1  [get_bd_pins s_axi_aclk] \
  [get_bd_pins microblaze_riscv_0_axi_intc/s_axi_aclk]
  connect_bd_net -net s_axi_aresetn_1  [get_bd_pins s_axi_aresetn] \
  [get_bd_pins microblaze_riscv_0_axi_intc/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}
  
# Hierarchical cell: lpddr5
proc create_hier_cell_lpddr5 { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_lpddr5() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S00_AXI

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 default_sysclk1_lpddrmc

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:lpddr5_rtl:1.0 lpddr5_sdram

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S01_AXI


  # Create pins
  create_bd_pin -dir I -type clk aclk
  create_bd_pin -dir I -type rst aresetn

  # Create instance: smartconnect_0, and set properties
  set smartconnect_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smartconnect_0 ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $smartconnect_0


  # Create instance: lpddrmc_0, and set properties
  set lpddrmc_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lpddrmc lpddrmc_0 ]
  set_property -dict [list \
    CONFIG.LPDDR5_BOARD_INTERFACE {lpddr5_sdram} \
    CONFIG.SYSCLK_BOARD_INTERFACE {default_sysclk1_lpddrmc} \
  ] $lpddrmc_0


  # Create instance: smartconnect_1, and set properties
  set smartconnect_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smartconnect_1 ]
  set_property CONFIG.NUM_SI {1} $smartconnect_1


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins lpddrmc_0/SYS_CLK] [get_bd_intf_pins default_sysclk1_lpddrmc]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins lpddrmc_0/LPDDR5] [get_bd_intf_pins lpddr5_sdram]
  connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins smartconnect_1/S00_AXI] [get_bd_intf_pins S01_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_M_AXI_DC [get_bd_intf_pins S00_AXI] [get_bd_intf_pins smartconnect_0/S00_AXI]
  connect_bd_intf_net -intf_net smartconnect_0_M00_AXI [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins lpddrmc_0/S0_AXI]
  connect_bd_intf_net -intf_net smartconnect_1_M00_AXI [get_bd_intf_pins smartconnect_1/M00_AXI] [get_bd_intf_pins lpddrmc_0/S1_AXI]

  # Create port connections
  connect_bd_net -net microblaze_riscv_0_Clk  [get_bd_pins aclk] \
  [get_bd_pins smartconnect_0/aclk] \
  [get_bd_pins lpddrmc_0/aclk1] \
  [get_bd_pins lpddrmc_0/aclk0] \
  [get_bd_pins smartconnect_1/aclk]
  connect_bd_net -net rst_clk_wiz_1_100M_peripheral_aresetn  [get_bd_pins aresetn] \
  [get_bd_pins smartconnect_0/aresetn] \
  [get_bd_pins smartconnect_1/aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}
  
# Hierarchical cell: clk_rst
proc create_hier_cell_clk_rst { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_clk_rst() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_diff_clock


  # Create pins
  create_bd_pin -dir O -type clk clk_sys
  create_bd_pin -dir I -type rst reset
  create_bd_pin -dir O -type clk clk_out2
  create_bd_pin -dir O -from 0 -to 0 -type rst bus_struct_reset
  create_bd_pin -dir O -type rst mb_reset
  create_bd_pin -dir O -from 0 -to 0 -type rst peripheral_aresetn
  create_bd_pin -dir I -type rst mb_debug_sys_rst

  # Create instance: clk_wiz_1, and set properties
  set clk_wiz_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_1 ]
  set_property -dict [list \
    CONFIG.CLKOUT1_JITTER {102.086} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.CLKOUT2_JITTER {115.831} \
    CONFIG.CLKOUT2_PHASE_ERROR {87.180} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLK_IN1_BOARD_INTERFACE {sys_diff_clock} \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F {6.000} \
    CONFIG.MMCM_CLKOUT1_DIVIDE {12} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.RESET_BOARD_INTERFACE {reset} \
    CONFIG.RESET_PORT {resetn} \
    CONFIG.RESET_TYPE {ACTIVE_LOW} \
    CONFIG.USE_BOARD_FLOW {true} \
  ] $clk_wiz_1


  # Create instance: rst_clk_wiz_1_200M, and set properties
  set rst_clk_wiz_1_200M [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_clk_wiz_1_200M ]
  set_property -dict [list \
    CONFIG.RESET_BOARD_INTERFACE {reset} \
    CONFIG.USE_BOARD_FLOW {true} \
  ] $rst_clk_wiz_1_200M


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins clk_wiz_1/CLK_IN1_D] [get_bd_intf_pins sys_diff_clock]

  # Create port connections
  connect_bd_net -net clk_wiz_1_clk_out1  [get_bd_pins clk_wiz_1/clk_out1] \
  [get_bd_pins clk_sys] \
  [get_bd_pins rst_clk_wiz_1_200M/slowest_sync_clk]
  connect_bd_net -net clk_wiz_1_clk_out2  [get_bd_pins clk_wiz_1/clk_out2] \
  [get_bd_pins clk_out2]
  connect_bd_net -net clk_wiz_1_locked  [get_bd_pins clk_wiz_1/locked] \
  [get_bd_pins rst_clk_wiz_1_200M/dcm_locked]
  connect_bd_net -net mb_debug_sys_rst_1  [get_bd_pins mb_debug_sys_rst] \
  [get_bd_pins rst_clk_wiz_1_200M/mb_debug_sys_rst]
  connect_bd_net -net reset_1  [get_bd_pins reset] \
  [get_bd_pins clk_wiz_1/resetn] \
  [get_bd_pins rst_clk_wiz_1_200M/ext_reset_in]
  connect_bd_net -net rst_clk_wiz_1_200M_bus_struct_reset  [get_bd_pins rst_clk_wiz_1_200M/bus_struct_reset] \
  [get_bd_pins bus_struct_reset]
  connect_bd_net -net rst_clk_wiz_1_200M_mb_reset  [get_bd_pins rst_clk_wiz_1_200M/mb_reset] \
  [get_bd_pins mb_reset]
  connect_bd_net -net rst_clk_wiz_1_200M_peripheral_aresetn  [get_bd_pins rst_clk_wiz_1_200M/peripheral_aresetn] \
  [get_bd_pins peripheral_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}
  
# Hierarchical cell: peripherals
proc create_hier_cell_peripherals { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_peripherals() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M00_AXI

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S00_AXI

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 LEDs

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 push_buttons_5bits

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 dip_switches_8bits

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uartb

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 iic_0


  # Create pins
  create_bd_pin -dir I -type clk s_axi_aclk
  create_bd_pin -dir I -type rst s_axi_aresetn
  create_bd_pin -dir O -type intr irpt_timer
  create_bd_pin -dir O -type intr irpt_uart0
  create_bd_pin -dir I -type clk ext_spi_clk
  create_bd_pin -dir O -type intr irpt_spi_flash
  create_bd_pin -dir O -type intr irpt_i2c

  # Create instance: axi_timer_0, and set properties
  set axi_timer_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer axi_timer_0 ]

  # Create instance: gpio_pushB_DIP, and set properties
  set gpio_pushB_DIP [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio gpio_pushB_DIP ]
  set_property -dict [list \
    CONFIG.GPIO2_BOARD_INTERFACE {dip_switches_8bits} \
    CONFIG.GPIO_BOARD_INTERFACE {push_buttons_5bits} \
    CONFIG.USE_BOARD_FLOW {true} \
  ] $gpio_pushB_DIP


  # Create instance: axi_uartlite_0, and set properties
  set axi_uartlite_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite axi_uartlite_0 ]
  set_property -dict [list \
    CONFIG.C_BAUDRATE {115200} \
    CONFIG.C_S_AXI_ACLK_FREQ_HZ {200000000} \
    CONFIG.UARTLITE_BOARD_INTERFACE {uartb} \
    CONFIG.USE_BOARD_FLOW {true} \
  ] $axi_uartlite_0


  # Create instance: axi_quad_spi_0, and set properties
  set axi_quad_spi_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_quad_spi axi_quad_spi_0 ]
  set_property -dict [list \
    CONFIG.C_FIFO_DEPTH {256} \
    CONFIG.C_SCK_RATIO {4} \
    CONFIG.C_USE_STARTUP {1} \
    CONFIG.C_USE_STARTUP_INT {1} \
  ] $axi_quad_spi_0


  # Create instance: gpio_LEDs, and set properties
  set gpio_LEDs [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio gpio_LEDs ]
  set_property -dict [list \
    CONFIG.C_IS_DUAL {0} \
    CONFIG.GPIO2_BOARD_INTERFACE {Custom} \
    CONFIG.GPIO_BOARD_INTERFACE {led_8bits} \
    CONFIG.USE_BOARD_FLOW {true} \
  ] $gpio_LEDs


  # Create instance: microblaze_riscv_0_axi_periph, and set properties
  set microblaze_riscv_0_axi_periph [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect microblaze_riscv_0_axi_periph ]
  set_property -dict [list \
    CONFIG.NUM_MI {7} \
    CONFIG.NUM_SI {1} \
  ] $microblaze_riscv_0_axi_periph


  # Create instance: axi_iic_0, and set properties
  set axi_iic_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic axi_iic_0 ]
  set_property CONFIG.IIC_BOARD_INTERFACE {iic} $axi_iic_0


  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins gpio_pushB_DIP/GPIO2] [get_bd_intf_pins dip_switches_8bits]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins microblaze_riscv_0_axi_periph/M00_AXI] [get_bd_intf_pins M00_AXI]
  connect_bd_intf_net -intf_net Conn3 [get_bd_intf_pins axi_uartlite_0/UART] [get_bd_intf_pins uartb]
  connect_bd_intf_net -intf_net Conn4 [get_bd_intf_pins microblaze_riscv_0_axi_periph/S00_AXI] [get_bd_intf_pins S00_AXI]
  connect_bd_intf_net -intf_net Conn5 [get_bd_intf_pins axi_iic_0/IIC] [get_bd_intf_pins iic_0]
  connect_bd_intf_net -intf_net Conn9 [get_bd_intf_pins gpio_LEDs/GPIO] [get_bd_intf_pins LEDs]
  connect_bd_intf_net -intf_net gpio_pushB_DIP_GPIO [get_bd_intf_pins push_buttons_5bits] [get_bd_intf_pins gpio_pushB_DIP/GPIO]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M01_AXI [get_bd_intf_pins axi_timer_0/S_AXI] [get_bd_intf_pins microblaze_riscv_0_axi_periph/M01_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M02_AXI [get_bd_intf_pins axi_uartlite_0/S_AXI] [get_bd_intf_pins microblaze_riscv_0_axi_periph/M02_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M03_AXI [get_bd_intf_pins gpio_LEDs/S_AXI] [get_bd_intf_pins microblaze_riscv_0_axi_periph/M03_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M04_AXI [get_bd_intf_pins gpio_pushB_DIP/S_AXI] [get_bd_intf_pins microblaze_riscv_0_axi_periph/M04_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M05_AXI [get_bd_intf_pins axi_quad_spi_0/AXI_LITE] [get_bd_intf_pins microblaze_riscv_0_axi_periph/M05_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_axi_periph_M06_AXI [get_bd_intf_pins microblaze_riscv_0_axi_periph/M06_AXI] [get_bd_intf_pins axi_iic_0/S_AXI]

  # Create port connections
  connect_bd_net -net axi_iic_0_iic2intc_irpt  [get_bd_pins axi_iic_0/iic2intc_irpt] \
  [get_bd_pins irpt_i2c]
  connect_bd_net -net axi_quad_spi_0_ip2intc_irpt  [get_bd_pins axi_quad_spi_0/ip2intc_irpt] \
  [get_bd_pins irpt_spi_flash]
  connect_bd_net -net axi_timer_0_interrupt  [get_bd_pins axi_timer_0/interrupt] \
  [get_bd_pins irpt_timer]
  connect_bd_net -net axi_uartlite_0_interrupt  [get_bd_pins axi_uartlite_0/interrupt] \
  [get_bd_pins irpt_uart0]
  connect_bd_net -net ext_spi_clk_1  [get_bd_pins ext_spi_clk] \
  [get_bd_pins axi_quad_spi_0/ext_spi_clk]
  connect_bd_net -net s_axi_aclk_1  [get_bd_pins s_axi_aclk] \
  [get_bd_pins axi_quad_spi_0/s_axi_aclk] \
  [get_bd_pins axi_timer_0/s_axi_aclk] \
  [get_bd_pins axi_uartlite_0/s_axi_aclk] \
  [get_bd_pins gpio_LEDs/s_axi_aclk] \
  [get_bd_pins gpio_pushB_DIP/s_axi_aclk] \
  [get_bd_pins microblaze_riscv_0_axi_periph/aclk] \
  [get_bd_pins axi_iic_0/s_axi_aclk]
  connect_bd_net -net s_axi_aresetn_1  [get_bd_pins s_axi_aresetn] \
  [get_bd_pins axi_quad_spi_0/s_axi_aresetn] \
  [get_bd_pins axi_timer_0/s_axi_aresetn] \
  [get_bd_pins axi_uartlite_0/s_axi_aresetn] \
  [get_bd_pins gpio_LEDs/s_axi_aresetn] \
  [get_bd_pins gpio_pushB_DIP/s_axi_aresetn] \
  [get_bd_pins microblaze_riscv_0_axi_periph/aresetn] \
  [get_bd_pins axi_iic_0/s_axi_aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}
  
# Hierarchical cell: microblaze_riscv_0_local_memory
proc create_hier_cell_microblaze_riscv_0_local_memory { parentCell nameHier } {

  variable script_folder

  if { $parentCell eq "" || $nameHier eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2092 -severity "ERROR" "create_hier_cell_microblaze_riscv_0_local_memory() - Empty argument(s)!"}
     return
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 DLMB

  create_bd_intf_pin -mode MirroredMaster -vlnv xilinx.com:interface:lmb_rtl:1.0 ILMB


  # Create pins
  create_bd_pin -dir I -type clk LMB_Clk
  create_bd_pin -dir I -type rst SYS_Rst

  # Create instance: dlmb_v10, and set properties
  set dlmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10 dlmb_v10 ]

  # Create instance: ilmb_v10, and set properties
  set ilmb_v10 [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10 ilmb_v10 ]

  # Create instance: dlmb_bram_if_cntlr, and set properties
  set dlmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr dlmb_bram_if_cntlr ]
  set_property CONFIG.C_ECC {0} $dlmb_bram_if_cntlr


  # Create instance: ilmb_bram_if_cntlr, and set properties
  set ilmb_bram_if_cntlr [ create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr ilmb_bram_if_cntlr ]
  set_property CONFIG.C_ECC {0} $ilmb_bram_if_cntlr


  # Create instance: lmb_bram, and set properties
  set lmb_bram [ create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen lmb_bram ]
  set_property -dict [list \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Memory_Type {True_Dual_Port_RAM} \
    CONFIG.Port_B_Clock {100} \
    CONFIG.Port_B_Enable_Rate {100} \
    CONFIG.Port_B_Write_Rate {50} \
    CONFIG.Use_RSTB_Pin {true} \
    CONFIG.use_bram_block {BRAM_Controller} \
  ] $lmb_bram


  # Create interface connections
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb [get_bd_intf_pins dlmb_v10/LMB_M] [get_bd_intf_pins DLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb_bus [get_bd_intf_pins dlmb_v10/LMB_Sl_0] [get_bd_intf_pins dlmb_bram_if_cntlr/SLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb_cntlr [get_bd_intf_pins dlmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTA]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb [get_bd_intf_pins ilmb_v10/LMB_M] [get_bd_intf_pins ILMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb_bus [get_bd_intf_pins ilmb_v10/LMB_Sl_0] [get_bd_intf_pins ilmb_bram_if_cntlr/SLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb_cntlr [get_bd_intf_pins ilmb_bram_if_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTB]

  # Create port connections
  connect_bd_net -net SYS_Rst_1  [get_bd_pins SYS_Rst] \
  [get_bd_pins dlmb_bram_if_cntlr/LMB_Rst] \
  [get_bd_pins dlmb_v10/SYS_Rst] \
  [get_bd_pins ilmb_bram_if_cntlr/LMB_Rst] \
  [get_bd_pins ilmb_v10/SYS_Rst]
  connect_bd_net -net microblaze_riscv_0_Clk  [get_bd_pins LMB_Clk] \
  [get_bd_pins dlmb_bram_if_cntlr/LMB_Clk] \
  [get_bd_pins dlmb_v10/LMB_Clk] \
  [get_bd_pins ilmb_bram_if_cntlr/LMB_Clk] \
  [get_bd_pins ilmb_v10/LMB_Clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}
  variable script_folder

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set sys_diff_clock [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_diff_clock ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {100000000} \
   ] $sys_diff_clock

  set led_8bits [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 led_8bits ]

  set push_buttons_5bits [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 push_buttons_5bits ]

  set dip_switches_8bits [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 dip_switches_8bits ]

  set uartb [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:uart_rtl:1.0 uartb ]

  set lpddr5_sdram [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:lpddr5_rtl:1.0 lpddr5_sdram ]

  set default_sysclk1_lpddrmc [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 default_sysclk1_lpddrmc ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {266670000} \
   ] $default_sysclk1_lpddrmc

  set iic_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 iic_0 ]


  # Create ports
  set reset [ create_bd_port -dir I -type rst reset ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_LOW} \
 ] $reset

  # Create instance: microblaze_riscv_0, and set properties
  set microblaze_riscv_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze_riscv microblaze_riscv_0 ]
  set_property -dict [list \
    CONFIG.C_DEBUG_ENABLED {1} \
    CONFIG.C_D_AXI {1} \
    CONFIG.C_D_LMB {1} \
    CONFIG.C_ILL_INSTR_EXCEPTION {1} \
    CONFIG.C_I_LMB {1} \
    CONFIG.C_M_AXI_D_BUS_EXCEPTION {1} \
    CONFIG.C_OPTIMIZATION {0} \
    CONFIG.C_USE_COMPRESSION {1} \
    CONFIG.C_USE_MULDIV {1} \
    CONFIG.G_TEMPLATE_LIST {2} \
  ] $microblaze_riscv_0


  # Create instance: microblaze_riscv_0_local_memory
  create_hier_cell_microblaze_riscv_0_local_memory [current_bd_instance .] microblaze_riscv_0_local_memory

  # Create instance: peripherals
  create_hier_cell_peripherals [current_bd_instance .] peripherals

  # Create instance: clk_rst
  create_hier_cell_clk_rst [current_bd_instance .] clk_rst

  # Create instance: lpddr5
  create_hier_cell_lpddr5 [current_bd_instance .] lpddr5

  # Create instance: irpt_dbg
  create_hier_cell_irpt_dbg [current_bd_instance .] irpt_dbg

  # Create interface connections
  connect_bd_intf_net -intf_net default_sysclk1_lpddrmc_1 [get_bd_intf_ports default_sysclk1_lpddrmc] [get_bd_intf_pins lpddr5/default_sysclk1_lpddrmc]
  connect_bd_intf_net -intf_net irpt_dbg_MBDEBUG_0 [get_bd_intf_pins microblaze_riscv_0/DEBUG] [get_bd_intf_pins irpt_dbg/MBDEBUG_0]
  connect_bd_intf_net -intf_net irpt_dbg_interrupt [get_bd_intf_pins microblaze_riscv_0/INTERRUPT] [get_bd_intf_pins irpt_dbg/interrupt]
  connect_bd_intf_net -intf_net lpddr5_lpddr5_sdram [get_bd_intf_ports lpddr5_sdram] [get_bd_intf_pins lpddr5/lpddr5_sdram]
  connect_bd_intf_net -intf_net microblaze_riscv_0_M_AXI_DC [get_bd_intf_pins microblaze_riscv_0/M_AXI_DC] [get_bd_intf_pins lpddr5/S00_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_M_AXI_DP [get_bd_intf_pins microblaze_riscv_0/M_AXI_DP] [get_bd_intf_pins peripherals/S00_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_M_AXI_IC [get_bd_intf_pins microblaze_riscv_0/M_AXI_IC] [get_bd_intf_pins lpddr5/S01_AXI]
  connect_bd_intf_net -intf_net microblaze_riscv_0_dlmb_1 [get_bd_intf_pins microblaze_riscv_0/DLMB] [get_bd_intf_pins microblaze_riscv_0_local_memory/DLMB]
  connect_bd_intf_net -intf_net microblaze_riscv_0_ilmb_1 [get_bd_intf_pins microblaze_riscv_0/ILMB] [get_bd_intf_pins microblaze_riscv_0_local_memory/ILMB]
  connect_bd_intf_net -intf_net peripherals_IIC_0 [get_bd_intf_ports iic_0] [get_bd_intf_pins peripherals/iic_0]
  connect_bd_intf_net -intf_net peripherals_LEDs [get_bd_intf_ports led_8bits] [get_bd_intf_pins peripherals/LEDs]
  connect_bd_intf_net -intf_net peripherals_M00_AXI [get_bd_intf_pins peripherals/M00_AXI] [get_bd_intf_pins irpt_dbg/s_axi]
  connect_bd_intf_net -intf_net peripherals_UART_0 [get_bd_intf_ports uartb] [get_bd_intf_pins peripherals/uartb]
  connect_bd_intf_net -intf_net peripherals_dip_switches_8bits [get_bd_intf_ports dip_switches_8bits] [get_bd_intf_pins peripherals/dip_switches_8bits]
  connect_bd_intf_net -intf_net peripherals_push_buttons_5bits [get_bd_intf_ports push_buttons_5bits] [get_bd_intf_pins peripherals/push_buttons_5bits]
  connect_bd_intf_net -intf_net sys_diff_clock_1 [get_bd_intf_ports sys_diff_clock] [get_bd_intf_pins clk_rst/sys_diff_clock]

  # Create port connections
  connect_bd_net -net SYS_Rst_1  [get_bd_pins clk_rst/bus_struct_reset] \
  [get_bd_pins microblaze_riscv_0_local_memory/SYS_Rst]
  connect_bd_net -net clk_rst_mb_reset  [get_bd_pins clk_rst/mb_reset] \
  [get_bd_pins microblaze_riscv_0/Reset]
  connect_bd_net -net ext_spi_clk_1  [get_bd_pins clk_rst/clk_out2] \
  [get_bd_pins peripherals/ext_spi_clk]
  connect_bd_net -net mb_debug_sys_rst_1  [get_bd_pins irpt_dbg/Debug_SYS_Rst] \
  [get_bd_pins clk_rst/mb_debug_sys_rst]
  connect_bd_net -net microblaze_riscv_0_Clk  [get_bd_pins clk_rst/clk_sys] \
  [get_bd_pins microblaze_riscv_0_local_memory/LMB_Clk] \
  [get_bd_pins peripherals/s_axi_aclk] \
  [get_bd_pins microblaze_riscv_0/Clk] \
  [get_bd_pins lpddr5/aclk] \
  [get_bd_pins irpt_dbg/s_axi_aclk]
  connect_bd_net -net peripherals_irpt_i2c  [get_bd_pins peripherals/irpt_i2c] \
  [get_bd_pins irpt_dbg/irpt_i2c]
  connect_bd_net -net peripherals_irpt_spi_flash  [get_bd_pins peripherals/irpt_spi_flash] \
  [get_bd_pins irpt_dbg/irpt_spi_flash]
  connect_bd_net -net peripherals_irpt_timer  [get_bd_pins peripherals/irpt_timer] \
  [get_bd_pins irpt_dbg/trpt_timer]
  connect_bd_net -net peripherals_irpt_uart0  [get_bd_pins peripherals/irpt_uart0] \
  [get_bd_pins irpt_dbg/irpt_uart]
  connect_bd_net -net reset_1  [get_bd_ports reset] \
  [get_bd_pins clk_rst/reset]
  connect_bd_net -net rst_clk_wiz_1_100M_peripheral_aresetn  [get_bd_pins clk_rst/peripheral_aresetn] \
  [get_bd_pins peripherals/s_axi_aresetn] \
  [get_bd_pins lpddr5/aresetn] \
  [get_bd_pins irpt_dbg/s_axi_aresetn]

  # Create address segments
  assign_bd_address -offset 0x40800000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs peripherals/axi_iic_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x44A00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs peripherals/axi_quad_spi_0/AXI_LITE/Reg] -force
  assign_bd_address -offset 0x41C00000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs peripherals/axi_timer_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x40600000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs peripherals/axi_uartlite_0/S_AXI/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x00040000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs microblaze_riscv_0_local_memory/dlmb_bram_if_cntlr/SLMB/Mem] -force
  assign_bd_address -offset 0x40000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs peripherals/gpio_LEDs/S_AXI/Reg] -force
  assign_bd_address -offset 0x40010000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs peripherals/gpio_pushB_DIP/S_AXI/Reg] -force
  assign_bd_address -offset 0x80000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs lpddr5/lpddrmc_0/LPDDRMC_S0_AXI/LPDDRMC_ADDRESS_BLOCK] -force
  assign_bd_address -offset 0x41200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Data] [get_bd_addr_segs irpt_dbg/microblaze_riscv_0_axi_intc/S_AXI/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x00040000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Instruction] [get_bd_addr_segs microblaze_riscv_0_local_memory/ilmb_bram_if_cntlr/SLMB/Mem] -force
  assign_bd_address -offset 0x80000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces microblaze_riscv_0/Instruction] [get_bd_addr_segs lpddr5/lpddrmc_0/LPDDRMC_S1_AXI/LPDDRMC_ADDRESS_BLOCK] -force


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
  close_bd_design $design_name 
}
# End of cr_bd_system()
