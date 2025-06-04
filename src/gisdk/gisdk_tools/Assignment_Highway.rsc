/*
Generic assignment functions.
Because the assignment options are so complex, a separate
macro is used for each assignment method. For example,
separate macros should be used for OUE and UE. Otherwise,
the options required by a general macro would become
too complicated.
*/

/*dontdoc
*/

Macro "OUE Assignment"
  Throw(
    "TransCAD 8 renamed Origin-Based UE to Path-Based UE.\n" +
    "The macro in GT has been renamed to 'PUE Assignment'."
  )
EndMacro

/*doc
Path-Based User-Equilibrium Assignment.

Inputs (all in a named array)
    * `period`
      * String
      * Name of period. Is used as a suffix for output file names.
    * `hwy_dbd`
      * String
      * Full path to the highway DBD
    * `cycle`
      * Integer
      * Feedback iteration/cycle
    * `asn_dir`
      * String
      * Full path to assignment directory. This folder will contain output
        from every assignment cycle located in a separate folder named "cycle_x".
    * `trip_mtx`
      * String
      * Full path to the matrix of trips to be assigned.
    * `toll_mtx`
      * Optional String
      * Full path to the matrix describing OD-based tolls
    * `net_file`
      * String
      * Full path to the .net file to use for assignment. Importantly, a single
        .net file is used for all classes found in `trip_mtx`. Exclusion queries
        control which links a class can use. As a result, the .net file used
        should include all links that any of the highway classes might use. For
        example, if there are da, sr2, and sr3 .net files, the sr3 network
        should be used.
    * `class_param_file`
      * String
      * Full path to the .csv file that contains the class-specific parameters.
      * This includes things like passenger-car-equivalents (PCEs),
        values of time, and link exclusion queries.
        
      | Class  | Term            | Value                  | Description                            |
      |--------|-----------------|------------------------|----------------------------------------|
      | da     | vot             | 1                      | value of time                          |
      | da     | pce             | 1                      | passenger car equivalent               |
      | da     | pce_field       | None                   | field based pce (if it varies by link) |
      | da     | exclusion_query | HOV > = 2 or Drive = 0 | query to use to exclude links          |
      | da     | toll_field      | n/a                    | field containing toll price of link    |
      | da     | toll_core       |                        | matrix core name for OD-based tolls    |
        
    * `vdf_opts`
      * (Optional) Named Array
      * Contains VDF field info for the conical VDF. Each option has a default value
        for field name. Importantly, these are not necessarily the field names
        in the hwy_dbd. Instead, they are the names in the .net file.
      * `fftime`
        * Free-flow time field.
        * Defaults to "FFTime"
      * `capacity`
        * Capacity on the link
        * Defaults to "Capacity"
      * `alpha`
        * Alpha value to use for the link
        * Defaults to "Alpha"
      * `preload`
        * Preload fields to use
        * Defaults to "None"
*/

Macro "PUE Assignment" (MacroOpts)

  period = MacroOpts.period
  hwy_dbd = RunMacro("Normalize Path", MacroOpts.hwy_dbd)
  cycle = MacroOpts.cycle
  asn_dir = RunMacro("Normalize Path", MacroOpts.asn_dir)
  trip_mtx = RunMacro("Normalize Path", MacroOpts.trip_mtx)
  toll_mtx = RunMacro("Normalize Path", MacroOpts.toll_mtx)
  net_file = RunMacro("Normalize Path", MacroOpts.net_file)
  class_param_file = RunMacro("Normalize Path", MacroOpts.class_param_file)
  vdf_opts = MacroOpts.vdf_opts

  // opts array passed by this macro to TC MMA
  opts = null

  // Set default vdf options if they are missing. These are field names
  // in the .net file.
  if vdf_opts.fftime = null then vdf_opts.fftime = "FFTime"
  if vdf_opts.capacity = null then vdf_opts.capacity = "Capacity"
  if vdf_opts.alpha = null then vdf_opts.alpha = "Alpha"
  if vdf_opts.preload = null then vdf_opts.preload = "None"

  // VDF options
  opts.Global.[VDF DLL] = "emme2.vdf"
  opts.Field.[VDF Fld Names] = {
    vdf_opts.fftime,      // Free flow time
    vdf_opts.capacity,    // Capacity
    vdf_opts.alpha,       // Alpha
    vdf_opts.preload      // Preload
  }
  opts.Global.[VDF Defaults] = {, , 6, 0}

  // Setup the output directory
  output_dir = asn_dir + "\\cycle_" + String(cycle)
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Get hwy_dbd layers
  {nlyr, llyr} = GetDBLayers(hwy_dbd)

  // Create an example trip currency for assignment
  mtx = OpenMatrix(trip_mtx, )
  {ri, ci} = GetMatrixIndex(mtx)
  a_cores = GetMatrixCoreNames(mtx)
  /* trip_cur = CreateMatrixCurrency(mtx, a_cores[1], , , ) */
  opts.Input.[OD Matrix Currency] = {trip_mtx, a_cores[1], ri, ci}

  // Toll matrix currency
  if toll_mtx <> null then do
    mtx = OpenMatrix(toll_mtx, )
    a_cores = GetMatrixCoreNames(mtx)
    toll_cur = CreateMatrixCurrency(mtx, a_cores[1], , , )
    opts.Input.[Toll Matrix Currency] = toll_cur
  end
  mtx = null

  // Input file options
  opts.Input.Database = hwy_dbd
  opts.Input.Network = net_file

  // Warm start options
  if cycle > 1 then do
    opts.Flag.[Do Warm Start] = 1
    prev_dir = asn_dir + "\\cycle_" + String(cycle - 1)
    opts.Input.[Path File] = prev_dir + "/path_" + period + ".obt"
  end

  // Cycle/Feedback options
  opts.Field.[MSA Flow] = "__MSAFlow"    // creates net field "__MSAFlow"
  opts.Field.[MSA Cost] = "__MSATime"    // creates net field "__MSATime"
  opts.Global.[MSA Iteration] = cycle    // Stores current feedback iteration

  // Vehicle class options (set by parameter file)
  params = RunMacro("Read Parameter File", class_param_file)
  opts.Global.[Number of Classes] = params.length
  for c = 1 to params.length do
    class = params[c][1]
    class_params = params.(class)
    
    // Class names
    opts.Field.[Class Names] = opts.Field.[Class Names] + {class}

    // Class PCEs and value of time (VOI = "Value of Impedance" = VOT)
    opts.Global.[Class PCEs] = opts.Global.[Class PCEs] +
      {class_params.pce}
    opts.Field.[PCE Fields] = opts.Field.[PCE Fields] +
      {class_params.pce_field}
    opts.Global.[Class VOIs] = opts.Global.[Class VOIs] +
      {class_params.vot}

    // Class exlusion set (if provided)
    if class_params.exclusion_query <> null then do
      excl_set = {
        hwy_dbd + "|" + llyr,
        llyr,
        class + " exclusion set",
        Runmacro("Normalize Query", class_params.exclusion_query)
      }
      opts.Input.[Exclusion Link Sets] = opts.Input.[Exclusion Link Sets] +
        {excl_set}
    end else opts.Input.[Exclusion Link Sets] = opts.Input.[Exclusion Link Sets] +
      {null}
      
    // Operating cost fields. Caliper recommends not using these, so GT does
    // not support them. "None" is hard-coded for every class.
    opts.Field.[Operating Cost Fields] = opts.Field.[Operating Cost Fields] + 
      {"None"}

    // Turn attributes
    opts.Field.[Turn Attributes] = opts.Field.[Turn Attributes] +
      {class_params.turn_attributes}

    // Class toll info (fixed and OD)
    opts.Field.[Fixed Toll Fields] = opts.Field.[Fixed Toll Fields] +
      {class_params.toll_field}
    // If OD-based tolls are needed, must provide:
    // opts.Input.[Toll Matrix Currency]
    if class_params.toll_core <> null
      and opts.Input.[Toll Matrix Currency] = null
      then Throw(
        "Toll core name provided for the " + class +
        ", but toll_mtx not provided"
      )
    opts.Field.[Class Toll Cores] = opts.Field.[Class Toll Cores] +
      {class_params.toll_core}
  end

  // Load method options
  opts.Global.[Load Method] = "PUE"
  opts.Global.Convergence = .000001
  opts.Global.Iterations = 999
  opts.Global.[Loading Multiplier] = 1
  opts.Global.[Time Minimum] = 0

  // Output file options
  path_file = output_dir + "\\path_" + period + ".obt"
  opts.Output.[Path File] = path_file
  flow_file = output_dir + "\\LinkFlow_" + period + ".bin"
  opts.Output.[Flow Table] = flow_file
  opts.Output.[Flow Matrix].Label = period + " Flow Matrix"
  opts.Output.[Flow Matrix].Compression = 1
  opts.Output.[Flow Matrix].[File Name] = output_dir + "\\Flow_" + period + ".mtx"
  opts.Output.[VOC Matrix].Label = period + " VOC Matrix"
  opts.Output.[VOC Matrix].Compression = 1
  opts.Output.[VOC Matrix].[File Name] = output_dir + "\\voc_" + period + ".mtx"
  opts.Output.[Iteration Log] = output_dir + "\\IterationLog_" + period + ".bin"

  // Run assignment
  ret_value = RunMacro("TCB Run Procedure", "MMA", opts, &Ret)
  if !ret_value then Throw(
    "Assignment failed: " + period + " cycle " + String(cycle)
  )

  // Collect RMSE from previous cycle's last assignment
  // For the first cycle, set them to high values
  if cycle = 1 then do
    rmse = 9999
    prmse = 9999
    max_flow = 9999
  end else do
    rmse = Ret[2].[MSA RMSE]
    max_flow = Ret[2].[Maximum Flow Change]

    vw_flow = OpenTable("flow", "FFB", {flow_file})
    v_ab = GetDataVector(vw_flow + "|", "AB_MSA_Flow", )
    a_avg = VectorStatistic(v_ab, "Mean", )
    v_ba = GetDataVector(vw_flow + "|", "BA_MSA_Flow", )
    b_avg = VectorStatistic(v_ba, "Mean", )
    avg = (a_avg + b_avg) / 2
    prmse = round(rmse / avg * 100, 2)
  end

  return({rmse, prmse})
EndMacro
