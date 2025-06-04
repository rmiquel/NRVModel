/*
This rsc implements the TransCAD skimming procedure with successive MSA
averaging of flows and travel times.  In addition, because the model is using
PUE assignment, the warmstart option is used to speed up successive feedback
cycles.
(See TransCAD help topic "Feedback Loops in TransCAD".)

Returns
  prmse
  %RMSE between feedback cycle skims or 9999 if first cycle
*/

Macro "Skimming"
    if MODELARGS.cycle = 1 then do
      RunMacro("Initial Congested Speed")
      RunMacro("Create Highway Net Files")
      RunMacro("Create Transit Net Files")
    end else do
      RunMacro("Update Congested Link Times")
    end
    RunMacro("Highway Skims")
    RunMacro("Transit Skims")
    RunMacro("Calculate Additional Skim Cores")
    RunMacro("Create Skim Indices")
    {rmse, prmse} = RunMacro("Calculate Skim RMSE")
    RunMacro("Log Cycle Skim RMSE", rmse, prmse)
    return(prmse)
EndMacro

/*
Using the free-flow speed for the first cycle's skim time requires many
more cycles to reach convergence.  Instead, this macro creates estimated
congested speed for use during the first cycle.

This speed comes from a simple ruleset based on facility type, area type,
and time period.

This macro is here (and not in initial processing) to simplify looping by time
of day. Instead of needing a separate field for each time of day, this field
is simply overwritten when needed. This simplifies references to the field
later.

Depends
  gplyr
*/

Macro "Initial Congested Speed"
  UpdateProgressBar("Initial Congested Speed", 0)

  hwy_dbd = MODELARGS.hwy_dbd
  scen_dir = MODELARGS.scen_dir
  period = MODELARGS.period

  // Add field to highway DBD
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)
  a_fields = {{"InitCongSpeed", "Real", 10,,,,,"Init guess at cong speed"},
              {"InitCongTime", "Real", 10, 2,,,,"Init guess at cong time"}}
  RunMacro("TCB Add View Fields", {llyr, a_fields})

  df1 = CreateObject("df")
  opts = null
  opts.view = llyr
  df1.read_view(opts)
  df1.select({"Length", "PostedSpeed", "AreaType", "HCMType"})

  // Open parameter table, select time period, and join
  cs_file = scen_dir + "/inputs/skimming/initial_congested_speed.csv"
  df2 = CreateObject("df")
  df2.read_csv(cs_file)
  df2.filter("Period = '" + period + "'")
  df1.left_join(df2, {"AreaType", "HCMType"}, {"AreaType", "HCMType"})

  // Calculate congested time and speed
  v_cs = df1.tbl.PostedSpeed + df1.tbl.ModifyPosted
  v_ct = df1.tbl.[Length] / v_cs * 60
  SetDataVector(llyr + "|", "InitCongSpeed", v_cs, )
  SetDataVector(llyr + "|", "InitCongTime", v_ct, )

  RunMacro("Close All")
EndMacro

/*
On the first cycle, this macro creates the initial highway .net files.
Also sets their settings.
*/

Macro "Create Highway Net Files"
  UpdateProgressBar("Create Highway Net Files", 0)

  period = MODELARGS.period
  scen_dir = MODELARGS.scen_dir
  hwy_dbd = MODELARGS.hwy_dbd
  in_dir = scen_dir + "/inputs/networks"

  opts = null
  opts.hwy_dbd = hwy_dbd
  opts.settings_tbl = in_dir + "/highway_net_settings.csv"
  opts.fields_tbl = in_dir + "/highway_net_fields.csv"
  opts.out_dir = scen_dir + "/outputs/networks"
  opts.label = period + " network file"
  opts.period = period
  RunMacro("GT - Create Highway Networks", opts)
EndMacro

/*
On the first cycle, this macro creates the initial transit .tnw files.
Also sets their settings.
*/

Macro "Create Transit Net Files"
  UpdateProgressBar("Create Transit Net Files", 0)

  scen_dir = MODELARGS.scen_dir
  period = MODELARGS.period
  net_dir = scen_dir + "/inputs/networks"

  opts = null
  opts.rts_file = MODELARGS.rts_file
  opts.settings_file = net_dir + "/transit_net_settings_filtered.csv"
  opts.fields_file = net_dir + "/transit_net_fields.csv"
  opts.mode_table = net_dir + "/transit_mode_table.csv"
  opts.period = period
  if period = "PM" then opts.flip_drive_access = "true"
  opts.output_dir = scen_dir + "/outputs/networks"
  RunMacro("GT - Create Transit Networks", opts)
EndMacro

/*
After feedback, the link travel times in the .net and .tnw files need to
be updated.
*/

Macro "Update Congested Link Times"
  
  scen_dir = MODELARGS.scen_dir
  period = MODELARGS.period
  hwy_dbd = MODELARGS.hwy_dbd
  rts_file = MODELARGS.rts_file
  
  // Update highway networks
  opts = null
  opts.net_settings_file = scen_dir + "/inputs/networks/highway_net_settings.csv"
  opts.expr_vars.period = period
  opts.congested_net_file = scen_dir + "/outputs/networks/sr3_" + period + ".net"
  opts.dbd_or_rts = hwy_dbd
  RunMacro("Update MSATime", opts)
  
  // Update transit networks
  opts.net_settings_file = scen_dir + "/inputs/networks/transit_net_settings_filtered.csv"
  opts.dbd_or_rts = rts_file
  RunMacro("Update MSATime", opts)
EndMacro

/*

*/

Macro "Highway Skims"
  UpdateProgressBar("Highway Skims", 0)

  scen_dir = MODELARGS.scen_dir
  period = MODELARGS.period
  cycle = MODELARGS.cycle

  opts.param_file = scen_dir + "/inputs/networks/highway_net_settings.csv"
  opts.expr_vars.period = period
  opts.net_dir = scen_dir + "/outputs/networks"
  opts.output_matrix = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
  opts.clear_output_dir = if cycle = 1 and period = "AM" then "true"
  opts.cycle = cycle
  if cycle = 1
    then opts.field_to_minimize = "InitCongTime"
    else opts.field_to_minimize = "__MSATime"
  opts.period = period
  if period = "PM" then opts.ap_direction = "true"
  RunMacro("GT - Highway Skim", opts)

  // Open matrix and modify cores
  mtx = OpenMatrix(opts.output_matrix, )
  a_corenames = GetMatrixCoreNames(mtx)

  for corename in a_corenames do
    if Position(corename, "InitCongTime") <> 0 then do
      new_name = Substitute(corename, "InitCongTime", "time", )
      SetMatrixCoreName(mtx, corename, new_name)
    end
    if Position(corename, "__MSATime") <> 0 then do
      new_name = Substitute(corename, "__MSATime", "time", )
      SetMatrixCoreName(mtx, corename, new_name)
    end
    if Position(corename, "Length") <> 0 then do
      new_name = Substitute(corename, "Length", "dist", )
      SetMatrixCoreName(mtx, corename, new_name)
    end
  end
  mtx = null
EndMacro

/*

*/

Macro "Transit Skims"
  UpdateProgressBar("Transit Skims", 0)

  scen_dir = MODELARGS.scen_dir
  rts_file = MODELARGS.rts_file
  period = MODELARGS.period
  cycle = MODELARGS.cycle

  opts.rts_file = rts_file
  opts.param_file = scen_dir + "/inputs/networks/transit_net_settings_filtered.csv"
  opts.expr_vars.period = period
  opts.net_dir = scen_dir + "/outputs/networks"
  opts.output_matrix = scen_dir + "/outputs/skims/transit/_trn_skim_" + period + ".mtx"
  opts.clear_output_dir = if cycle = 1 and period = "AM" then "true"
  opts.cycle = cycle
  opts.period = period
  if period = "PM" then opts.ap_direction = "true"
  RunMacro("GT - Transit Skim", opts)
EndMacro

/*
Calculates cores needed for MC and DC.
*/

Macro "Calculate Additional Skim Cores"
  UpdateProgressBar("Calculate Additional Skim Cores", 0)

  period = MODELARGS.period
  scen_dir = MODELARGS.scen_dir

  // Highway skim cores
  opts = null
  opts.mtx_file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
  opts.param_file = scen_dir + "/inputs/skimming/calc_highway_cores.csv"
  RunMacro("Calculate Cores", opts)

  // Get scenario transit network names from the settings file
  net_dir = scen_dir + "/inputs/networks"
  settings_file = net_dir + "/transit_net_settings_filtered.csv"
  settings = RunMacro("Read Parameter File", settings_file)

  for n = 1 to settings.length do
    net_name = settings[n][1]

    opts = null
    opts.mtx_file = scen_dir + "/outputs/skims/transit/_trn_skim_" + period + ".mtx"
    opts.param_file = scen_dir + "/inputs/skimming/calc_transit_cores.csv"
    opts.expr_vars.net = net_name
    RunMacro("Calculate Cores", opts)
  end
EndMacro

/*
Creates any additional indices needed by later model steps. For example,
resident distribution should only see internal zones.
*/

Macro "Create Skim Indices"
  UpdateProgressBar("Create Skim Indices", 0)

  period = MODELARGS.period
  scen_dir = MODELARGS.scen_dir
  se_bin = MODELARGS.se_bin
  hwy_dbd = MODELARGS.hwy_dbd

  // Add node layer to the map
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  AddLayerToWorkspace(nlyr, hwy_dbd, nlyr)
  SetLayer(nlyr)
  qry = "Select * where nz(TAZ) <> 0 and nz(External) = 0"
  n = SelectByQuery("internal", "several", qry)
  if n = 0 then Throw("No internal centroids found for skim index")

  a_mtx_files = {
    scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx",
    scen_dir + "/outputs/skims/transit/_trn_skim_" + period + ".mtx"
  }

  for mtx_file in a_mtx_files do
    mtx = OpenMatrix(mtx_file, )
    {ris, cis} = GetMatrixIndexNames(mtx)
    if ArrayPosition(ris, {"internal"}, ) <> 0
      then DeleteMatrixIndex(mtx, "internal")
    CreateMatrixIndex(
      "internal", mtx, "Both", nlyr + "|internal", "TAZ", "TAZ"
    )
  end
EndMacro

/*
Compares current skim time with previous.

Returns
  prmse
  The relative/percent RMSE
*/

Macro "Calculate Skim RMSE"

  cycle = MODELARGS.cycle
  period = MODELARGS.period
  scen_dir = MODELARGS.scen_dir
  skim_dir = scen_dir + "/outputs/skims/highway"
  prev_dir = skim_dir + "/previous"
  corename = "da_time"

  if cycle = 1 then do
    rmse = 9999
    prmse = 9999
  end else do
    mtx_name = "_hwy_skim_" + period + ".mtx"

    // Previous matrix
    m1_file = prev_dir + "/" + mtx_name
    m1 = OpenMatrix(m1_file, )
    {ri, ci} = GetMatrixIndex(m1)
    c1 = CreateMatrixCurrency(m1, corename, ri, ci, )

    // Current matrix
    m2_file = skim_dir + "/" + mtx_name
    m2 = OpenMatrix(m2_file, )
    {ri, ci} = GetMatrixIndex(m2)
    c2 = CreateMatrixCurrency(m2, corename, ri, ci, )

    stats = MatrixRMSE(c1, c2)
    rmse = round(stats.RMSE, 2)
    prmse = round(stats.RelRMSE, 2)
  end

  return({rmse, prmse})
EndMacro

/*
Logs the RMSE between feedback cycles (assignment back to skimming)

Depends
  gplyr
*/

Macro "Log Cycle Skim RMSE" (rmse, prmse)
  UpdateProgressBar("Log Cycle Skim RMSE", 0)

  scen_dir = MODELARGS.scen_dir
  period = MODELARGS.period
  cycle = MODELARGS.cycle
  log_file = scen_dir + "/outputs/skims/cycle_rmse_" + period + ".csv"

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
