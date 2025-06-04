/*
Generalized highway skim macro. Uses the same parameter file as
"GT - Create Highway Network". Automatically saves previous skims and
computes %RMSEs. Each network listed in the param_file is collapsed
into a single period matrix.

Inputs
  MacroOpts
    Named array containing all macro arguments.

    param_file
      String
      Path to the parameter file.

    expr_vars
      Optional named array
      Supports expressions in the parameter file. See "Normalize Expression" and
      "Read Parameter File" for more details.

    net_dir
      String
      Directory path where all .net files are stored.

    output_matrix
      String
      Name of final matrix containing skims for all networks. This also defines
      the output directory where all skim matrices are stored. This directory is
      cleared if clear_output_dir = "true", so only the outputs of this macro
      should be present there.

    clear_output_dir
      Logical
      Whether or not to clear the output directory of all it's contents.

    cycle
      Number
      Which model feedback cycle is being run. For all but the first cycle,
      %RMSEs are calculated by comparing to the previous cycle.

    field_to_minimize
      String
      Name of field that will be minized by TCs shortest path algorithm.

    period
      String
      Time period (time of day).

    ap_direction
      True/False
      True: the skim will be transposed to represent travel time from attraction
        zone to production zone. This better-approximates travel time in periods
        with heavy AP flow (generally the PM period).
      False (default): the skim isn't transposed.

    intrazonal_neighbors
      Optional integer
      When filling the matrix diagonal for intrazonal time, how many nearest
      neighbors to use. Default is 3. (Passed through to "GT - Fill Skim
      Intrazonals".)

    intrazonal_factor
      Optional real
      When filling the matrix diagonal for intrazonal time, this is the factor
      to apply to the average value of nearest neighbors. Default is .75.
      (Passed through to "GT - Fill Skim Intrazonals".)
*/

Macro "GT - Highway Skim" (MacroOpts)

  // Argument extraction
  param_file = MacroOpts.param_file
  expr_vars = MacroOpts.expr_vars
  net_dir = MacroOpts.net_dir
  output_matrix = MacroOpts.output_matrix
  cycle = MacroOpts.cycle
  field_to_minimize = MacroOpts.field_to_minimize
  clear_output_dir = MacroOpts.clear_output_dir
  period = MacroOpts.period
  ap_direction = MacroOpts.ap_direction
  intrazonal_neighbors = MacroOpts.intrazonal_neighbors
  intrazonal_factor = MacroOpts.intrazonal_factor

  expr_vars.period = period

  {drive, folder, out_file, out_ext} = SplitPath(output_matrix)
  output_dir = RunMacro("Normalize Path", drive + folder)
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Read the settings table
  all_settings = RunMacro("Read Parameter File", param_file, expr_vars)

  // Clear the skim directory if indicated
  if clear_output_dir then RunMacro("Clear Directory", output_dir)

  // After the first feedback cycle, make a copy of the prev skim.
  // It will be used to check for convergence.
  if cycle > 1 then do
    prev_dir = output_dir + "/previous"
    if GetDirectoryInfo(prev_dir, "All") = null then CreateDirectory(prev_dir)

    from = output_matrix
    to = prev_dir + "/" + out_file + out_ext
    CopyFile(from, to)
  end

  for i = 1 to all_settings.length do
    net_name = all_settings[i][1]
    settings = CopyArray(all_settings.(net_name))

    Opts = null
    Opts.Input.Network = net_dir + "/" + settings.out_file
    nh = ReadNetwork(Opts.Input.Network)
    hwy_dbd = GetNetworkDBName(nh)
    {nlyr, llyr} = GetDBLayers(hwy_dbd)
    c_query = RunMacro("Normalize Query", settings.centroid_query)
    Opts.Input.[Origin Set] = {hwy_dbd + "|" + nlyr, nlyr, "Centroids", c_query}
    Opts.Input.[Destination Set] = {hwy_dbd + "|" + nlyr, nlyr, "Centroids"}
    Opts.Input.[Via Set] = {hwy_dbd + "|" + nlyr, nlyr}
    Opts.Field.Minimize = field_to_minimize
    Opts.Field.[Skim Fields].Length = "All"
    Opts.Field.Nodes = nlyr + ".ID"
    Opts.Output.[Output Matrix].Label = net_name + " Skim"
    Opts.Output.[Output Matrix].Compression = 1
    {drive, path, file, ext} = SplitPath(Opts.Input.Network)
    output_mtx = output_dir + "/" + file + ".mtx"
    Opts.Output.[Output Matrix].[File Name] = output_mtx
    ok = RunMacro("TCB Run Procedure", "TCSPMAT", Opts, &Ret)
    if !ok then Throw("Skimming failed for net " + file)
    Ret = null

    result = RunMacro("Check Skim For Disconnected Centroids", output_mtx)
    if !result then Throw(result)

    to_combine = to_combine + {output_mtx}
    prefix = prefix + {net_name + "_"}
  end

  // Combine skim matrices
  opts = null
  opts.matrices = to_combine
  opts.output_matrix = output_matrix
  opts.label = "Highway Skim " + period
  opts.delete_orig = "true"
  opts.core_prefix = prefix
  RunMacro("GT - Combine Matrices", opts)

  // Clear out " (Skim)" from core names
  mtx = OpenMatrix(opts.output_matrix, )
  a_corenames = GetMatrixCoreNames(mtx)
  for name in a_corenames do
    if Position(name, " (Skim)") <> 0
      then do
        new_name = Substitute(name, " (Skim)", "", )
        SetMatrixCoreName(mtx, name, new_name)
      end
  end
  mtx = null

  // Calculate the intrazonal (diagonal) values.
  opts = null
  opts.matrix = output_matrix
  RunMacro("GT - Fill Skim Intrazonals", opts)

  // Check and flip matrix to AP format if specified
  if ap_direction then do
    label = "Highway Skim " + period + " transposed to AP"
    RunMacro("Transpose Matrix", output_matrix, label)
  end
EndMacro

/*
Generalized transit skim macro. Uses the same parameter file as
"GT - Create Transit Network". Automatically saves previous skims and
computes %RMSEs. Each network listed in the param_file is collapsed
into a single period matrix.

Inputs
  MacroOpts
    Named array containing all macro arguments.

    rts_file
      String
      Full path to the route system file (*.rts)

    param_file
      String
      Path to the parameter file.

    expr_vars
      Optional named array
      Supports expressions in the parameter file. See "Normalize Expression" and
      "Read Parameter File" for more details.

    net_dir
      String
      Directory path where all .net files are stored.

    output_matrix
      String
      Name of final matrix containing skims for all networks. This also defines
      the output directory where all skim matrices are stored. This directory is
      cleared if clear_output_dir = "true", so only the outputs of this macro
      should be present there.

    simplify_core_names
      True/False
      If true (the default), the standard TC names will be simplified. Spaces
      removed with underscores, special characters removed, etc. If false, the
      typical TC core names will be left as is.

    clear_output_dir
      Logical
      Whether or not to clear the output directory of all it's contents.

    cycle
      Number
      Which model feedback cycle is being run. For all but the first cycle,
      %RMSEs are calculated by comparing to the previous cycle.

    period
      String
      Time period (time of day).

    ap_direction
      True/False
      True: the skim will be transposed to represent travel time from attraction
        zone to production zone. This better-approximates travel time in periods
        with heavy AP flow (generally the PM period). This option should be
        paired with `flip_drive_access` from `GT - Create Transit Network`.
      False (default): the skim isn't transposed.

*/

Macro "GT - Transit Skim" (MacroOpts)

  // Argument extraction
  rts_file = RunMacro("Normalize Path",MacroOpts.rts_file)
  param_file = RunMacro("Normalize Path",MacroOpts.param_file)
  expr_vars = MacroOpts.expr_vars
  net_dir = RunMacro("Normalize Path",MacroOpts.net_dir)
  output_matrix = RunMacro("Normalize Path",MacroOpts.output_matrix)
  simplify_core_names = MacroOpts.simplify_core_names
  cycle = MacroOpts.cycle
  clear_output_dir = MacroOpts.clear_output_dir
  period = MacroOpts.period
  ap_direction = MacroOpts.ap_direction

  // Argument checking
  if rts_file = null then Throw("'rts_file' not provided")
  if GetFileInfo(rts_file) = null then Throw("'rts_file' not found")
  if param_file = null then Throw("'param_file' not provided")
  if GetFileInfo(param_file) = null then Throw("'param_file' not found")
  if net_dir = null then Throw("'net_dir' not provided")
  if output_matrix = null then Throw("'output_matrix' not provided")
  if simplify_core_names = null then simplify_core_names = "true"
  if cycle = null then Throw("'cycle' not provided")
  if period = null then Throw("'period' not provided")

  {drive, folder, out_file, out_ext} = SplitPath(output_matrix)
  output_dir = RunMacro("Normalize Path", drive + folder)
  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)

  // Read the settings table
  all_settings = RunMacro("Read Parameter File", param_file, expr_vars)

  // Clear the skim directory if indicated
  if clear_output_dir then RunMacro("Clear Directory", output_dir)

  // After the first feedback cycle, make a copy of the prev skim.
  // It will be used to check for convergence.
  if cycle > 1 then do
    prev_dir = output_dir + "/previous"
    if GetDirectoryInfo(prev_dir, "All") = null then CreateDirectory(prev_dir)

    from = output_matrix
    to = prev_dir + "/" + out_file + out_ext
    CopyFile(from, to)
  end

  // Collect layer and DBD info from route system
  opts = null
  opts.file = rts_file
  {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", opts)
  hwy_dbd = GetLayerDB(llyr)
  stop_dbd = GetLayerDB(slyr)
  CloseMap(map)

  for i = 1 to all_settings.length do
    net_name = all_settings[i][1]
    settings = CopyArray(all_settings.(net_name))

    // "GT - Create Transit Networks" checks that all modes are in the scenario
    // before building the tnw files. If the tnw doesn't exist, skip skimming.
    net_file = net_dir + "\\" + settings.out_file
    if GetFileInfo(net_file) = null then continue

    opts = null
    opts.Input.Database = hwy_dbd
    opts.Input.[Transit RS] = rts_file
    opts.Input.Network = net_file
    centroid_query = RunMacro("Normalize Query", settings.centroid_query)
    opts.Input.[Origin Set] = {hwy_dbd + "|" + nlyr, nlyr, "centroid_set", centroid_query}
    opts.Input.[Destination Set] = {hwy_dbd + "|" + nlyr, nlyr, "centroid_set"}
    opts.Global.[Load Method] = "PF"
    opts.Global.[Skim Variables] = {
      "Generalized Cost", "Fare", "In-Vehicle Time", "Initial Wait Time",
      "Transfer Wait Time", "Initial Penalty Time", "Transfer Penalty Time",
      "Transfer Walk Time", "Access Walk Time", "Egress Walk Time",
      "Access Drive Time", "Egress Drive Time", "Dwelling Time", "Total Time",
      "In-Vehicle Cost", "Initial Wait Cost", "Transfer Wait Cost",
      "Initial Penalty Cost", "Transfer Penalty Cost", "Transfer Walk Cost",
      "Access Walk Cost", "Egress Walk Cost", "Access Drive Cost",
      "Egress Drive Cost", "Dwelling Cost", "Number of Transfers",
      "In-Vehicle Distance", "Access Drive Distance", "Egress Drive Distance"
    }
    opts.Global.[OD Layer Type] = "Node"
    output_mtx = Substitute(
      output_dir + "/" + settings.out_file,
      ".tnw", ".mtx",
    )
    opts.Output.[Skim Matrix].Label = net_name + " Skim Matrix (Pathfinder)"
    opts.Output.[Skim Matrix].[File Name] = output_mtx
    ok = RunMacro("TCB Run Procedure", "Transit Skim PF", opts, &Ret)
    if !ok then do
      err_msg = "Transit skim failed for " + net_name
      if Ret <> null then do
        Ret = {err_msg} + Ret
        ShowArray(Ret)
      end
      Throw(err_msg)
    end
    Ret = null

    // Simplify core names
    if simplify_core_names then do
      simple_names = {
        "gen_cost", "fare", "ivt_transit", "initial_wait",
        "xfer_wait_time", "initial_penalty_time", "xfer_penalty_time",
        "xfer_walk_time", "access_walk_time", "egress_walk_time",
        "access_drive_time", "egress_drive_time", "dwell_time", "total_time",
        "iv_cost", "initial_wait_cost", "xfer_wait_cost",
        "initial_penalty_cost", "xfer_penalty_cost", "xfer_walk_cost",
        "access_walk_cost", "egress_walk_cost", "access_drive_cost",
        "egress_drive_cost", "dwell_cost", "num_xfers",
        "iv_dist", "access_drive_dist", "egress_drive_dist"
      }

      mtx = OpenMatrix(output_mtx, )
      SetMatrixCoreNames(mtx, simple_names)
      mtx = null
    end

    to_combine = to_combine + {output_mtx}
    prefix = prefix + {net_name + "_"}
  end

  // Combine skim matrices
  opts = null
  opts.matrices = to_combine
  opts.output_matrix = output_matrix
  opts.label = "Transit Skim " + period
  opts.delete_orig = "true"
  opts.core_prefix = prefix
  RunMacro("GT - Combine Matrices", opts)

  // Check and flip matrix to AP format if specified
  if ap_direction then do
    label = "Transit Skim " + period + " transposed to AP"
    RunMacro("Transpose Matrix", output_matrix, label)
  end
EndMacro

/*
Fills in the diagonals of a skim matrix. Is applied to every core. Uses the
TC approach of taking a percentage of the skim time of a given number of
nearest neighbors.

Inputs
  MacroOpts
    Named array containing all inputs

    matrix
      String or matrix handle
      Either the file path of the matrix or its handle.
      
    cores
      Optional string or array of strings
      Names of matrix cores to fill. Defaults to all.

    neighbors
      Optional integer
      How many nearest neighbors to use. Default is 3.

    factor
      Optional real
      Factor to apply to the average value of nearest neighbors. Default is .75.

    row_index
      Optional string
      Matrix row index to use. Defaults to primary.

    column_index
      Optional string
      Matrix column index to use. Defaults to primary.
*/

Macro "GT - Fill Skim Intrazonals" (MacroOpts)

  // Argument extraction
  matrix = MacroOpts.matrix
  cores = MacroOpts.cores
  neighbors = MacroOpts.neighbors
  factor = MacroOpts.factor
  row_index = MacroOpts.row_index
  column_index = MacroOpts.column_index

  // Argument checking
  if MacroOpts.matrix_file <> null then Throw(
    "Intrazonals: 'matrix_file' is deprecated. Use 'matrix' argument instead.")
  if matrix = null then Throw("'matrix' not provided.")
  if TypeOf(matrix) = "string" then matrix = OpenMatrix(matrix, )
  else if TypeOf(matrix) <> "matrix" then Throw(
    "Intrazonals: 'matrix' must be either a string or matrix handle.")
  if TypeOf(cores) = "string" then cores = {cores}
  if neighbors = null then neighbors = 3
  if factor = null then factor = .75

  if cores <> null then do
    for core in cores do
      a_curs.(core) = CreateMatrixCurrency(matrix, core, row_index, column_index, )
    end
  end else a_curs = CreateMatrixCurrencies(matrix, row_index, column_index, )

  for currency in a_curs do
    Opts = null
    Opts.Input.[Matrix Currency] = currency[2]
    Opts.Global.Factor = factor
    Opts.Global.Neighbors = neighbors
    Opts.Global.Operation = 1
    Opts.Global.[Treat Missing] = 2
    ret_value = RunMacro("TCB Run Procedure", "Intrazonal", Opts, &Ret)
  end
EndMacro

/*
Checks a matrix to see if any column or row totals are zero. In a highway skim
matrix, this signifies that a centroid is not properly connected to the network.
This doesn't work for transit skims, as a null marginal could just mean that no
'reasonable' path exists.

Returns
  Either "true", meaning all centroids are connected, or a message indicating
  the first disconnected centroid found.
*/

Macro "Check Skim For Disconnected Centroids" (mtx_file)

  mtx = OpenMatrix(mtx_file, )
  marg_types = {"row", "column"}
  corenames = GetMatrixCoreNames(mtx)
  currencies = CreateMatrixCurrencies(mtx, , , )

  for corename in corenames do
    cur = currencies.(corename)
    for marg_type in marg_types do
      opts.Index = marg_type
      ids = GetMatrixVector(cur, opts)
      marginal = GetMatrixMarginals(cur, "sum", marg_type)
      pos = ArrayPosition(marginal, {0}, )
      if pos <> 0 then do
        id = ids[pos]
        return(
          "Centroid " + String(id) + " is disconnected\n" +
          "(0 found for skimming " + marg_type + " marginal)\n" +
          "Matrix: " + mtx_file
        )
      end
    end
  end

  return("true")
EndMacro
