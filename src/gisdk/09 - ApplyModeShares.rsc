/*
Mode choice is broken into two steps:

Calc Mode Shares (other script file)
  Calculates utilities, probabilities, and logsums for every ij pair using
  skim and zonal data.  This makes the logsum available to the
  distribution model.

Apply Mode Shares (this script file)
  Applies to the probabilities calculated in MC1 to the trip matrices output
  by the distribution model.
*/

Macro "Apply Mode Shares" (Args)
  RunMacro("Remove School Bus Trips"), Args)
  RunMacro("Apply MC Probabilities"), Args)
EndMacro

/*

*/

Macro "Remove School Bus Trips" (Args)
  UpdateProgressBar("Remove School Bus Trips", 0)
  shared no_bus_file

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  output_dir = scen_dir + "/outputs/mode"

  // Copy the DC matrix to a MC matrix
  dc_mtx_file = scen_dir + "/outputs/distribution/_trips_" + period + ".mtx"
  no_bus_file = output_dir + "/_trips_wo_bus_" + period + ".mtx"
  CopyFile(dc_mtx_file, no_bus_file)

  opts = null
  opts.mtx_file = no_bus_file
  opts.param_file = scen_dir + "/inputs/mode/bus_share.csv"
  RunMacro("Calculate Cores", opts)

  RunMacro("Close All")
EndMacro

/*

*/

Macro "Apply MC Probabilities" (Args)
  UpdateProgressBar("Apply MC Probabilities", 0)
  shared no_bus_file

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  
  opts = null
  opts.trip_matrix = no_bus_file
  mode_dir = scen_dir + "/outputs/mode"
  opts.prob_matrix = mode_dir + "/_mc_resident_" + period + ".mtx"
  opts.output_matrix = mode_dir + "/_mc_modal_trips_" + period + ".mtx"
  opts.coeffs_file = scen_dir + "/inputs/mode/mc_coefficients.csv"
  RunMacro("Split Trips by Mode", opts)
  
  if no_bus_file <> null then DeleteFile(no_bus_file)
EndMacro
