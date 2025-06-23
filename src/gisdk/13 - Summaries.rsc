/*
This script contains a collection of macros to run after the model
has completed.
*/

Macro "Summaries"
  RunMacro("Write Skim CSVs")
  RunMacro("Summarize Distribution")
  RunMacro("Summarize Mode")
  RunMacro("Create Loaded Network")
  RunMacro("Calculate Daily Fields")
  RunMacro("VOC Maps")
  RunMacro("Create Count Difference Map")
  RunMacro("Summarize by FT and AT")
  RunMacro("Run Outviz Assignment Validation")
  RunMacro("Transit Summary")
EndMacro

/*
These CSV files are read by rmarkdown and used for calibration.
This is done here instead of during skimming to reduce the
number of times it must be done. Only the final skims are written out.
*/

Macro "Write Skim CSVs"
  UpdateProgressBar("Write Skim CSVs", 0)

  a_periods = MODELARGS.periods
  scen_dir = Args.[Scenario Folder]
  output_dir = scen_dir + "/outputs/summary/skim_csvs"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  for p = 1 to a_periods.length do
    period = a_periods[p]

    // Create bin file from skim matrix
    file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
    mtx = OpenMatrix(file, )
    opts = null
    opts.Complete = "True"
    bin_file = scen_dir + "/outputs/skims/highway/skim_" + period + ".bin"
    CreateTableFromMatrix(mtx, bin_file, "FFB", opts)

    // Convert bin to csv (much faster to read in R)
    view = OpenTable("tbl", "FFB", {bin_file})

    csv_file = output_dir + "/skim_" + period + ".csv"
    opts = null
    opts.[CSV Header] = "True"
    ExportView(view + "|", "CSV", csv_file, , opts)
    CloseView(view)
    DeleteFile(bin_file)
    DeleteFile(Substitute(bin_file, ".bin", ".DCB", ))
  end

  RunMacro("Close All")
EndMacro

/*
Creates a table of statistics and writes out
final tables to CSV.
*/

Macro "Summarize Distribution"
  UpdateProgressBar("Summarize Distribution", 0)

  a_periods = MODELARGS.periods
  scen_dir = Args.[Scenario Folder]
  dist_dir = scen_dir + "/outputs/distribution"
  output_dir = scen_dir + "/outputs/summary/distribution_csvs"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Create table of statistics
  for period in a_periods do
    matrices = matrices + {dist_dir + "/_trips_" + period + ".mtx"}
  end
  df = RunMacro("Matrix Stats", matrices)
  df.mutate("matrix", Substitute(df.tbl.matrix, "_trips_", "", ))
  df.rename({"matrix", "core"}, {"period", "purpose"})
  df.write_csv(output_dir + "/trips_stats.csv")

  // Write final matrices to CSV
  for p = 1 to a_periods.length do
    period = a_periods[p]

    // Create bin file from distribution matrix
    file = dist_dir + "/_trips_" + period + ".mtx"
    mtx = OpenMatrix(file, )
    opts = null
    opts.Complete = "True"
    bin_file = output_dir + "/trips_all_" + period + ".bin"
    CreateTableFromMatrix(mtx, bin_file, "FFB", opts)

    // Convert bin to csv (much faster to read in R)
    view = OpenTable("tbl", "FFB", {bin_file})
    csv_file = output_dir + "/trips_all_" + period + ".csv"
    opts = null
    opts.[CSV Header] = "True"
    ExportView(view + "|", "CSV", csv_file, , opts)
    CloseView(view)
    DeleteFile(bin_file)
    DeleteFile(Substitute(bin_file, ".bin", ".DCB", ))
  end

  RunMacro("Close All")
EndMacro

/*

*/

Macro "Summarize Mode"
  UpdateProgressBar("Summarize Mode", 0)

  a_periods = MODELARGS.periods
  scen_dir = Args.[Scenario Folder]
  mode_dir = scen_dir + "/outputs/mode"
  output_dir = scen_dir + "/outputs/summary/mode"
  RunMacro("Create Directory", output_dir)

  // Create table of statistics
  for period in a_periods do
    matrices = matrices + {mode_dir + "/_mc_modal_trips_" + period + ".mtx"}
  end
  df = RunMacro("Matrix Stats", matrices)
  df.mutate("matrix", Substitute(df.tbl.matrix, "_mc_modal_trips_", "", ))
  df.rename({"matrix", "core"}, {"period", "purpose"})
  df.write_csv(output_dir + "/trip_stats.csv")

  RunMacro("Close All")
EndMacro

/*
Depends
  ModelUtilites
    "Perma Join"

  gplyr
*/

Macro "Create Loaded Network"
  UpdateProgressBar("Create Loaded Network", 0)

  a_periods = MODELARGS.periods
  scen_dir = Args.[Scenario Folder]
  hwy_dbd = Args.hwy_dbd
  output_dir = scen_dir + "/outputs/summary/loaded_network"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Copy output network to summary folder
  new_dbd = output_dir + "/LoadedNetwork.dbd"
  CopyDatabase(hwy_dbd, new_dbd)

  // Append flow tables by time period
  for p = 1 to a_periods.length do
    period = a_periods[p]

    fin_cycle = RunMacro("Get Final Cycle Number", period)
    asn_file = scen_dir + "/outputs/assignment/cycle_" + String(fin_cycle) +
      "/LinkFlow_" + period + ".bin"

    // Read the asn file and add time period suffixes to each field
    df = CreateObject("df")
    df.read_bin(asn_file)
    colnames = df.colnames()
    new_names = A2V(colnames) + "_" + period
    opts = null
    opts.new_names = new_names
    df.colnames(opts)

    // Join to loaded network
    temp_csv = output_dir + "/temp.csv"
    df.write_csv(temp_csv)
    RunMacro("Join Table To Layer", new_dbd, "ID", temp_csv, "ID1_" + period)
    DeleteFile(temp_csv)
    DeleteFile(Substitute(temp_csv, ".csv", ".DCC", ))
//    DeleteFile(Substitute(temp_csv, ".csv", ".bx", ))
    DeleteFile(Substitute(temp_csv, ".csv", ".bxu", ))
  end
  RunMacro("Close All")

  // Calculate delay by time period and direction
  {nlyr, llyr} = GetDBLayers(new_dbd)
  llyr = AddLayerToWorkspace(llyr, new_dbd, llyr)
  a_dir = {"AB", "BA"}
  for p = 1 to a_periods.length do
    period = a_periods[p]

    for d = 1 to a_dir.length do
      dir = a_dir[d]

      // Add delay field
      delay_field = dir + "_Delay_" + period
      a_fields = {
        {delay_field, "Real", 10, 2,,,,"(CongTime - FFTime) * Flow / 60"}
      }
      RunMacro("Add Fields", llyr, a_fields)

      // Get data vectors
      v_fft = nz(GetDataVector(llyr + "|", "FFTime", ))
      v_ct = nz(GetDataVector(llyr + "|", dir + "_Time_" + period, ))
      v_vol = nz(GetDataVector(llyr + "|", dir + "_Flow_" + period, ))

      // Calculate delay
      v_delay = (v_ct - v_fft) * v_vol / 60
      SetDataVector(llyr + "|", delay_field, v_delay, )
    end
  end

  // Often LOSD is used for V/C maps. Calculate this.
  for p = 1 to a_periods.length do
    period = a_periods[p]

    for d = 1 to a_dir.length do
      dir = a_dir[d]

      field = dir + "_VOC_" + period
      e_field = dir + "_VOCE_" + period
      d_field = dir + "_VOCD_" + period

      // Rename the original field and add a description
      RunMacro("Rename Field", llyr, field, e_field)
      RunMacro("Add Field Description", llyr, e_field, "V/C based on LOS E")

      // Add and calculate the new field (los d)
      a_fields = {{d_field, "Real", 10, 3,,,,"V/C based on LOS D"}}
      RunMacro("Add Fields", llyr, a_fields, )
      v_flow = GetDataVector(llyr + "|", dir + "_FLOW_PCE_" + period, )
      v_cap = GetDataVector(llyr + "|", dir + period + "CapD", )
      v_vc = v_flow / v_cap
      array.(d_field) = v_vc

    end
  end
  SetDataVectors(llyr + "|", array, )


  RunMacro("Close All")
EndMacro

/*
This macro summarize fields across time period and direction.

The loaded network table will have a volume field for each class that looks like
"AB_Flow_auto_AM". It will also have fields aggregated across classes that look
like "BA_Flow_PM" and "AB_VMT_MD". Direction (AB/BA) and time period (e.g. AM)
will be looped over. Create an array of the rest of the field names to
summarize. e.g. {"Flow_auto", "Flow", "VMT"}.
*/

Macro "Calculate Daily Fields"
  UpdateProgressBar("Calculate Daily Fields", 0)

  a_periods = MODELARGS.periods
  scen_dir = Args.[Scenario Folder]
  output_dir = scen_dir + "/outputs/summary/loaded_network"
  loaded_dbd = output_dir + "/LoadedNetwork.dbd"
  a_dir = {"AB", "BA"}

  // Add link layer to workspace
  {nlyr, llyr} = GetDBLayers(loaded_dbd)
  llyr = AddLayerToWorkspace(llyr, loaded_dbd, llyr)

  // Determine the names of the assignment classes.
  param_file = scen_dir + "/inputs/assignment/assignment_class_parameters.csv"
  params = RunMacro("Read Parameter File", param_file)
  for i = 1 to params.length do
    a_classes = a_classes + {params[i][1]}
  end

  // Add "Flow_" to the assignment class name.
  a_fields = V2A("Flow_" + A2V(a_classes))

  // Add other fields to be summed
  a_fields = a_fields + {"Flow", "VMT", "VHT", "Delay"}

  // Calculate additive daily fields
  for f = 1 to a_fields.length do
    field = a_fields[f]

    for d = 1 to a_dir.length do
      dir = a_dir[d]

      field_name = dir + "_" + field + "_Daily"
      a_fields2 = {
        {field_name, "Real", 10, 2,,,,"Daily " + dir + " " + field}
      }
      RunMacro("Add Fields", llyr, a_fields2, 0)
      v_final = nz(GetDataVector(llyr + "|", field_name, ))

      for p = 1 to a_periods.length do
        period = a_periods[p]

        per_field = dir + "_" + field + "_" + period
        v_add = GetDataVector(llyr + "|", per_field, )
        v_final = v_final + v_add
      end

      // Set field values
      SetDataVector(llyr + "|", field_name, v_final, )
    end
  end

  // Combine AB/BA into total daily flows commonly used to compare to counts.
  // Flow is done separately from VMT, VHT, and Delay because the flow fields
  // are by assignment class. The others are not.
  a_type = a_classes + {""}
  for t = 1 to a_type.length do
    type = a_type[t]

    if type = "" then do
      field_name = "Flow_Daily"
      ab_field = "AB_Flow_Daily"
      ba_field = "BA_Flow_Daily"
    end else do
      field_name = type + "_" + "Flow_Daily"
      ab_field = "AB_Flow_" + type + "_Daily"
      ba_field = "BA_Flow_" + type + "_Daily"
    end
    a_fields = {{
      field_name, "Real", 10, 2,,,,
      "Daily " + type + " flow in both directions"
    }}
    RunMacro("Add Fields", llyr, a_fields)

    v_ab = nz(GetDataVector(llyr + "|", ab_field, ))
    v_ba = nz(GetDataVector(llyr + "|", ba_field, ))
    v_tot = v_ab + v_ba

    SetDataVector(llyr + "|", field_name, v_tot, )
  end

  // Combine AB/BA daily fields for VMT, VHT, and Delay
  a_type = {"VMT", "VHT", "Delay"}
  for t = 1 to a_type.length do
    type = a_type[t]

    a_fields = {{
      type + "_Daily", "Real", 10, 2,,,,
      "Daily " + type + " in both directions"
    }}
    RunMacro("Add Fields", llyr, a_fields)

    v_ab = nz(GetDataVector(llyr + "|", "AB_" + type + "_Daily", ))
    v_ba = nz(GetDataVector(llyr + "|", "BA_" + type + "_Daily", ))
    v_tot = v_ab + v_ba

    SetDataVector(llyr + "|", type + "_Daily", v_tot, )
  end

  // Calculate non-additive daily fields
  a_fields = {
    {"AB_Speed_Daily", "Real", 10, 2,,,, "Slowest speed throughout day"},
    {"BA_Speed_Daily", "Real", 10, 2,,,, "Slowest speed throughout day"},
    {"AB_Time_Daily", "Real", 10, 2,,,, "Highest time throughout day"},
    {"BA_Time_Daily", "Real", 10, 2,,,, "Highest time throughout day"},
    {"AB_VOCE_Daily", "Real", 10, 2,,,, "Highest LOS E v/c throughout day"},
    {"BA_VOCE_Daily", "Real", 10, 2,,,, "Highest LOS E v/c throughout day"},
    {"AB_VOCD_Daily", "Real", 10, 2,,,, "Highest LOS D v/c throughout day"},
    {"BA_VOCD_Daily", "Real", 10, 2,,,, "Highest LOS D v/c throughout day"}
  }
  RunMacro("TCB Add View Fields", {llyr, a_fields})

  for d = 1 to a_dir.length do
    dir = a_dir[d]

    v_min_speed = GetDataVector(llyr + "|", dir + "_Speed_Daily", )
    v_min_speed = if (v_min_speed = null) then 9999 else v_min_speed
    v_max_time = GetDataVector(llyr + "|", dir + "_Time_Daily", )
    v_max_time = if (v_max_time = null) then 0 else v_max_time
    // LOS E v/c
    v_max_voce = nz(GetDataVector(llyr + "|", dir + "_VOCE_Daily", ))
    // LOS D v/c
    v_max_vocd = nz(GetDataVector(llyr + "|", dir + "_VOCD_Daily", ))

    for p = 1 to a_periods.length do
      period = a_periods[p]

      v_speed = GetDataVector(llyr + "|", dir + "_Speed_" + period, )
      v_time = GetDataVector(llyr + "|", dir + "_Time_" + period, )
      v_voce = GetDataVector(llyr + "|", dir + "_VOCE_" + period, )
      v_vocd = GetDataVector(llyr + "|", dir + "_VOCD_" + period, )

      v_min_speed = min(v_min_speed, v_speed)
      v_max_time = max(v_max_time, v_time)
      v_max_voce = max(v_max_voce, v_voce)
      v_max_vocd = max(v_max_vocd, v_vocd)
    end

    SetDataVector(llyr + "|", dir + "_Speed_Daily", v_min_speed, )
    SetDataVector(llyr + "|", dir + "_Time_Daily", v_max_time, )
    SetDataVector(llyr + "|", dir + "_VOCE_Daily", v_max_voce, )
    SetDataVector(llyr + "|", dir + "_VOCD_Daily", v_max_vocd, )
  end
EndMacro

/*
Helper macro
Because each period is fed back independently, the number of cycles
can be different.  This macro returns the number of the final
cycle for a given period.

Depends
  gplyr
*/

Macro "Get Final Cycle Number" (period)

  scen_dir = Args.[Scenario Folder]
  rmse_file = scen_dir + "/outputs/assignment/cycle_rmse_" + period + ".csv"
  df = CreateObject("df")
  df.read_csv(rmse_file)
  cycle = VectorStatistic(df.tbl.cycle, "Max", )

  return(cycle)
EndMacro

/*
Creates V/C maps for each time period.
*/

Macro "VOC Maps"
  UpdateProgressBar("VOC Maps", 0)

  a_periods = MODELARGS.periods + {"Daily"}
  scen_dir = Args.[Scenario Folder]
  hwy_dbd = scen_dir + "/outputs/summary/loaded_network/LoadedNetwork.dbd"
  output_dir = scen_dir + "/outputs/summary/maps"
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  for p = 1 to a_periods.length do
    period = a_periods[p]

    mapFile = output_dir + "/voc_" + period + ".map"

    //Create a new, blank map
    {nlyr,llyr} = GetDBLayers(hwy_dbd)
    a_info = GetDBInfo(hwy_dbd)
    maptitle = period + " V/C"
    map = CreateMap(maptitle,{
      {"Scope",a_info[1]},
      {"Auto Project","True"}
    })
    MinimizeWindow(GetWindowName())

    //Add highway layer to the map
    llyr = AddLayer(map,llyr,hwy_dbd,llyr)
    RunMacro("G30 new layer default settings", llyr)
    SetArrowheads(llyr + "|", "None")
    SetLayer(llyr)

    // Dualized Scaled Symbol Theme (from Caliper Support - not in Help)
  	flds = {llyr+".AB_Flow_" + period}
  	opts = null
  	opts.Title = period + " Flow"
  	opts.[Data Source] = "All"
  	opts.[Minimum Size] = 1
  	opts.[Maximum Size] = 10
  	theme_name = CreateContinuousTheme("Flows", flds, opts)
    // Set color to white to make it disappear in legend
    dual_colors = {ColorRGB(65535,65535,65535)}
    // without black outlines
  	/*dual_linestyles = {LineStyle({{{1, -1, 0}}})}  */
    // with black outlines
    dual_linestyles = {LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})}
  	// dual_labels = {"AB/BA " + period + " VOL"}
  	dual_linesizes = {0}
  	SetThemeLineStyles(theme_name , dual_linestyles)
  	//SetThemeClassLabels(theme_name , dual_labels)
  	SetThemeLineColors(theme_name , dual_colors)
  	SetThemeLineWidths(theme_name , dual_linesizes)
  	ShowTheme(, theme_name)

    // Apply color theme based on the V/C
    num_classes = 4
    theme_title = if period = "Daily"
      then "Max V/C (LOS D)"
      else period + " V/C (LOS D)"
    cTheme = CreateTheme(
      theme_title, llyr+".AB_VOCD_" + period, "Manual",
      num_classes,
      {
        {"Values",{
          {0.0,"True",0.6,"False"},
          {0.6,"True",0.75,"False"},
          {0.75,"True",0.9,"False"},
          {0.9,"True",100,"False"}
          }},
        {"Other", "False"}
      }
    )

    line_colors =	{
      ColorRGB(10794, 52428, 17733),
      ColorRGB(63736, 63736, 3084),
      ColorRGB(65535, 32896, 0),
      ColorRGB(65535, 0, 0)
    }
    dualline = LineStyle({{{2, -1, 0},{0,0,1},{0,0,-1}}})

    for i = 1 to num_classes do
        class_id = llyr +"|" + cTheme + "|" + String(i)
        SetLineStyle(class_id, dualline)
        SetLineColor(class_id, line_colors[i])
        SetLineWidth(class_id, 2)
    end

    // Change the labels of the classes for legend
    labels = {
      "Congestion Free (VC < .6)",
      "Moderate Traffic (VC .60 to .75)",
      "Heavy Traffic (VC .75 to .90)",
      "Stop and Go (VC > .90)"
    }
    SetThemeClassLabels(cTheme, labels)
    ShowTheme(,cTheme)

    // Hide centroid connectors
    SetLayer(llyr)
    ccquery = "Select * where HCMType = 'CC'"
    n1 = SelectByQuery ("CCs", "Several", ccquery,)
    if n1 > 0 then SetDisplayStatus(llyr + "|CCs", "Invisible")

    // Configure Legend
    SetLegendDisplayStatus(llyr + "|", "False")
    RunMacro("G30 create legend", "Theme")
    subtitle = if period = "Daily"
      then "Daily Flow + Max V/C"
      else period + " Period"
    SetLegendSettings (
      GetMap(),
      {
        "Automatic",
        {0, 1, 0, 0, 1, 4, 0},
        {1, 1, 1},
        {"Arial|Bold|16", "Arial|9", "Arial|Bold|16", "Arial|12"},
        {"", subtitle}
      }
    )
    str1 = "XXXXXXXX"
    solid = FillStyle({str1, str1, str1, str1, str1, str1, str1, str1})
    SetLegendOptions (GetMap(), {{"Background Style", solid}})

    // Refresh Map Window
    RedrawMap(map)

    // Save map
    RestoreWindow(GetWindowName())
    SaveMap(map, mapFile)
    CloseMap(map)
  end

  RunMacro("Close All")
EndMacro

/*

*/

Macro "Create Count Difference Map"
  UpdateProgressBar("Count Difference Map", 0)

  // Create total count diff map
  scen_dir = Args.[Scenario Folder]
  macro_opts = null
  macro_opts.output_file = scen_dir +
    "/outputs/summary/maps/Count Difference - Total.map"
  macro_opts.hwy_dbd = scen_dir +
    "/outputs/summary/loaded_network/LoadedNetwork.dbd"
  macro_opts.count_id_field = "CountID"
  macro_opts.count_field = "DailyCount"
  macro_opts.vol_field = "Flow_Daily"
  macro_opts.field_suffix = "All"
  macro_opts.combine_oneway_pairs = "false"
  RunMacro("Count Difference Map", macro_opts)

  // Create SUT count diff map
  scen_dir = Args.[Scenario Folder]
  macro_opts = null
  macro_opts.output_file = scen_dir +
    "/outputs/summary/maps/Count Difference - SUT.map"
  macro_opts.hwy_dbd = scen_dir +
    "/outputs/summary/loaded_network/LoadedNetwork.dbd"
  macro_opts.count_id_field = "CountID"
  macro_opts.count_field = "SUTCount"
  macro_opts.vol_field = "SUT_Flow_Daily"
  macro_opts.field_suffix = "SUT"
  macro_opts.combine_oneway_pairs = "false"
  RunMacro("Count Difference Map", macro_opts)

  // Create MUT count diff map
  scen_dir = Args.[Scenario Folder]
  macro_opts = null
  macro_opts.output_file = scen_dir +
    "/outputs/summary/maps/Count Difference - MUT.map"
  macro_opts.hwy_dbd = scen_dir +
    "/outputs/summary/loaded_network/LoadedNetwork.dbd"
  macro_opts.count_id_field = "CountID"
  macro_opts.count_field = "MUTCount"
  macro_opts.vol_field = "MUT_Flow_Daily"
  macro_opts.field_suffix = "MUT"
  macro_opts.combine_oneway_pairs = "false"
  RunMacro("Count Difference Map", macro_opts)

  RunMacro("Close All")
EndMacro

/*
Uses a gisdk_tools library function to summarize highway stats like
VMT and VHT.
*/

Macro "Summarize by FT and AT"
  UpdateProgressBar("Summarize by FT and AT", 0)

  scen_dir = Args.[Scenario Folder]
  opts.hwy_dbd = scen_dir + "/outputs/summary/loaded_network/LoadedNetwork.dbd"
  opts.output_dir = scen_dir + "/outputs/summary"
  RunMacro("Link Summary by FT and AT", opts)

  RunMacro("Close All")
EndMacro

/*
Sets up project-specific options before calling the gisdk_tools
macro "Outviz Assignment Validation"
*/

Macro "Run Outviz Assignment Validation"
  UpdateProgressBar("Outviz Assignment Validation", 0)

  scen_dir = Args.[Scenario Folder]
  model_dir = RunMacro("Normalize Path", scen_dir + "/../..")
  opts = null
  opts.rscriptexe = model_dir + "/src/R/R-3.5.0/bin/Rscript.exe"
  opts.rmd = model_dir + "/src/gisdk/Assignment_Validation.Rmd"
  opts.pandoc_dir = model_dir + "/src/gisdk/gisdk_tools/pandoc"
  opts.output_dir = scen_dir + "/outputs/summary"
  opts.hwy_dbd = scen_dir + "/outputs/summary/loaded_network/LoadedNetwork.dbd"
  RunMacro("Outviz Assignment Validation", opts)
EndMacro

/*
Summarizes transit assignment.
*/

Macro "Transit Summary"
  UpdateProgressBar("Transit Summary", 0)
  
  scen_dir = Args.[Scenario Folder]
  opts = null
  opts.transit_asn_dir = scen_dir + "/outputs/assignment/transit"
  opts.output_dir = scen_dir + "/outputs/summary/transit_tables"
  opts.loaded_network = scen_dir + "/outputs/summary/loaded_network/LoadedNetwork.dbd"
  RunMacro("Summarize Transit", opts)
EndMacro
