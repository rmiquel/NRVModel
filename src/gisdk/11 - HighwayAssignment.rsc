/*
This script file makes any final preparations to the trip tables
before setting up and running assignment.

During assignment, options are in place to capture statistics
for the model cycle.  These are returned and used to determine
if another feedback cycle is necessary.
*/

Macro "Highway Assignment" (Args)
  RunMacro("Assignment Matrix Creation")
  {rmse, prmse} = RunMacro("Run Highway Assignment")
  RunMacro("Log Cycle RMSE", rmse, prmse)
  return(prmse)
EndMacro

/*

*/

Macro "Assignment Matrix Creation" (Args)
  UpdateProgressBar("Assignment Matrix Creation", 0)

  scen_dir = Args.[Scenario Folder]
  period = MODELARGS.period
  cycle = MODELARGS.cycle

  // Clear the assignment directory on the very first run
  if cycle = 1 and period = MODELARGS.periods[1] then do
    dir = scen_dir + "/outputs/assignment"
    RunMacro("Clear Directory", dir)
  end

  // Create the assignment matrix
  opts = null
  opts.from_mtx = scen_dir + "/outputs/directionality/od_vehicle_hwy_trips_" +
    period + ".mtx"
  opts.to_mtx = scen_dir + "/outputs/assignment/assignment_" + period + ".mtx"
  opts.to_mtx_label = "assigned " + period + " OD table "
  opts.equiv_tbl = scen_dir + "/inputs/assignment/assignment_mtx_creation.csv"
  RunMacro("Matrix Crosswalk", opts)
EndMacro

/*
Sets up options for TCs MMA assignment
Includes options to support feedback/cycling
*/

Macro "Run Highway Assignment" (Args)
  UpdateProgressBar("Run Highway Assignment", 0)

  scen_dir = Args.[Scenario Folder]
  period = MODELARGS.period

  // Set options for the OUE macro call
  opts = null
  opts.period = period
  opts.hwy_dbd = Args.hwy_dbd
  opts.cycle = MODELARGS.cycle
  opts.asn_dir = scen_dir + "/outputs/assignment"
  opts.trip_mtx = opts.asn_dir + "/assignment_" + period + ".mtx"
  opts.toll_mtx = null
  opts.net_file = scen_dir + "/outputs/networks/sr3_" + period + ".net"
  opts.class_param_file = scen_dir +
    "/inputs/assignment/assignment_class_parameters.csv"

  {rmse, prmse} = RunMacro("PUE Assignment", opts)

  RunMacro("Close All")
  return({rmse, prmse})
EndMacro

/*
Logs the RMSE between feedback cycles (assignment back to skimming)

Depends
  gplyr
*/

Macro "Log Cycle RMSE" (rmse, prmse)
  UpdateProgressBar("Log Cycle RMSE", 0)

  scen_dir = Args.[Scenario Folder]
  period = MODELARGS.period
  cycle = MODELARGS.cycle
  log_file = scen_dir + "/outputs/assignment/cycle_rmse_" + period + ".csv"

  // Create data frame of current cycle and rmse
  tbl.cycle = cycle
  tbl.rmse = rmse
  tbl.prmse = prmse
  new_df = CreateObject("df", tbl)

  if cycle > 1 then do
    // Append to existing log file
    df = CreateObject("df")
    df.read_csv(log_file)
    df.bind_rows(new_df)
    new_df = df
  end

  new_df.write_csv(log_file)
EndMacro
