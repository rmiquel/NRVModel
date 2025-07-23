/*
Time of Day is done by a single macro.  That macro simply sets up the options
for the "Calculate Fields - Simple" macro (ModelUtilities.rsc) and runs it.

Directionality factors are not applied here.
*/

Macro "Time of Day" (Args)
  UpdateProgressBar("Time of Day", 0)
  opts = null
  opts.table = Args.se_bin
  opts.param_file = Args.[Scenario Folder] + "/inputs/tod/time_of_day_factors.csv"
  RunMacro("Calculate Fields - Simple", opts)
  RunMacro("Close All")
  return(1)
EndMacro
