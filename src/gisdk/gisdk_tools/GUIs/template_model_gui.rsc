/*
All code below this comment is from the NRV model GUI. It provides a few
powerful features that make it worth copying for other modeling projects.
*/

/*
This script contains the primary dialog box and control macros that run the
model.  Individual model components that peroform calculations are stored
in separate script files.  In addition, general utility scripts are stored in
the "src/lib" directory.

Passing information between dialog boxes and macros is handled using the
global MODELARGS variable. MODELARGS is established/modified entirely
in this main script.  In all other scripts, it is simply referenced
- not modified.  For example, many macros use Args.period to determine
which time of day (e.g. "AM") they are operating in.
*/

/*
This macro runs a single scenario to convergence.

Returns
  congerved
    "True" or "False"
    If the model converged.
*/
Macro "Full Model Run"
  
  MODELARGS.full_feedback = "true"
  RunMacro("Destroy Stopwatches")
  RunMacro("Destroy Progress Bars")
  RunMacro("Close All")
  CreateProgressBar("placeholder", )
  
  // Start of model steps
  RunMacro("Initial Processing")
  RunMacro("Through Trips")
  RunMacro("Generation")
  RunMacro("Time of Day")

  for p = 1 to Args.Periods.length do
    Args.period = Args.Periods[p]

    Args.Iteration = 1
    prmse_skim = null
    prmse_flow = null
    converged = "False"
    while !converged and Args.Iteration <= Args.MaxIterations do
      UpdateProgressBar(
        "Period: " + Args.period + "     " +
        "Cycle: " + String(Args.Iteration) + "     " +
        "Skim RMSE: " + String(prmse_skim) + "%     " +
        "Flow RMSE: " + String(prmse_flow) + "%",
        round(Args.Iteration / Args.MaxIterations * 100, 0)
      )
      CreateProgressBar("placeholder", )

      prmse_skim = RunMacro("Skimming")
      RunMacro("Calc Mode Shares")
      RunMacro("Distribution")
      RunMacro("Apply Mode Shares")
      RunMacro("Directionality")
      prmse_flow = RunMacro("Highway Assignment")

      if prmse_skim < .1 and prmse_flow < .1 and Args.Iteration >= 4
        then converged = "True"
      Args.Iteration = Args.Iteration + 1
      DestroyProgressBar()
    end
  end

  RunMacro("Summaries")
  DestroyProgressBar()
  RunMacro("Close All")
  return(converged)
EndMacro

/*
Model GUI
*/

dBox "Main" location: x, y
  Title: "NRV MPO Travel Model" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  init do
    static x, y
    if x = null then x = -3

    global MODELARGS
    MODELARGS = null
    RunMacro("TCB Init")

    /*Set the model debug paramter
    1: Turn on debug buttons
    0: Turn off debug buttons
    */
    MODELARGS.debug = 0
    if MODELARGS.debug = 1 then ShowItem("debug")

    // Use the ui location to find the master directory
    ui_dbd = GetInterface()
    a_path = SplitPath(ui_dbd)
    ui_dir = a_path[1] + a_path[2]
    ui_dir = RunMacro("Normalize Path", ui_dir)
    if RunMacro("Path has Special Chars", ui_dir) then ShowMessage(
      "Model path includes spaces or other special characters.\n" +
      "Setup in a directory with only 'a-z' and '_' to avoid potential issues."
    )
    Args.[Master Folder] = RunMacro(
      "Normalize Path", ui_dir + "/../../master"
    )
    Args.[Master Links] = Args.[Master Folder] + "/networks/master_network.dbd"
    Args.[Master Routes] = Args.[Master Folder] + "/networks/master_transit.rts"

    // Check to see if the UI needs to be recompiled
    RunMacro("Recompile UI Check", ui_dbd, ui_dir)

    // Initialize other dbox items
    Args.MaxIterations = 20
    git_hub_image = ui_dir + "/../bmp/GitHub-Mark-32px.bmp"
  EndItem

  // Link to GitHub
  button 45, 0 icon: git_hub_image help: "GitHub Link" do
    message = "(If repository is private, you must be a</br>" +
      "collaborator and log in to GitHub to view)<p>"
    message = message + "<a href='https://github.com/pbsag/HickoryNC/wiki' "
    + "target=\"new window\">https://github.com/pbsag/HickoryNC/wiki</a>"

    Opts = null
    Opts.title = "GitHub Wiki and Repo"
    Opts.message = message
    RunDbox("confirm dbox with browser", Opts)
  EndItem

  // Quit Button
  button 1, 28, 10 Prompt:"Quit" do
    Return(1)
  EndItem

  // Debug Button
  button "debug" after, same, 10 Prompt:"Debug" Hidden do
    Throw("Debug button pressed")
  EndItem

  // Version info
  text 20, after variable: "Model Developed for TC V8 Build 22085"






  Tab List 0, 2, 52, 25 Variable: tab
  Tab Prompt: "Single Scenario"

  // Scenario directory text and button
  text 1, 0 variable: "Scenario Directory"
  text same, after, 40 variable: scen_dir framed
  button after, same, 6 Prompt: "..." do

    on escape goto nodir
    init_dir = RunMacro("Normalize Path", ui_dir + "/../../scenarios")
    scen_dir = ChooseDirectory(
      "Choose a Scenario Directory",
      {{"Initial Directory", init_dir}}
    )
    if RunMacro("Path has Special Chars", scen_dir) then do
      ShowMessage(
        "Scenario path includes spaces or other special characters.\n" +
        "Use only 'a-z' and '_' to avoid potential issues."
      )
      scen_dir = null
      goto nodir
    end
    RunMacro("Init MODELARGS", scen_dir)
    ok = RunDbox("Scenario Settings")
    if !ok then scen_dir = null
      // re-run init to capture any changes to scenario settings
      else RunMacro("Init MODELARGS", scen_dir)

    nodir:
    on error, notfound, escape default
  EndItem

  // Scenario creation
  button 1, 3, 20 Prompt:"Create Scenario" do
    CreateProgressBar("placeholder", )
    RunMacro("Create Scenario")
    DestroyProgressBar()
    ShowMessage("Done with 'Create Scenario'")
  EndItem

  // Full model run button and max cycle selection
  text 28, 5 variable: "Model with Feedback"
  button 26, 7, 20 Prompt:"Full Model Run" do
    CreateStopwatch("run_time")
    converged = RunMacro("Full Model Run")
    time = round(CheckStopwatch("run_time") / 3600, 2)
    DestroyStopwatch("run_time")
    converged_string = if converged
      then "Model converged successfully\n"
      else "Model did not converge before hitting max iterations\n"
    ShowMessage(
      "Full Model Run Complete\n" +
      converged_string +
      "Run Time: " + String(time) + " hours"
    )
  EndItem
  Popdown Menu 36, after, 6 Prompt: "Max Cycles"
    List:{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20}
    Editable Variable: Args.MaxIterations

  // Fixed OD run button
  text 28, 11 variable: "Fixed OD Run"
  button 41, 11, 3 Prompt: " ? " do
    ShowMessage(
      "A common task during application is to\n" +
      "slightly modify the network of an\n" +
      "existing scenario and then run assignment\n" +
      "using the same assignment trip tables.\n" +
      "\n" +
      "This macro automates that process.\n" +
      "Modify the input highway network and press\n" +
      "the 'Fixed OD Run' button."
      )
  EndItem
  button 26, 12.5, 20 Prompt: "Fixed OD Run" do
    RunMacro("Fixed OD Run")
    ShowMessage("Fixed OD Run Complete")
  EndItem

  // Individual model step buttons
  text 6, 5 variable: "Single Steps"

  button 1, 7, 20 Prompt:"Initial Processing" do
    RunMacro("Initial Processing")
    ShowMessage("Done with 'Initial Processing'")
  EndItem

  button same, after, 20 Prompt:"Through Trips" do
    RunMacro("Through Trips")
    ShowMessage("Done with 'Through Trips'")
  EndItem

  button same, after, 20 Prompt:"Generation" do
    RunMacro("Generation")
    ShowMessage("Done with 'Generation'")
  EndItem

  button same, after, 20 Prompt:"Time of Day" do
    RunMacro("Time of Day")
    ShowMessage("Done with 'Time of Day'")
  EndItem

  button same, after, 20 Prompt:"Skimming" do
    RunMacro("Skimming")
    ShowMessage("Done with 'Skimming'")
  EndItem

  button same, after, 20 Prompt:"Calc Mode Shares" do
    RunMacro("Calc Mode Shares")
    ShowMessage("Done with 'Calc Mode Shares'")
  EndItem

  button same, after, 20 Prompt:"Distribution" do
    RunMacro("Distribution")
    ShowMessage("Done with 'Distribution'")
  EndItem

  button same, after, 20 Prompt:"Apply Mode Shares" do
    RunMacro("Apply Mode Shares")
    ShowMessage("Done with 'Apply Mode Shares'")
  EndItem

  button same, after, 20 Prompt:"Directionality" do
    RunMacro("Directionality")
    ShowMessage("Done with 'Directionality'")
  EndItem

  button same, after, 20 Prompt:"Highway Assignment" do
    RunMacro("Highway Assignment")
    ShowMessage("Done with 'Highway Assignment'")
  EndItem

  button same, after, 20 Prompt:"Summaries" do
    RunMacro("Summaries")
    ShowMessage("Done with 'Summaries'")
  EndItem




  Tab Prompt: "Multiple Scenarios"

  // Scenario directory text and button
  text 0, 1 variable: "Choose Multiple Scenario Directories    "
  button after, same, 6 Prompt: "..." do
    on escape goto nodir
    init_dir = RunMacro("Normalize Path", ui_dir + "/../../scenarios")
    scen_dir = ChooseDirectory(
      "Choose a Scenario Directory",
      {{"Initial Directory", init_dir}}
      )

    // Make sure that the scenario has already been created
    // If not, offer to create it.
    test = GetDirectoryInfo(scen_dir + "/inputs/taz/*", "File")
    scen_created = if test = null then "false" else "true"
    if !scen_created then do
      opts = null
      opts.Buttons = "YesNo"
      opts.Caption = "Note"
      str = "This scenario needs to be created.\n" +
        "Create now?"
      yesno = MessageBox(str, opts)

      if yesno = "Yes" then do
        RunMacro("Init MODELARGS", scen_dir)
        scen_defined = RunDbox("Scenario Settings")
        if scen_defined then do
          CreateProgressBar("placeholder", )
          RunMacro("Create Scenario")
          DestroyProgressBar()
        end
      end
    end

    if scen_created or scen_defined then a_scen_list = a_scen_list + {scen_dir}

    nodir:
    on escape default
  EndItem

  Scroll List 0, 3, 50, 5 List: a_scen_list Variable: sl
  Menu: {
    {
      {"Title", "Remove Scenario"},
      {"Macro", "Remove Scenario"}
    }
  }

  Macro "Remove Scenario" do
    a_scen_list = ExcludeArrayElements(a_scen_list, sl, 1)
  EndItem

  // Run scenarios button and iteration selection
  button 1, 9, 20 Prompt:"Run Scenarios" do
    if a_scen_list.length > 0 then RunMacro("Wrapper", a_scen_list)
    else ShowMessage("No scenarios selected.")
  EndItem
  Popdown Menu 11, after, 6 Prompt: "Max Cycles"
    List:{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20}
    Editable Variable: Args.MaxIterations





  Tab Prompt: "Utilities"

  button 1, 1, 15 Prompt:"Clear Workspace" do
    RunMacro("Close All")
    RunMacro("Destroy Progress Bars")
    RunMacro("Destroy Stopwatches")
    ShowMessage("Workspace Cleared")
  EndItem
  
  button same, after, 15 Prompt: "Calibrate MC" do
    if Args.[Scenario Folder] = null then ShowMessage("Choose a model scenario")
    else RunDbox("MC Calibration")
  EndItem
EndDbox

/*
- Checks to make sure HighwayProjectList.csv is present
- Reads ScenarioSettings.csv if present
- Asks for information about the scenario
- Writes info to ScenarioSettings.csv
*/

dBox "Scenario Settings" location: x, y Title: "Scenario Settings"

  init do
    static x, y
    if MODELARGS.debug = 1 then ShowItem("debug")

    // Check to see if ScenarioSettings.csv and HighwayProjectList.csv exist
    settings_file = Args.[Scenario Folder] + "/ScenarioSettings.csv"
    if GetFileInfo(settings_file) then settings = "True" else settings = "False"
    proj_list_file = Args.[Scenario Folder] + "/HighwayProjectList.csv"
    if GetFileInfo(proj_list_file) then proj_list = "True" else proj_list = "False"

    // If the project list exists, read IDs (for display only).
    // Otherwise, create it.
    if proj_list then do
      csv_tbl = OpenTable("tbl", "CSV", {proj_list_file, })
      v_projIDs = GetDataVector(csv_tbl + "|", "ProjID", )
      CloseView(csv_tbl)
      DeleteFile(Substitute(proj_list_file, ".csv", ".DCC", ))
    end else do
      file = OpenFile(proj_list_file, "w")
      WriteLine(file, "ProjID")
      CloseFile(file)
    end

    // if the config file exists, read it into Settings array
    // Create a backup Settings array to check for changes.
    // If config file doesn't exist, toggle writing out to file
    write_settings = "False"
    if settings then do
      Settings = RunMacro("Read Parameter File", settings_file)
      v_description = RunMacro("Read Parameter File", settings_file, , , "True")
      Backup = CopyArray(Settings)
      // create a string of the ext_awdt_year for display
      string.ext_awdt_year = String(Settings.ext_awdt_year)
    end else do
      write_settings = "True"
      dim a_description[2]
    end
  EndItem

  // External AWDT Year
  text 1, 1 variable: "Ext AWDT Year"
  Edit Text 20, same, 40 variable: string.ext_awdt_year do

    Settings.ext_awdt_year = Value(string.ext_awdt_year)
    if Settings.ext_awdt_year <> Backup.ext_awdt_year then do
      write_settings = "True"
      a_description[1] = "Determines AWDT to use at external stations"
    end

    quit:
  EndItem
  button 67, same, 3 Prompt: " ? " do
    ShowMessage("Determines AWDT to use at external stations")
  EndItem

  // SE Data
  text 1, 3 variable: "SE Data File"
  text 20, same, 40 variable: RunMacro(
    "TCU trim filename", Settings.master_se, 40) framed
  button after, same, 4 Prompt: "..." do
    on escape goto no_se
    file = ChooseFile(
      {{"Binary File", "*.bin"}},
      "Choose the SE bin file",
      {{"Initial Directory", Args.[Master Folder] + "\\sedata"}}
    )

    // Extract just the file name and extension from the full path and prefix it
    // with the model's master sedata folder. This ensures that this step will
    // work when passing settings files between machines where the model is in a
    // different directory.
    a_path = SplitPath(file)
    Settings.master_se = a_path[3] + a_path[4]

    if Settings.master_se <> Backup.master_se then do
      write_settings = "True"
      a_description[2] = "Name of se bin file in master sedata folder to use"
    end

    no_se:
    on escape default
  EndItem
  button 67, same, 3 Prompt: " ? " do
    ShowMessage("Name of se bin file in master sedata folder to use")
  EndItem

  // List of project IDs
  text 73, 0 variable: "Project List"
  button 84, same, 3 Prompt: " ? " do
    message = "Shows contents of the HighwayProjectList.csv.</br>" +
      "For more help, see the wiki:<p>"
    message = message + "<a href='https://github.com/pbsag/gisdk_tools/wiki/Highway-Manager#highwayprojectlistcsv' "
    + "target=\"new window\">https://github.com/pbsag/gisdk_tools/wiki/Highway-Manager#highwayprojectlistcsv</a>"

    Opts = null
    Opts.title = "Highway Project Management"
    Opts.message = message
    RunDbox("confirm dbox with browser", Opts)
  EndItem
  Scroll List 73, after, 15, 6 List: V2A(v_projIDs)

  // Save Button
  button 47, 6, 6 Prompt: "Save" do
    // Check that all settings have values
    ok = "True"
    if Settings.master_se = null then ok = "False"
    if Settings.ext_awdt_year = null then ok = "False"
    if !ok then ShowMessage("Some values are missing")

    // Check that settings are valid
    se_file = Args.[Master Folder] + "/sedata/" + Settings.master_se
    if GetFileInfo(se_file) = null then do
      ok = "False"
      ShowMessage(
        "The master se data file must be located in your master/sedata directory.\n" +
        "Use the browse button to select a valid file."
      )
    end
    ee_year = Value(string.ext_awdt_year)
    if ee_year < 2016 or ee_year > 2045 then do
      ok = "False"
      ShowMessage("Year must be between 2015 and 2045")
    end

    // Write out settings to ScenarioSettings.csv
    if ok and write_settings then do
      settings_file = Args.[Scenario Folder] + "/ScenarioSettings.csv"
      col_names = {"Parameter", "Value", "Description"}
      v_description = A2V(a_description)
      RunMacro(
        "Write Parameter File",
        Settings, settings_file, col_names, v_description
      )
    end

    if ok then Return(ok)
  EndItem

  // Cancel Button
  button after, same Prompt: "Cancel" do
    Return("False")
  EndItem

  // Debug Button
  button "debug" after, same, 10 Prompt:"Debug" Hidden do
    Throw("Debug button pressed")
  EndItem


EndDbox

/*
Macro that executes when "Run Scenarios" button is pressed.
This will call the "Full Model Run" once for each scenario.
*/
Macro "Wrapper" (a_scen_list)

  // This variable tells the model it is running multiple scenarios
  MODELARGS.wrapper = "True"

  CreateProgressBar("Running Scenarios", "False")

  for s = 1 to a_scen_list.length do
    RunMacro("Init MODELARGS", a_scen_list[s])

    pct = round((s - 1) / a_scen_list.length * 100, 0)
    UpdateProgressBar("Running Scenario: " + Args.[Scenario Folder], pct)
    CreateProgressBar("place holder", )
    RunMacro("Full Model Run")
    DestroyProgressBar()
  end

  DestroyProgressBar()
  ShowMessage("Done")
EndMacro

/*
This macro is used each time a new scenario is selected (or run by Wrapper).
Because MODELARGS is gobal, and each step needs to be completely independent,
the variables must be initialized outside of any step.

Input:
MODELARGS   Global options array that may have any number of scenario-specific
            info.

Output:
MODELARGS   Global options array that has been set to the current scenario.
*/

Macro "Init MODELARGS" (scen_dir)

  // Reset MODELARGS, but Preserve important info from GUI
  // using a backup opts array
  Backup.debug = MODELARGS.debug
  Backup.master_dir = Args.[Master Folder]
  Backup.master_hwy = Args.[Master Links]
  Backup.master_rts = Args.[Master Routes]
  Backup.max_cycles = Args.MaxIterations
  Backup.wrapper = MODELARGS.wrapper
  MODELARGS = null
  for i = 1 to Backup.length do
    MODELARGS.(Backup[i][1]) = Backup[i][2]
  end
  Args.Iteration = 1

  // Use the master period capacity factor file to establish TOD periods
  param_file = Args.[Master Folder] +
    "\\networks\\period_capacity_factors.csv"
  pf_factors = RunMacro("Read Parameter File", param_file)
  Args.Periods = null
  for p = 1 to pf_factors.length do
    Args.Periods = Args.Periods + {pf_factors[p][1]}
  end
  pf_factors = null

  // Add scenario-specific info
  Args.[Scenario Folder] = scen_dir
  Args.hwy_dbd = scen_dir + "\\outputs\\networks\\ScenarioNetwork.dbd"
  Args.rts_file = scen_dir + "\\outputs\\networks\\ScenarioRoutes.rts"
  Args.taz_dbd = scen_dir + "\\outputs\\taz\\ScenarioTAZ.dbd"
  Args.ee_mtx = scen_dir + "\\outputs\\external\\EETable.mtx"
  Args.se_bin = scen_dir + "\\outputs\\sedata\\ScenarioSE.bin"

  // Load MODELARGS with info from the settings file if it exists
  // and has data.
  settings_file = Args.[Scenario Folder] + "/ScenarioSettings.csv"

  if GetFileInfo(settings_file) <> null then do
    // Check file to make sure it has field names and data
    ok = "True"
    settings_file = Args.[Scenario Folder] + "/ScenarioSettings.csv"

    df = CreateObject("df")
    df.read_csv(settings_file)
    if df.is_empty() then ok = "False"
    if df.tbl.Value.length = 0 then ok = "False"
    if !ok then Throw(
      "The Scenario Settings CSV file exists, but is\n" +
      "missing field names or values.  Delete it to create a new one.\n" +
      settings_file
    )

    Settings = RunMacro("Read Parameter File", settings_file)
    MODELARGS = MODELARGS + Settings
    // Convert the se data file name to a full path
    Args.[Master SE] =  Args.[Master Folder] + "/sedata/" +
      Args.[Master SE]
  end

  RunMacro("Close All")
EndMacro

/*
A common task during application is to slightly modify the network of an
existing scenario and then run assignment using the same assignment trip tables.

This macro automates running the steps after modifying the transport network.
*/

Macro "Fixed OD Run"

  RunMacro("Destroy Progress Bars")
  RunMacro("Close All")
  CreateProgressBar("placeholder", )
  UpdateProgressBar("Fixed OD Run", 0)
  CreateProgressBar("placeholder", )

  // From Initial Processing
  RunMacro("Create Output Copies")
  RunMacro("Determine Area Type")
  RunMacro("Capacity")
  RunMacro("Free-Flow Speed and Alpha")

  Args.Iteration = 1
  for p = 1 to Args.Periods.length do
    Args.period = Args.Periods[p]

    // From Skimming
    RunMacro("Initial Congested Speed")
    RunMacro("Create Net Files")
    // From Highway Assignment
    RunMacro("Highway Assignment")
  end

  // From Summaries
  RunMacro("Create Loaded Network")
  RunMacro("Calculate Daily Fields")
  RunMacro("VOC Maps")
  RunMacro("Create Count Difference Map")
  RunMacro("Run Outviz Assignment Validation")
  
  DestroyProgressBar()
  DestroyProgressBar()
EndMacro
