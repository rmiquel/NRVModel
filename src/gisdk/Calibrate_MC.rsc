dBox "MC Calibration" location: x, y Title: "MC Calibration" toolbox

  close do
    return()
  enditem

  init do
    static x, y, damp_factor, string_damp_factor, modal_trip_matrices, names, 
      folder, target_file, coeffs_file, string_max_iters, max_iters,
      string_rel_gap, rel_gap, equiv_file, check_calib
    if MODELARGS.debug = 1 then ShowItem("debug")
    if damp_factor = null then do
      damp_factor = .75
      string_damp_factor = "0.75"
    end else string_damp_factor = String(damp_factor)
    if max_iters = null then do
      max_iters = 50
      string_max_iters = "50"
    end else string_max_iters = String(max_iters)
    if rel_gap = null then do
      rel_gap = .1
      string_rel_gap = "0.1"
    end else string_rel_gap = String(rel_gap)
    target_dir = RunMacro("Normalize Path",
      MODELARGS.scen_dir + "/../../docs/data/mode_choice"
    )
  EndItem
  
  button 1, 0, 5 Prompt: "Help" do
    message = "User's Guide not yet available"
    Opts = null
    Opts.title = "Highway Project Management"
    Opts.message = message
    RunDbox("confirm dbox with browser", Opts)
  EndItem
  
  text 1, 2 variable: "Coefficients File"
  text 20, same, 40 variable: RunMacro(
    "TCU trim filename", coeffs_file, 40) framed
  button after, same, 4 Prompt: "..." do
    on escape goto no_coeff
    coeffs_file = ChooseFile(
      {{"CSV File", "*.csv"}}, 
      "Choose the MC Coefficients File", 
      {{"Initial Directory", MODELARGS.scen_dir + "\\inputs\\mode"}}
    )
    no_coeff:
    on escape default
  EndItem
  
  text 1, 4 variable: "Target File"
  text 20, same, 40 variable: RunMacro(
    "TCU trim filename", target_file, 40) framed
  button after, same, 4 Prompt: "..." do
    on escape goto no_target
    target_file = ChooseFile(
      {{"CSV File", "*.csv"}},
      "Choose the MC Targets File",
      {{"Initial Directory", target_dir}}
    )
    no_target:
    on escape default
  EndItem
  
  text 1, 6 variable: "Equivalency File"
  text 20, same, 40 variable: RunMacro(
    "TCU trim filename", equiv_file, 40) framed
  button after, same, 4 Prompt: "..." do
    on escape goto no_equiv
    equiv_file = ChooseFile(
      {{"CSV File", "*.csv"}},
      "Choose the Model/Target Equivalency File",
      {{"Initial Directory", target_dir}}
    )
    no_equiv:
    on escape default
  EndItem  
  
  text 1, 8 variable: "Dampening Factor"
  Edit Text 20, same, 5 variable: string_damp_factor do
    damp_factor = Value(string_damp_factor)
  EndItem
  
  text 28, 8 variable: "Iters"
  Edit Text after, same, 5 variable: string_max_iters do
    max_iters = Value(string_max_iters)
  EndItem
  
  text 40, 8 variable: "Gap"
  Edit Text after, same, 5 variable: string_rel_gap do
    rel_gap = Value(string_rel_gap)
  EndItem
  
  text 69, 0 variable: "Modal Trip Matrices"
  button after, same, 4 Prompt: "..." do
    on escape goto no_trips
    {folder, names} = ChooseFiles(
      {{"Matrix File", "*.mtx"}},
      "Choose the Modal Trip Matrices",
      {{"Initial Directory", MODELARGS.scen_dir + "\\outputs\\mode"}}
    )
    modal_trip_matrices = null
    for name in names do
      modal_trip_matrices = modal_trip_matrices + {folder + name}
    end
    no_trips:
    on escape default
  EndItem
  Scroll List 69, after, 30, 6 List: names
  
  Checkbox 69, 8.5 Prompt: "Check calibration only" Variable: check_calib
  
  button 46, 10, 7 Prompt: "Calibrate" do
    if coeffs_file = null then ShowMessage("Choose a coefficients file")
    else if target_file = null then ShowMessage("Choose a target file")
    else if equiv_file = null then ShowMessage("Choose an equivalency file")
    else if damp_factor = null then ShowMessage("Set a dampening factor")
    else if modal_trip_matrices = null then ShowMessage("Choose modal trip matrices")
    else if max_iters = null then ShowMessage("Set maximum iterations")
    else if rel_gap = null then ShowMessage("Set relative gap")
    else do
      opts = null
      opts.coeffs_file = coeffs_file
      opts.target_file = target_file
      opts.equiv_file = equiv_file
      opts.modal_trip_matrices = modal_trip_matrices
      opts.damp_factor = damp_factor
      opts.max_iters = max_iters
      opts.rel_gap = rel_gap
      opts.model_steps = {
        "Run Single Step",
        "Run Single Step"
      }
      opts.model_step_args = {
        {step_name: "Calc Mode Shares", period_loop: "true"},
        {step_name: "Apply Mode Shares", period_loop: "true"}
      }
      opts.check_calib = check_calib

      if !check_calib 
        then RunMacro("Calibrate MC", opts)
        else RunMacro("Adjust ASCs", opts)
    end
    ShowMessage("Done with Calibration")
  EndItem
  
  button after, same Prompt: "Cancel" do
    return()
  EndItem
  
  button "debug" after, same Prompt: "Debug" hidden do
    Throw("Used the debugger to view variable states")
  EndItem

EndDbox

/*

*/
