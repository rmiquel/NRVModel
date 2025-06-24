/*

*/

Macro "Transit Assignment" (Args)
  
  RunMacro("Transit Assignment Matrix Creation"), Args)
  RunMacro("Run Transit Assignment"), Args)
EndMacro

/*

*/

Macro "Transit Assignment Matrix Creation" (Args)
  UpdateProgressBar("Transit Assignment Matrix Creation", 0)
  
  scen_dir = Args.[Scenario Folder]
  period = Args.period
  cycle = Args.Iteration

  to_dir = scen_dir + "/outputs/assignment/transit"
  RunMacro("Create Directory", to_dir)

  // Create the assignment matrix
  opts = null
  opts.from_mtx = scen_dir + "/outputs/directionality/pa_person_transit_trips_" +
    period + ".mtx"
  opts.to_mtx = to_dir + "/_transit_assignment_" + period + ".mtx"
  opts.to_mtx_label = "assigned " + period + " PA transit trips"
  opts.equiv_tbl = scen_dir + "/inputs/assignment/transit/transit_assignment_mtx_creation.csv"
  opts.skip_missing = "true"
  RunMacro("Matrix Crosswalk", opts)
  
  if period = "PM" then do
    label = "assigned " + period + " transit trips (transposed to AP)"
    RunMacro("Transpose Matrix", opts.to_mtx, label)
  end
EndMacro

/*

*/

Macro "Run Transit Assignment" (Args)
  UpdateProgressBar("Run Transit Assignment", 0)
  
  scen_dir = Args.[Scenario Folder]
  period = Args.period
  
  opts = null
  opts.period = period
  opts.net_params = scen_dir + "/inputs/networks/transit_net_settings_filtered.csv"
  opts.rts_file = scen_dir + "/outputs/networks/ScenarioRoutes.rts"
  opts.net_dir = scen_dir + "/outputs/networks"
  opts.asn_dir = scen_dir + "/outputs/assignment/transit"
  opts.trip_mtx = opts.asn_dir + "/_transit_assignment_" + period + ".mtx"
  RunMacro("Pathfinder Assignment", opts)
EndMacro
