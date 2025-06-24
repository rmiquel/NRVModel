/*
This rsc file controls the initial processing steps before skimming.
e.g. Area type calculation, capacity, speeds, etc.

Macro "Initial Processing" is the main control macro, which calls all other
macros in this script.
*/

Macro "Initial Processing" (Args)
  RunMacro("Create Output Copies"), Args)
  RunMacro("Determine Area Type"), Args)
  RunMacro("Capacity"), Args)
  RunMacro("Set CC Speeds"), Args)
  RunMacro("Other Attributes"), Args)
  RunMacro("Filter Transit Settings"), Args)
EndMacro

/*
Creates copies of the scenario/input SE, TAZ, and highway network.
The model will modify the scenario/output copy, leaving
the input files as they were.  This helps when looking back at
older scenarios.
*/

Macro "Create Output Copies" (Args)
  UpdateProgressBar("Create Output Copies", 0)

  input_dir = Args.[Scenario Folder] + "/inputs"

  opts = null
  opts.from_rts = input_dir + "/networks/ScenarioRoutes.rts"
  {drive, folder, filename, ext} = SplitPath(Args.rts_file)
  opts.to_dir = drive + folder
  opts.include_hwy_files = "true"
  RunMacro("Copy RTS Files", opts)
  CopyDatabase(input_dir + "/taz/ScenarioTAZ.dbd", Args.taz_dbd)
  se = OpenTable("se", "FFB", {input_dir + "/sedata/ScenarioSE.bin"})
  ExportView(
    se + "|",
    "FFB",
    Args.se_bin,,
  )
  CloseView(se)
EndMacro


/*
Prepares input options for the AreaType.rsc library of tools, which
tags TAZs and Links with area types.
*/

Macro "Determine Area Type" (Args)
  UpdateProgressBar("Determine Area Type", 0)

  scen_dir = Args.[Scenario Folder]
  taz_dbd = Args.taz_dbd
  se_bin = Args.se_bin
  hwy_dbd = Args.hwy_dbd

  opts = null
  opts.table = se_bin
  opts.param_file = scen_dir + "/inputs/area_type/total_employment.csv"
  RunMacro("Calculate Fields - Simple", opts)

  // Open the area type table and get names and density thresholds
  file = scen_dir + "/inputs/area_type/area_type.csv"
  csv = OpenTable("table", "CSV", {file, })
  opts = null
  opts.[Sort Order] = {{"Density", "Ascending"}}
  v_types = GetDataVector(csv + "|", "AreaType", opts)
  v_thresholds = GetDataVector(csv + "|", "Density", opts)

  // Set options for the "Area Type" library
  opts = null
  opts.taz_dbd = taz_dbd
  opts.se_bin = se_bin
  opts.areaField = "Area"
  opts.hhField = "Households"
  opts.empField = "TotEmp"
  opts.types = V2A(v_types)
  opts.thresholds = V2A(v_thresholds)
  opts.hwy_dbd = hwy_dbd
  RunMacro("Area Type", opts)

  RunMacro("Close All")
EndMacro

/*
Instead of using the hcmr package, this macro uses a lookup table to determine
capacities. It then converts to period capacity based on TOD factors.
*/

Macro "Capacity" (Args)
  UpdateProgressBar("Capacity", 0)

  scen_dir = Args.[Scenario Folder]
  hwy_dbd = Args.hwy_dbd

  // Assign facility type to ramps
  ramp_query = "Select * where HCMType = 'Ramp'"
  fac_field = "HCMType"
  a_ft_priority = {
    "Freeway", "MLHighway", "TLHighway", "PrArterial", "MinArterial",
    "Collector", "Local"
  }
  RunMacro("Assign FT to Ramps", hwy_dbd, ramp_query, fac_field, a_ft_priority)

  // Lookup hourly capacities
  cap_tbl = scen_dir + "/inputs/networks/hourly_capacities.csv"
  cap = CreateObject("df")
  cap.read_csv(cap_tbl)
  hwy_bin = Substitute(hwy_dbd, ".dbd", ".bin", )
  net = CreateObject("df")
  net.read_bin(hwy_bin, {"HCMType", "AreaType"})
  net.left_join(cap, {"HCMType", "AreaType"})
  net.select({"capd_phpl", "cape_phpl"})
  net.update_bin(hwy_bin)

  // Calculate period capacities
  {nlyr, llyr} = GetDBLayers(Args.hwy_dbd)
  llyr = AddLayerToWorkspace(llyr, Args.hwy_dbd, llyr)
  settings_file = Args.[Scenario Folder] +
    "/inputs/networks/period_capacity_factors.csv"
  pf_factors = RunMacro("Read Parameter File", settings_file)

  a_los = {"D", "E"}
  a_dir = {"AB", "BA"}

  for los in a_los do
    for tod in MODELARGS.periods do
      for dir in a_dir do

        field_name = dir + tod + "Cap" + los
        a_fields = {
          {field_name, "Integer", 10,,,,, "hourly los " + los + " capacity per lane"}
        }
        RunMacro("Add Fields", llyr, a_fields)

        v_hourly = GetDataVector(llyr + "|", "cap" + Lower(los) + "_phpl", )
        v_lanes = GetDataVector(llyr + "|", dir + "Lanes", )
        v_period = v_hourly * pf_factors.(tod) * v_lanes
        SetDataVector(llyr + "|", field_name, v_period, )
      end
    end
  end

  RunMacro("Close All")
EndMacro

/*

*/

Macro "Set CC Speeds" (Args)
  UpdateProgressBar("Set CC Speeds", 0)

  hwy_dbd = Args.hwy_dbd
  scen_dir = Args.[Scenario Folder]

  // Add link layer to workspace
  {nlyr, llyr} = GetDBLayers(hwy_dbd)
  llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)

  // Open the area type table
  file = scen_dir + "/inputs/area_type/area_type.csv"
  csv = OpenTable("table", "CSV", {file, })

  // Join based on AreaType
  jv = JoinViews(
    "jv",
    llyr + ".AreaType",
    csv + ".AreaType",
  )

  // Create a selection set of centroid connectors
  SetLayer(llyr)
  qry = "Select * where HCMType = 'CC'"
  n = SelectByQuery("CCs", "Several", qry)

  // Update speeds
  v_speed = GetDataVector(jv + "|CCs", "CCSpeed", )
  SetDataVector(jv + "|CCs", "PostedSpeed", v_speed, )

  RunMacro("Close All")
EndMacro

/*
Determines the free-flow speed/time of links from a lookup table. This speed is
used as a starting point for traffic assignment in each cycle. Walk time and
alpha are also added. Mode is just a column of 1s. It's required by the transit
tnw mode table.
*/

Macro "Other Attributes" (Args)
  UpdateProgressBar("Free-Flow Speed", 0)

  // Add fields to highway DBD
  {nlyr, llyr} = GetDBLayers(Args.hwy_dbd)
  llyr = AddLayerToWorkspace(llyr, Args.hwy_dbd, llyr)
  a_fields = {
              {"FFSpeed", "Integer", 10, , , , , "Free flow travel speed"},
              {"FFTime", "Real", 10, 2, , , , "Free flow travel time"},
              {"Alpha", "Real", 10, 2, , , , "VDF alpha value"},
              {"WalkTime", "Real", 10, 2, , , , "Length / 3 mph"},
              {"Mode", "Real", 10, 2, , , , "Marks all links with a 1 (nontransit mode)"}
            }
  RunMacro("Add Fields", llyr, a_fields, {, , , , 1})

  // Open parameter table
  ffs_file = Args.[Scenario Folder] + "/inputs/networks/ff_speed_alpha.csv"
  ffs_tbl = OpenTable("ffs", "CSV", {ffs_file, })

  // Join based on AreaType and HCMType
  jv = JoinViewsMulti(
    "jv",
    {llyr + ".AreaType", llyr + ".HCMType"},
    {ffs_tbl + ".AreaType", ffs_tbl + ".HCMType"},
    )

  // Perform calculations
  {v_len, v_ps, v_mod, v_alpha} = GetDataVectors(
    jv + "|", {
      llyr + ".Length",
      llyr + ".PostedSpeed",
      ffs_tbl + ".ModifyPosted",
      ffs_tbl + ".Alpha"
      },
    )
  v_ffs = v_ps + v_mod
  v_fft = v_len / v_ffs * 60
  v_wt = v_len / 3 * 60
  SetDataVector(jv + "|", llyr + ".FFSpeed", v_ffs, )
  SetDataVector(jv + "|", llyr + ".FFTime", v_fft, )
  SetDataVector(jv + "|", llyr + ".Alpha", v_alpha, )
  SetDataVector(jv + "|", llyr + ".WalkTime", v_wt, )

  RunMacro("Close All")
EndMacro

/*
Removes network settings from the scenario transit settings file if the
modes required for that network are not present. Uses the results to filter
any other files that need similar treatment.
*/

Macro "Filter Transit Settings" (Args)
  UpdateProgressBar("Filter Transit Settings", 0)

  scen_dir = Args.[Scenario Folder]
  period = MODELARGS.periods[1]
  rts_file = Args.rts_file
  param_dir = scen_dir + "/inputs/networks"

  opts.rts_file = rts_file
  opts.settings_file = param_dir + "/transit_net_settings.csv"
  opts.expr_vars.period = period
  opts.mode_table = param_dir + "/transit_mode_table.csv"
  opts.out_file = param_dir + "/transit_net_settings_filtered.csv"
  RunMacro("GT - Filter Transit Settings", opts)
  
  // Update the transit matrix definition file used in the directionality step
  params = RunMacro("Read Parameter File", opts.out_file)
  for i = 1 to params.length do
    name = ParseString(params[i][1], "_")
    name = name[2]
    if i = 1
      then query = "mode = '" + name + "'" 
      else query = query + " or mode = '" + name + "'"
  end
  csv = scen_dir + "/inputs/directionality/transit_trip_definition.csv"
  df = CreateObject("df", csv)
  df.separate("from_core", {"purp", "seg", "acc", "mode"}, , "true")
  df.filter(query)
  df.select({"to_core", "from_core", "from_factor", "description"})
  df.write_csv(Substitute(csv, ".csv", "_filtered.csv", ))
EndMacro
