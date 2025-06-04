/*


Inputs (all in a named array)
  * `period`
    * String
    * Time of day (e.g. "AM" or "Daily")
  * `net_params`
    * String
    * Path to the network settings csv file
  * `rts_file`
    * String
    * Path to the route system file (.rts)
  * `net_dir`
    * String
    * Path to the directory containing all .tnw files to be assigned
    * File names of net files assumed to be `{net_name}_{period}.tnw`
      * `net_name` must match names found in `net_params`
      * e.g. "w_lb_AM.tnw"
  * `asn_dir`
    * String
    * Path to the transit assignment directory. Outputs will be written here.
  * `trip_mtx`
    * String
    * Path to the matrix to be assigned.
  * `report_access_egress`
    * Optional true/false
    * Defaults to false
    * If true, will report access and egress stop tables. Caution: turning this
      on adds a substantial amount of run time. 
*/

Macro "Pathfinder Assignment" (MacroOpts)
  
  // Argument extraction
  period = MacroOpts.period
  net_params = RunMacro("Normalize Path", MacroOpts.net_params)
  rts_file = RunMacro("Normalize Path", MacroOpts.rts_file)
  net_dir = RunMacro("Normalize Path", MacroOpts.net_dir)
  asn_dir = RunMacro("Normalize Path", MacroOpts.asn_dir)
  trip_mtx = RunMacro("Normalize Path", MacroOpts.trip_mtx)
  report_access_egress = MacroOpts.report_access_egress
  
  // Argument checking
  if period = null then Throw("Pathfinder Assignment: 'period' not provided")
  if net_params = null then Throw("Pathfinder Assignment: 'net_params' not provided")
  if GetFileInfo(net_params) = null then Throw("Pathfinder Assignment: 'net_params' not found")
  if rts_file = null then Throw("Pathfinder Assignment: 'rts_file' not provided")
  if GetFileInfo(rts_file) = null then Throw("Pathfinder Assignment: 'rts_file' not found")
  if net_dir = null then Throw("Pathfinder Assignment: 'net_dir' not provided")
  if asn_dir = null then Throw("Pathfinder Assignment: 'asn_dir' not provided")
  if trip_mtx = null then Throw("Pathfinder Assignment: 'trip_mtx' not provided")
  if GetFileInfo(trip_mtx) = null then Throw("Pathfinder Assignment: 'trip_mtx' not found")
  
  params = RunMacro("Read Parameter File", net_params)
  for p = 1 to params.length do
    net_names = net_names + {params[p][1]}
  end
  
  opts = null
  opts.Input.[Transit RS] = rts_file
  opts.Global.[Load Method] = "PF"
  opts.Global.[OD Layer Type] = "Node"
  opts.Flag.[Do Theme] = 1
  
  for net_name in net_names do
    
    opts.Input.Network = net_dir + "\\" + net_name + "_" + period + ".tnw"
    opts.Input.[OD Matrix Currency] = {trip_mtx, net_name, , }
    opts.Output.[Flow Table] = asn_dir + "\\" + net_name + "_transit_flows_" + period + ".bin"
    opts.Output.[Walk Flow Table] = asn_dir + "\\" + net_name + "_walk_flows_" + period + ".bin"
    opts.Output.[Aggre Table] = asn_dir + "\\" + net_name + "_aggregated_flows_" + period + ".bin"
    opts.Output.[OnOff Table] = asn_dir + "\\" + net_name + "_onoff_" + period + ".bin"
    if report_access_egress then do  
      opts.Output.[Access Stop Table] = asn_dir + "\\" + net_name + "_stop_access_" + period + ".bin"
      opts.Output.[Egress Stop Table] = asn_dir + "\\" + net_name + "_stop_egress_" + period + ".bin"
      nh = ReadNetwork(opts.Input.Network)
      array = GetNetworkInformation(nh)
      if array.[Park and Ride Nodes] > 0 then access_park = "true"
      if array.[Egress Park and Ride Nodes] > 0 then egress_park = "true"
      nh = null
      if access_park
        then opts.Output.[Access Park Table] = asn_dir + "\\" + net_name + 
          "_access_parking_" + period + ".bin"
      if egress_park
        then opts.Output.[Egress Park Table] = asn_dir + "\\" + net_name + 
          "_access_parking_" + period + ".bin"
    end
    
    ok = RunMacro("TCB Run Procedure", "Transit Assignment PF", opts, &Ret)
    
    // collect options for aggregation
    agg.(net_name) = CopyArray(opts)
  end

  // Aggregate the assignment output
  RunMacro("Aggregate Transit Assignment Results", agg, period)
EndMacro

/*dontdoc
Transit assignment creates many output files when run for multiple networks.
This is a helper macro to collapse them together into CSV files.
*/

Macro "Aggregate Transit Assignment Results" (agg, period)

  first_path = agg[1][2]
  first_path = first_path.Output[1][2]
  {drive, folder, name, ext} = SplitPath(first_path)
  output_dir = RunMacro("Normalize Path", drive + folder)
  
  for i = 1 to agg.length do
    net_name = agg[i][1]
    files = agg.(net_name).Output
    
    for f = 1 to files.length do
      file_name = files[f][1]
      file_path = files.(file_name)
      
      temp = CreateObject("df", file_path)
      colnames = temp.colnames()
      temp.mutate("network", net_name)
      temp.mutate("period", period)
      temp.select({"network", "period"} + colnames)
      
      if i = 1 then do
        final.(file_name) = temp.copy()
      end else do
        temp2 = final.(file_name).copy()
        temp2.bind_rows(temp)
        final.(file_name) = temp2.copy()
      end
      
      if i = agg.length then final.(file_name).write_csv(
        output_dir + "/" + Substitute(file_name, " ", "_", ) + "_" + 
        period + ".csv"
      )
    end
  end
EndMacro
