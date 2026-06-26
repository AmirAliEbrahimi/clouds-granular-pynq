# ----------------------------------------------------------------------------
# build_project.tcl - reproducible Vivado project for clouds-granular-pynq.
#
# Adds the RTL sources BEFORE sourcing the block design, which resolves the
#   [BD 41-2925] "module references: audio_engine ... add the sources"
# warning emitted when soc_bd.tcl is sourced on its own.
#
# Run from the repo root:
#   vivado -mode batch -source scripts/build_project.tcl
# or in the Vivado Tcl console:
#   cd <repo-root>; source scripts/build_project.tcl
#
# Tested intent: Vivado 2025.1, board TUL PYNQ-Z2.
# ----------------------------------------------------------------------------
set repo_dir [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $repo_dir vivado_project]
set proj_name clouds_pynq

create_project $proj_name $proj_dir -part xc7z020clg400-1 -force
catch { set_property board_part tul.com.tw:pynq-z2:part0:1.0 [current_project] }

# 1) RTL first, so audio_engine resolves as a module reference in the BD
add_files -norecurse [glob [file join $repo_dir rtl *.v]]
set_property top audio_engine [current_fileset]
update_compile_order -fileset sources_1

# 2) constraints
add_files -fileset constrs_1 -norecurse [file join $repo_dir constraints audio.xdc]

# 3) build the block design
source [file join $repo_dir bd soc_bd.tcl]

# 4) generate the BD wrapper and make it the top
set bd [get_files soc_bd.bd]
make_wrapper -files $bd -top
set wrap [glob -nocomplain [file join $proj_dir *.gen  sources_1 bd soc_bd hdl soc_bd_wrapper.v]]
if { $wrap eq "" } {
  set wrap [glob -nocomplain [file join $proj_dir *.srcs sources_1 bd soc_bd hdl soc_bd_wrapper.v]]
}
add_files -norecurse $wrap
set_property top soc_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "==> Project ready at $proj_dir"
puts "==> To build the bitstream:"
puts "    launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "    wait_on_run impl_1"
