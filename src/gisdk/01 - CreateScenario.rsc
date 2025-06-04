/*
This rsc file controls the initial setup of a scenario.

Macro "Create Scenario" is the main control macro, which calls all other
macros in this script.
*/

Macro "Create Scenario"

  // Check if anything has already been created in the scenario directory
  dir = MODELARGS.scen_dir + "/inputs/*"
  if GetDirectoryInfo(dir, "All") <> null then do
    opts = null
    opts.Buttons = "YesNo"
    opts.Caption = "Note"
    str = "The input folder already contains information.\n" +
      "Continuing will overwrite any manual changes made.\n" +
      "The output folder will not be modified.\n" +
      "Are you sure you want to continue?"
    yesno = MessageBox(str, opts)
  end

  if yesno = "Yes" or yesno = null then do
    RunMacro("Create Folder Structure")
    RunMacro("Copy TAZ")
    RunMacro("Create Scenario SE")
    RunMacro("Create Scenario Highway")
    RunMacro("Create Scenario Transit")
  end
EndMacro

/*
- Creates input and output folders needed in the scenario directory
*/

Macro "Create Folder Structure"
  UpdateProgressBar("Create Folder Structure", 0)

  // copy the master directory structure to the scenario input directory
  opts = null
  opts.from = MODELARGS.master_dir
  opts.to = MODELARGS.scen_dir + "/inputs"
  opts.copy_files = "true"
  RunMacro("Copy Directory", opts)

  // Array of output directories to create
  a_dir = {
    "/outputs/taz",
    "/outputs/sedata",
    "/outputs/networks",
    "/outputs/skims",
    "/outputs/external",
    "/outputs/generation",
    "/outputs/distribution",
    "/outputs/mode",
    "/outputs/directionality",
    "/outputs/assignment",
    "/outputs/assignment/transit",
    "/outputs/summary",
  }

  for d = 1 to a_dir.length do
    dir = MODELARGS.scen_dir + a_dir[d]

    RunMacro("Create Directory", dir)
  end

  RunMacro("Close All")
EndMacro

/*
- copies the master TAZ layer into the scenario
- standardizes name
*/

Macro "Copy TAZ"
  UpdateProgressBar("Copy TAZ", 0)

  // Remove any dbd files in the taz directory
  dir = MODELARGS.scen_dir + "/inputs/taz"
  a_dbds = RunMacro("Catalog Files", dir, "dbd")
  for i = 1 to a_dbds.length do
    DeleteDatabase(a_dbds[i])
  end

  // Create the TAZ file
  taz_dir = MODELARGS.master_dir + "\\taz"
  a_files = GetDirectoryInfo(taz_dir + "/*.dbd", "File")
  if a_files.length > 1 then Throw(
    "There are multiple DBD files in the master TAZ folder.\n" +
    "Leave only the official TAZ layer of the model."
  )
  CopyDatabase(
    taz_dir + "\\" + a_files[1][1],
    MODELARGS.scen_dir + "\\inputs\\taz\\ScenarioTAZ.dbd"
  )

EndMacro

/*
- creates the scenario SE data
- standardizes name
*/

Macro "Create Scenario SE"
  UpdateProgressBar("Create Scenario SE", 0)

  // Remove any bin or dcb files in the directory
  dir = MODELARGS.scen_dir + "/inputs/sedata"
  a_dbds = RunMacro("Catalog Files", dir, {"bin", "dcb"})
  for i = 1 to a_dbds.length do
    DeleteFile(a_dbds[i])
  end

  // Make sure folder exists before exporting
  dir = MODELARGS.scen_dir + "/inputs/sedata"
  if GetDirectoryInfo(dir, "All") = null then CreateDirectory(dir)

  // Export se data into the scenario folder
  master_se = OpenTable("master_se", "FFB", {MODELARGS.master_se})
  scen_se = MODELARGS.scen_dir + "/inputs/sedata/ScenarioSE.bin"
  if GetFileInfo(scen_se) <> null then DeleteTableFiles("FFB", scen_se, )
  ExportView(
    master_se + "|",
    "FFB",
    scen_se,,
  )
  CloseView(master_se)

  // Add field to differentiate internal from external zones
  se_tbl = OpenTable(
    "se", "FFB", {MODELARGS.scen_dir + "/inputs/sedata/ScenarioSE.bin"}
  )
  a_fields = {{"InternalZone", "Character", 10,}}
  RunMacro("TCB Add View Fields", {se_tbl, a_fields})
  v_id = GetDataVector(se_tbl + "|", "ID", )
  v_type = if (nz(v_id) <> null) then "Internal"
  SetDataVector(se_tbl + "|", "InternalZone", v_type, )

  // Add records for external stations
  {nlyr, llyr} = GetDBLayers(MODELARGS.master_hwy)
  nlyr = AddLayerToWorkspace(nlyr, MODELARGS.master_hwy, nlyr)
  SetLayer(nlyr)
  SelectByQuery("ext", "Several", "Select * where External = 1")
  v_ext_ids = GetDataVector(nlyr + "|ext", "TAZ", )
  v_ext_ids = SortVector(v_ext_ids)
  opts = null
  opts.[empty records] = v_ext_ids.length
  AddRecords(se_tbl, , , opts)
  SetView(se_tbl)
  SelectByQuery("ext", "Several", "Select * where Households = null")
  SetDataVector(se_tbl + "|ext", "ID", v_ext_ids, )

  // Set InternalZone field to "External" for the new zones
  v_type = if (nz(v_ext_ids) <> null) then "External"
  SetDataVector(se_tbl + "|ext", "InternalZone", v_type, )

  RunMacro("Close All")
EndMacro

/*
- copies the master network into the scenario directory
- standardizes name
- uses the GT highway project manager
*/

Macro "Create Scenario Highway"
  UpdateProgressBar("Create Scenario Highway", 0)

  // Remove any dbd files in the directory
  dir = MODELARGS.scen_dir + "/inputs/networks"
  a_dbds = RunMacro("Catalog Files", dir, "dbd")
  for i = 1 to a_dbds.length do
    DeleteDatabase(a_dbds[i])
  end

  // Copy the master highway network into the scenario folder
  scen_hwy = MODELARGS.scen_dir + "/inputs/networks/ScenarioNetwork.dbd"
  if GetFileInfo(scen_hwy) <> null then DeleteFile(scen_hwy)
  CopyDatabase(MODELARGS.master_hwy, scen_hwy)

  // Update the network using gisdk_tools
  opts = null
  opts.hwy_dbd = scen_hwy
  opts.proj_list = MODELARGS.scen_dir + "/HighwayProjectList.csv"
  opts.master_dbd = MODELARGS.master_hwy
  RunMacro("Highway Project Management", opts)

  RunMacro("Close All")
EndMacro

/*
- copies the master network into the scenario directory
- standardizes name
- uses the GT transit project manager
*/

Macro "Create Scenario Transit"
  UpdateProgressBar("Create Scenario Transit", 0)

  // Remove any RTS files in the directory
  scen_rts = MODELARGS.scen_dir + "/inputs/networks/ScenarioRoutes.dbd"
  if GetFileInfo(scen_rts) <> null then DeleteRouteSystem(scen_rts)

  // Create scenario RTS using gisdk_tools
  scen_dir = MODELARGS.scen_dir
  opts = null
  opts.master_rts = MODELARGS.master_rts
  opts.scen_hwy = MODELARGS.scen_dir + "/inputs/networks/ScenarioNetwork.dbd"
  opts.proj_list = scen_dir + "/TransitProjectList.csv"
  opts.centroid_qry = "TAZ <> null"
  RunMacro("Transit Project Management", opts)

  // Check that no centroids are marked for PNR. This will cause
  // transit skimming to crash.
  opts = null
  opts.file = MODELARGS.scen_dir + "/inputs/networks/ScenarioNetwork.dbd"
  {map, {nlyr, llyr}} = RunMacro("Create Map", opts)
  SetLayer(nlyr)
  qry = "Select * where TAZ <> null and PNR = 1"
  n = SelectByQuery("check", "several", qry)
  if n > 0 then Throw(
    "At least one centroid is marked as a PNR node.\n" +
    "Use the following query to find them: 'TAZ <> null and PNR = 1'"
  )
  CloseMap(map)
EndMacro
