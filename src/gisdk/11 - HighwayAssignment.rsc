/*
This script file makes any final preparations to the trip tables
before setting up and running assignment.

During assignment, options are in place to capture statistics
for the model cycle.  These are returned and used to determine
if another feedback cycle is necessary.
*/

Macro "Highway Assignment" (Args)
  for period in Args.Periods do
    Args.period = period
    RunMacro("Assignment Matrix Creation", Args)
    {rmse, prmse} = RunMacro("Run Highway Assignment", Args)
    RunMacro("Log Cycle RMSE", rmse, prmse, Args)
    Args.hwy_prmse.(period) = prmse
  end
  return(1)
EndMacro

/*

*/

Macro "Assignment Matrix Creation" (Args)
  UpdateProgressBar(Args.period + ": Assignment Matrix Creation", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  cycle = Args.Iteration

  // Clear the assignment directory on the very first run
  if cycle = 1 and period = Args.Periods[1] then do
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
  UpdateProgressBar(Args.period + ": Run Highway Assignment", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period

  // Set options for the OUE macro call
  opts = null
  opts.period = period
  opts.hwy_dbd = Args.hwy_dbd
  opts.cycle = Args.Iteration
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

Macro "Log Cycle RMSE" (rmse, prmse, Args)
  UpdateProgressBar(Args.period + ": Log Cycle RMSE", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  cycle = Args.Iteration
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

/*

*/

Macro  "Feedback" (Args)
  // Simple check based on a set number of iterations
  // if you want to check skim/flow %RMSE, use Args.hwy_prmse and Args.skim_prmse by period
  if Args.Iteration >= Args.MaxIterations 
    then return(1) // converged
    else do
      Args.Iteration = Args.Iteration + 1
      return(2) // not converged
    end
EndMacro