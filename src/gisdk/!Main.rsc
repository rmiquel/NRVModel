/*
This script contains the primary dialog box and control macros that run the
model.  Individual model components that peroform calculations are stored
in separate script files.  In addition, general utility scripts are stored in
the "src/lib" directory.

Passing information between dialog boxes and macros is handled using the
global MODELARGS variable. MODELARGS is established/modified entirely
in this main script.  In all other scripts, it is simply referenced
- not modified.  For example, many macros use MODELARGS.period to determine
which time of day (e.g. "AM") they are operating in.
*/

/*
This macro runs a single scenario to convergence.

Inputs
  * start_cycle
    * Numeric
    * Which cycle of the model to start on. Mainly used during development for
      debugging.
    * Defaults to 1.

Returns
  * congerved
    * "True" or "False"
    * If the model converged.
*/
Macro "Run Full Model" (start_cycle)
  if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
  
  RunMacro("Destroy Progress Bars")
  RunMacro("Close All")
  CreateProgressBar("", )
  
  if start_cycle = null then start_cycle = 1
  
  // Start of model steps
  if start_cycle = 1 then do
    RunMacro("Initial Processing")
    RunMacro("Through Trips")
    RunMacro("Generation")
    RunMacro("Time of Day")
  end

  for p = 1 to MODELARGS.periods.length do
    MODELARGS.period = MODELARGS.periods[p]

    MODELARGS.cycle = start_cycle
    prmse_skim = null
    prmse_flow = null
    converged = "False"
    while !converged and MODELARGS.cycle <= MODELARGS.max_cycles do
      UpdateProgressBar(
        "Period: " + MODELARGS.period + "     " +
        "Cycle: " + String(MODELARGS.cycle) + "     " +
        "Skim RMSE: " + String(prmse_skim) + "%     " +
        "Flow RMSE: " + String(prmse_flow) + "%",
        round(MODELARGS.cycle / MODELARGS.max_cycles * 100, 0)
      )
      CreateProgressBar("", )

      prmse_skim = RunMacro("Skimming")
      RunMacro("Calc Mode Shares")
      RunMacro("Distribution")
      RunMacro("Apply Mode Shares")
      RunMacro("Directionality")
      prmse_flow = RunMacro("Highway Assignment")

      if prmse_skim < .1 and prmse_flow < .1 and MODELARGS.cycle >= 4
        then converged = "True"
      MODELARGS.cycle = MODELARGS.cycle + 1
      DestroyProgressBar()
    end
    
    CreateProgressBar("", )
    RunMacro("Transit Assignment")
    DestroyProgressBar()
  end

  RunMacro("Summaries")
  DestroyProgressBar()
  RunMacro("Close All")
  return(converged)
EndMacro

/*
Model GUI

There is an aknowledged bug in TransCAD dboxes regarding the loading of library
UIs. In short, you have to load it for each button/item that uses the library.
When fixed, you can just use SetLibrary() in the `init do` item.
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

    // Check software version and build number
    target_product = "TransCAD"
    target_version = 10.0 //8.0
    target_build = 40640 //22180
    // reg = RunMacro("Get Registration Info")
    {, product, , build, version} = GetProgram()
    if product <> target_product or version <> target_version or
      build <> target_build then ShowMessage(
        "Warning: " + target_product + " V " + String(target_version) + 
        " build " + String(target_build) + " required.\n" + 
        "This is " + product + " V " + String(version) + " build " + String(build)
      )


    // Use the ui location to find the master directory and load gisdk_tools
    // if the compiled UI exists.
    ui_dbd = GetInterface()
    a_path = SplitPath(ui_dbd)
    ui_dir = a_path[1] + a_path[2]
    gt_ui = ui_dir + "gisdk_tools\\gisdk_tools.dbd"
    if GetFileInfo(gt_ui) <> null then do
      MODELARGS.gt_ui = gt_ui
      SetLibrary(gt_ui)
    end
    ui_dir = RunMacro("Normalize Path", ui_dir)
    if RunMacro("Path has Special Chars", ui_dir) then ShowMessage(
      "Model path includes spaces or other special characters.\n" +
      "Setup in a directory with only 'a-z' and '_' to avoid potential issues."
    )
    MODELARGS.master_dir = RunMacro(
      "Normalize Path", ui_dir + "/../../master"
    )
    MODELARGS.master_hwy = MODELARGS.master_dir + "/networks/master_network.dbd"
    MODELARGS.master_rts = MODELARGS.master_dir + "/networks/master_transit.rts"

    // Check to see if the UI needs to be recompiled
    RunMacro("Recompile UI Check", ui_dbd, ui_dir)

    // Initialize other dbox items
    MODELARGS.max_cycles = 5
    git_hub_image = ui_dir + "/../bmp/GitHub-Mark-32px.bmp"
  EndItem

  // Link to GitHub
  button 45, .75 icon: git_hub_image help: "GitHub Link" do
    message = "(If repository is private, you must be a</br>" +
      "collaborator and log in to GitHub to view)<p>"
    message = message + "<a href='https://github.com/pbsag/nrv-model' "
    + "target=\"new window\">https://github.com/pbsag/nrv-model</a>"

    Opts = null
    Opts.title = "GitHub Wiki and Repo"
    Opts.message = message
    RunDbox("confirm dbox with browser", Opts)
  EndItem

  // Quit Button
  button 1, 30, 10 Prompt:"Quit" do
    Return(1)
  EndItem

  // Debug Button
  button "debug" after, same, 10 Prompt:"Debug" Hidden do
    Throw("Debug button pressed")
  EndItem

  // Version info
  text 17, after variable: "Model Developed for TC V8 Build " + build






  Tab List 0, 2, 52, 27 Variable: tab
  Tab Prompt: "Single Scenario"

  // Scenario directory text and button
  text 1, 0 variable: "Scenario Directory"
  text same, after, 40 variable: scen_dir framed
  button after, same, 6 Prompt: "..."  Default do
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)

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
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
    CreateProgressBar("", )
    RunMacro("Create Scenario")
    DestroyProgressBar()
    ShowMessage("Done with 'Create Scenario'")
  EndItem

  // Run full model button and max cycle selection
  text 28, 5 variable: "Model with Feedback"
  button 26, 7, 20 Prompt:"Run Full Model" do
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
    if MODELARGS.scen_dir = null then do
      ShowMessage("Select a scenario folder")
    end else do
      CreateStopwatch("run_time")
      converged = RunMacro("Run Full Model")
      time = round(CheckStopwatch("run_time") / 3600, 2)
      DestroyStopwatch("run_time")
      converged_string = if converged
        then "Model converged successfully\n"
        else "Model did not converge before hitting max iterations\n"
      ShowMessage(
        "'Run Full Model' Complete\n" +
        converged_string +
        "Run Time: " + String(time) + " hours"
      )
    end
  EndItem
  Popdown Menu 36, after, 6 Prompt: "Max Cycles"
    List:{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20}
    Editable Variable: MODELARGS.max_cycles do
      if TypeOf(MODELARGS.max_cycles) = "string" 
        then MODELARGS.max_cycles = S2I(MODELARGS.max_cycles)
    EndItem

  // Fixed OD run button
  text 28, 11 variable: "Fixed OD Run"
  button 41, 11, 3 Prompt: " ? " do
    ShowMessage(
      "A common task during application is to\n" +
      "slightly modify the network of an\n" +
      "existing scenario and then run assignment\n" +
      "using the same assignment trip tables.\n" +
      "This macro automates that process.\n" +
      "\n" +
      "1. Copy a prevoiusly-run scenario.\n" +
      "2. Modify the input highway network.\n" +
      "3. Point the GUI to that scenario.\n" + 
      "4. Press the 'Fixed OD Run' button."
      )
  EndItem
  button 26, 12.5, 20 Prompt: "Fixed OD Run" do
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
    if MODELARGS.scen_dir = null then do
      ShowMessage("Select a scenario folder")
    end else do
      RunMacro("Fixed OD Run")
      ShowMessage("Fixed OD Run Complete")
    end
  EndItem

  // Individual model step buttons
  text 6, 5 variable: "Single Steps"

  button 1, 7, 20 Prompt:"Initial Processing" do
    status = RunMacro("Run Single Step", {step_name: "Initial Processing"})
    if status != "failed" then ShowMessage("Done with 'Initial Processing'")
  EndItem

  button same, after, 20 Prompt:"Through Trips" do
    status = RunMacro("Run Single Step", {step_name: "Through Trips"})
    if status != "failed" then ShowMessage("Done with 'Through Trips'")
  EndItem

  button same, after, 20 Prompt:"Generation" do
    status = RunMacro("Run Single Step", {step_name: "Generation"})
    if status != "failed" then ShowMessage("Done with 'Generation'")
  EndItem

  button same, after, 20 Prompt:"Time of Day" do
    status = RunMacro("Run Single Step", {step_name: "Time of Day"})
    if status != "failed" then ShowMessage("Done with 'Time of Day'")
  EndItem

  button same, after, 20 Prompt:"Skimming" do
    status = RunMacro(
      "Run Single Step", {step_name: "Skimming", period_loop: "true"})
    if status != "failed" then ShowMessage("Done with 'Skimming'")
  EndItem

  button same, after, 20 Prompt:"Calc Mode Shares" do
    status = RunMacro(
      "Run Single Step", {step_name: "Calc Mode Shares", period_loop: "true"})
    if status != "failed" then ShowMessage("Done with 'Calc Mode Shares'")
  EndItem

  button same, after, 20 Prompt:"Distribution" do
    status = RunMacro(
      "Run Single Step", {step_name: "Distribution", period_loop: "true"})
    if status != "failed" then ShowMessage("Done with 'Distribution'")
  EndItem

  button same, after, 20 Prompt:"Apply Mode Shares" do
    status = RunMacro(
      "Run Single Step", {step_name: "Apply Mode Shares", period_loop: "true"})
    if status != "failed" then ShowMessage("Done with 'Apply Mode Shares'")
  EndItem

  button same, after, 20 Prompt:"Directionality" do
    status = RunMacro(
      "Run Single Step", {step_name: "Directionality", period_loop: "true"})
    if status != "failed" then ShowMessage("Done with 'Directionality'")
  EndItem

  button same, after, 20 Prompt:"Highway Assignment" do
    status = RunMacro(
      "Run Single Step", {step_name: "Highway Assignment", period_loop: "true"})
    if status != "failed" then ShowMessage("Done with 'Highway Assignment'")
  EndItem

  button same, after, 20 Prompt:"Transit Assignment" do
    status = RunMacro(
      "Run Single Step", {step_name: "Transit Assignment", period_loop: "true"})
    if status != "failed" then ShowMessage("Done with 'Transit Assignment'")
  EndItem

  button same, after, 20 Prompt:"Summaries" do
    status = RunMacro("Run Single Step", {step_name: "Summaries"})
    if status != "failed" then ShowMessage("Done with 'Summaries'")
  EndItem




  Tab Prompt: "Multiple Scenarios"

  // Scenario directory text and button
  text 0, 1 variable: "Choose Multiple Scenario Directories    "
  button after, same, 6 Prompt: "..." do
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
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
          CreateProgressBar("", )
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
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
    if a_scen_list.length > 0 then RunMacro("Wrapper", a_scen_list)
    else ShowMessage("No scenarios selected.")
  EndItem
  Popdown Menu 11, after, 6 Prompt: "Max Cycles"
    List:{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20}
    Editable Variable: MODELARGS.max_cycles





  Tab Prompt: "Utilities"

  button 1, 1, 15 Prompt:"Clear Workspace" do
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
    RunMacro("Close All")
    RunMacro("Destroy Progress Bars")
    RunMacro("Destroy Stopwatches")
    ShowMessage("Workspace Cleared")
  EndItem
  
  button same, after, 15 Prompt: "Calibrate MC" do
    if MODELARGS.scen_dir = null 
      then ShowMessage("Choose a model scenario to use for calibration.")
    else RunDbox("MC Calibration")
  EndItem
  
  button same, after, 15 Prompt: "Create Release" do
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
    opts = null
    opts.Buttons = "YesNo"
    opts.Default = 2
    yesno = MessageBox(
      "For developer use only:\n" +
      "This creates a zip file that accompanies GitHub releases.\n\n" +
      "Are you sure you want to create a release?\n" + 
      "It takes a while.", 
      opts
    )
    if yesno = "Yes" then do
      RunMacro("Create Release", "false")
      ShowMessage("Release Created")
    end
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
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)

    // Check to see if ScenarioSettings.csv and project list csvs are present
    settings_file = MODELARGS.scen_dir + "/ScenarioSettings.csv"
    if GetFileInfo(settings_file) then settings = "True" else settings = "False"
    hwy_list_file = MODELARGS.scen_dir + "/HighwayProjectList.csv"
    if GetFileInfo(hwy_list_file) then hwy_list = "True" else hwy_list = "False"
    trn_list_file = MODELARGS.scen_dir + "/TransitProjectList.csv"
    if GetFileInfo(trn_list_file) then trn_list = "True" else trn_list = "False"

    // If the project lists exist, read IDs (for display only).
    // Otherwise, create them.
    if hwy_list then do
      df = CreateObject("df", hwy_list_file)
      v_projIDs = df.tbl.ProjID
    end else do
      file = OpenFile(hwy_list_file, "w")
      WriteLine(file, "ProjID")
      CloseFile(file)
    end
    if trn_list then do
      df = CreateObject("df", trn_list_file)
      v_transitIDs = df.tbl.ProjID
    end else do
      file = OpenFile(trn_list_file, "w")
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
      {{"Initial Directory", MODELARGS.master_dir + "\\sedata"}}
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

  // List of highway project IDs
  text 73, 0 variable: "Highway Projects"
  button 90, same, 3 Prompt: " ? " do
    message = "Shows contents of the HighwayProjectList.csv.</br>" +
      "For more help, see the wiki:<p>"
    message = message + "<a href='https://github.com/wsp-sag/gisdk_tools_wiki/wiki/Highway-Manager#highwayprojectlistcsv' "
    + "target=\"new window\">https://github.com/wsp-sag/gisdk_tools_wiki/wiki/Highway-Manager#highwayprojectlistcsv</a>"

    Opts = null
    Opts.title = "Highway Project Management"
    Opts.message = message
    RunDbox("confirm dbox with browser", Opts)
  EndItem
  Scroll List 73, after, 15, 6 List: V2A(v_projIDs)
  
  // List of transit project IDs
  text 95, 0 variable: "Transit Projects"
  button 110, same, 3 Prompt: " ? " do
    message = "Shows contents of the TransitProjectList.csv.</br>" +
      "For more help, see the wiki:<p>"
    message = message + "<a href='https://github.com/wsp-sag/gisdk_tools_wiki/wiki/Transit-Manager#transitprojectlistcsv' "
    + "target=\"new window\">https://github.com/wsp-sag/gisdk_tools_wiki/wiki/Transit-Manager#transitprojectlistcsv</a>"

    Opts = null
    Opts.title = "Transit Project Management"
    Opts.message = message
    RunDbox("confirm dbox with browser", Opts)
  EndItem
  Scroll List 95, after, 15, 6 List: V2A(v_transitIDs)

  // Save Button
  button 47, 6, 6 Prompt: "Save" Default do
    if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
    
    // Check that all settings have values
    ok = "True"
    if Settings.master_se = null then ok = "False"
    if Settings.ext_awdt_year = null then ok = "False"
    if !ok then ShowMessage("Some values are missing")

    // Check that settings are valid
    se_file = MODELARGS.master_dir + "/sedata/" + Settings.master_se
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
      ShowMessage("Year must be between 2016 and 2045")
    end

    // Write out settings to ScenarioSettings.csv
    if ok and write_settings then do
      settings_file = MODELARGS.scen_dir + "/ScenarioSettings.csv"
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
This will call the "Run Full Model" once for each scenario.
*/
Macro "Wrapper" (a_scen_list)
  if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)

  // This variable tells the model it is running multiple scenarios
  MODELARGS.wrapper = "True"

  CreateProgressBar("Running Scenarios", "False")

  for s = 1 to a_scen_list.length do
    RunMacro("Init MODELARGS", a_scen_list[s])

    pct = round((s - 1) / a_scen_list.length * 100, 0)
    UpdateProgressBar("Running Scenario: " + MODELARGS.scen_dir, pct)
    CreateProgressBar("", )
    RunMacro("Run Full Model")
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
  if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)

  // Reset MODELARGS, but Preserve important info from GUI
  // using a backup opts array
  Backup.debug = MODELARGS.debug
  Backup.master_dir = MODELARGS.master_dir
  Backup.master_hwy = MODELARGS.master_hwy
  Backup.master_rts = MODELARGS.master_rts
  Backup.max_cycles = MODELARGS.max_cycles
  Backup.wrapper = MODELARGS.wrapper
  Backup.gt_ui = MODELARGS.gt_ui
  MODELARGS = null
  for i = 1 to Backup.length do
    MODELARGS.(Backup[i][1]) = Backup[i][2]
  end
  MODELARGS.cycle = 1

  // Use the master period capacity factor file to establish TOD periods
  param_file = MODELARGS.master_dir +
    "\\networks\\period_capacity_factors.csv"
  pf_factors = RunMacro("Read Parameter File", param_file)
  MODELARGS.periods = null
  for p = 1 to pf_factors.length do
    MODELARGS.periods = MODELARGS.periods + {pf_factors[p][1]}
  end
  pf_factors = null

  // Add scenario-specific info
  MODELARGS.scen_dir = scen_dir
  MODELARGS.hwy_dbd = scen_dir + "\\outputs\\networks\\ScenarioNetwork.dbd"
  MODELARGS.rts_file = scen_dir + "\\outputs\\networks\\ScenarioRoutes.rts"
  MODELARGS.taz_dbd = scen_dir + "\\outputs\\taz\\ScenarioTAZ.dbd"
  MODELARGS.ee_mtx = scen_dir + "\\outputs\\external\\EETable.mtx"
  MODELARGS.se_bin = scen_dir + "\\outputs\\sedata\\ScenarioSE.bin"

  // Load MODELARGS with info from the settings file if it exists
  // and has data.
  settings_file = MODELARGS.scen_dir + "/ScenarioSettings.csv"

  if GetFileInfo(settings_file) <> null then do
    // Check file to make sure it has field names and data
    ok = "True"
    settings_file = MODELARGS.scen_dir + "/ScenarioSettings.csv"

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
    MODELARGS.master_se =  MODELARGS.master_dir + "/sedata/" +
      MODELARGS.master_se
  end

  RunMacro("Close All")
EndMacro

/*
A common task during application is to slightly modify the network of an
existing scenario and then run assignment using the same assignment trip tables.

This macro automates running the steps after modifying the transport network.
*/

Macro "Fixed OD Run"
  if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)

  RunMacro("Destroy Progress Bars")
  RunMacro("Close All")
  CreateProgressBar("", )
  UpdateProgressBar("Fixed OD Run", 0)
  CreateProgressBar("", )

  // From Initial Processing
  RunMacro("Create Output Copies")
  RunMacro("Determine Area Type")
  RunMacro("Capacity")
  RunMacro("Set CC Speeds")
  RunMacro("Other Attributes")

  MODELARGS.cycle = 1
  for p = 1 to MODELARGS.periods.length do
    MODELARGS.period = MODELARGS.periods[p]

    // From Skimming
    RunMacro("Initial Congested Speed")
    RunMacro("Create Highway Net Files")
    
    RunMacro("Highway Assignment")
  end

  // From Summaries
  RunMacro("Create Loaded Network")
  RunMacro("Calculate Daily Fields")
  RunMacro("VOC Maps")
  RunMacro("Create Count Difference Map")
  RunMacro("Summarize by FT and AT")
  RunMacro("Run Outviz Assignment Validation")
  
  DestroyProgressBar()
  DestroyProgressBar()
EndMacro

/*
The primary purpose of this macro is to generalize access to the individual, 
primary model steps. This is what the single-step buttons on the GUI call, but
this can also be called by other programs (like MC calibration) to run model
steps as if the user was clicking GUI buttons.

Inputs (all in a named array)
  * step_name
    * String
    * Macro name to execute
  * period_loop
    * True/False
    * If the single step should be repeated by period.

Returns
  * If `period_loop = 'true'` then nothing is returned.
  * If 'false', then anything returned by the macro `step_name` will be 
    returned.
      
*/

Macro "Run Single Step" (MacroOpts)
  if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
  
  step_name = MacroOpts.step_name
  period_loop = MacroOpts.period_loop
  
  if step_name = null then ShowMessage("'step_name' not provided")
  else if MODELARGS.scen_dir = null then ShowMessage("Select a scenario folder.")
  else do
    MODELARGS.cycle = 1
    if period_loop then do
      for period in MODELARGS.periods do
        MODELARGS.period = period
        CreateProgressBar(period, )
        CreateProgressBar("", )
        RunMacro(step_name)
        DestroyProgressBar()
        DestroyProgressBar()
      end
    end else do
      CreateProgressBar("", )
      result = RunMacro(step_name)
      DestroyProgressBar()
    end
    return(result)
  end
  
  return("failed")
EndMacro

/*
The development version of the model (what you get when you clone the repo) is
not the easiest to setup. This macro creates a simplified directory that will
run 'out of the box'. Rename the zip output file and attach it to the GitHub 
official release.

Inputs
  * remove_gt_source
    * True/False
    * Whether to remove the GT source code in the client release
    * Defaults to false
    * If the source code is removed, GT is compiled into a separate UI during
      release creation.

Output
Creates a zip file that contains everything needed to run the model.
*/

Macro "Create Release" (remove_gt_source)
  if MODELARGS.gt_ui <> null then SetLibrary(MODELARGS.gt_ui)
  CreateProgressBar("", )
  UpdateProgressBar("Creating a Release", 0)

  master_dir = MODELARGS.master_dir
  model_dir = RunMacro("Normalize Path", master_dir + "/..")
  release_dir = RunMacro("Normalize Path", model_dir + "/../client_release")
  from_gisdk_dir = model_dir + "/src/gisdk"
  to_gisdk_dir = release_dir + "/src/gisdk"
  to_gt_dir = to_gisdk_dir + "/gisdk_tools"
  from_scen_dir = model_dir + "/scenarios"
  to_scen_dir = release_dir + "/scenarios"
  
  RunMacro("Create Directory", release_dir)
  
  // Copy major directories and base scenario recipes
  dir_to_copy = {"master", "other", "src"}
  opts = null
  for dir in dir_to_copy do
    opts.from = model_dir + "/" + dir
    opts.to = release_dir + "/" + dir
    RunMacro("Copy Directory", opts)
  end
  CopyFile(model_dir + "/README.md", release_dir + "/README.md")
  scenarios_to_copy = {"Base_2016", "LRTP_2045"}
  for scenario_name in scenarios_to_copy do
    from_scenario = from_scen_dir + "/" + scenario_name
    to_scenario = to_scen_dir + "/" + scenario_name
    RunMacro("Create Directory", to_scen_dir)
    files = {
      "HighwayProjectList.csv", "ScenarioSettings.csv", "TransitProjectList.csv"
    }
    for file in files do
      CopyFile(from_scenario + "/" + file, to_scenario + "/" + file)
    end
  end
 
  // Remove unwanted file extensions from the entire release directory
  exts_to_delete = {"gitignore", "git", "DS_Store"}
  files = RunMacro("Catalog Files", release_dir, exts_to_delete)
  for file in files do
    DeleteFile(file)
  end
  
  if remove_gt_source then do
    // Compile GT to a separate UI. This also runs docstrings
    // and updates the GT lst file to make sure it is current.
    RunMacro("Compile GT", to_gt_dir, to_gisdk_dir + "/gisdk_tools.dbd")
    RunMacro("Delete Directory", to_gt_dir + "/docstring_results")
    
    // Remove gt lines from the model's lst file before compiling it. This
    // ensures the model must use gisdk_tools.dbd properly.
    from_lst_file = from_gisdk_dir + "/!Compile This.lst"
    to_lst_file = to_gisdk_dir + "/!Compile This.lst"
    from = OpenFile(from_lst_file, "r")
    to = OpenFile(to_lst_file, "w")
    while !FileAtEOF(from) do
      line = ReadLine(from)
      if Position(line, "gisdk_tools") = 0 then WriteLine(to, line)
    end
    CloseFile(from)
    CloseFile(to)
    lst = to_lst_file
    ui = to_gisdk_dir + "/ui.dbd"
    RunMacro("Compile LST to UI", lst, ui)
  
    // Remove files from the GT directory
    exts_to_delete = {"rsc", "lst"}
    files = RunMacro("Catalog Files", to_gt_dir, exts_to_delete)
    for file in files do
      DeleteFile(file)
    end
  end
  
  RunMacro("Zip Directory", release_dir)
  DestroyProgressBar()
EndMacro
