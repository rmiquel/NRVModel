/*
This script contains three primary functions along with helper macros:
  Gravity
  Destination Choice
  Aggregate Distribution Matrices
*/

/*dontdoc
Provides a general gravity model that leverages parameter files and abstracts
away some of the complexity with TransCADs base function.

Inputs (all in a named array)
  * `se_bin`
    * String
    * Full path to the socio-economic bin file.
  * `skim_file`
    * String
    * Full path to the skim matrix that will be used for impedance.
  * `param_file`
    * String
    * Full path to the parameter file that controls model behavior.
  * `period`
    * String
    * Time period (e.g. "AM"). Used to extract a subset of parameters. Is also
      included in the output file name.
  * `output_dir`
    * String
    * Full path to the directory where the resulting trip matrix is written.
      
Returns
  Nothing. Writes out a trip matrix to 'output_dir'
*/

Macro "Gravity" (MacroOpts)

  Throw(
    "As of TC 8 build 22150 this has to be deprecated due to a bug in \n" +
    "how it handles open progress bars. Use 'Gravity2'."
  )

  se_bin = MacroOpts.se_bin
  skim_file = MacroOpts.skim_file
  param_file = MacroOpts.param_file
  period = MacroOpts.period
  output_dir = MacroOpts.output_dir

  // Read the parameter file
  grav_params = RunMacro("Read Parameter File", param_file)

  // Open the skim matrix and se table
  skim_mtx = OpenMatrix(skim_file, )
  {ri, ci} = GetMatrixIndex(skim_mtx)
  vw_se = OpenTable("ScenarioSE", "FFB", {se_bin})

  // Loop over each purpose found in the param file
  for p = 1 to grav_params.length do
    purp = grav_params[p][1]

    params = grav_params.(purp).(period)

    // Create skim currency
    imp_core = params.imp_core
    cur = CreateMatrixCurrency(skim_mtx, imp_core, ri, ci, )

    opts = null
    opts.Input.[PA View Set] = {se_bin, vw_se}
    opts.Input.[FF Tables] = {}
    opts.Input.[Imp Matrix Currencies] = {cur}
    opts.Input.[FF Matrix Currencies] = {}
    opts.Global.[Constraint Type] = {params.constraint}
    opts.Global.[Purpose Names] = {purp}
    opts.Global.Iterations = {50}
    opts.Global.Convergence = {0.001}
    opts.Global.[Fric Factor Type] = {"Gamma"}
    opts.Global.[A List] = {params.a}
    opts.Global.[B List] = {params.b}
    opts.Global.[C List] = {params.c}
    opts.Global.[Minimum Friction Value] = {0}
    opts.Field.[Prod Fields] = {params.p_field}
    opts.Field.[Attr Fields] = {params.a_field}
    opts.Field.[FF Table Times] = {}
    opts.Field.[FF Table Fields] = {}
    opts.Output.[Output Matrix].Label = purp + " Gravity Matrix"
    opts.Output.[Output Matrix].Compression = 1
    out_file = output_dir + "/trips_" + purp + "_" + period + ".mtx"
    opts.Output.[Output Matrix].[File Name] = out_file
    ret_value = RunMacro("TCB Run Procedure", "Gravity", opts, &Ret)
    if !ret_value then Throw("Gravity model failed")
  end
EndMacro

/*doc
Provides a general gravity model that leverages parameter files and abstracts
away some of the complexity with TransCADs base function.

Uses the Distribution.Gravity object instead of "TCB Run Procedure".
In the latest build of TC 8 (currently 22150), the old TCB gravity procedure
destroys too many progress bars.

Inputs (all in a named array)
  * `se_bin`
    * String
    * Full path to the socio-economic bin file.
  * `skim_file`
    * String
    * Full path to the skim matrix that will be used for impedance.
  * `param_file`
    * String
    * Full path to the parameter file that controls model behavior.
  * `period`
    * String
    * Time period (e.g. "AM"). Used to extract a subset of parameters. Is also
      included in the output file name.
  * `output_matrix`
    * String
    * Full path where the resulting trip matrix is written.
      
Returns
  An array of results from the gravity application. Also, writes out
  `output_matrix`.
*/

Macro "Gravity2" (MacroOpts)

  se_bin = MacroOpts.se_bin
  skim_file = MacroOpts.skim_file
  param_file = MacroOpts.param_file
  period = MacroOpts.period
  output_matrix = MacroOpts.output_matrix

  // Read the parameter file
  grav_params = RunMacro("Read Parameter File", param_file)

  // Open the skim matrix and se table
  skim_mtx = OpenMatrix(skim_file, )
  {ri, ci} = GetMatrixIndex(skim_mtx)
  vw_se = OpenTable("ScenarioSE", "FFB", {se_bin})

  // Create the gravity object
  obj = CreateObject("Distribution.Gravity")
  obj.DataSource = {TableName: se_bin}
  obj.OutputMatrix({
    MatrixFile: output_matrix,
    MatrixLabel: purp + " Gravity Matrix",
    Compression: "true",
    ColumnMajor: "false"
  })
  obj.ResetPurposes()

  // Loop over each purpose found in the param file
  for p = 1 to grav_params.length do
    purp = grav_params[p][1]

    params = grav_params.(purp).(period)

    obj.AddPurpose({
      Name: purp,
      Iterations: 50,
      Convergence: 0.001,
      Production: params.p_field,
      Attraction: params.a_field,
      ImpedanceMatrix: {
        MatrixFile: skim_file,
        Matrix: params.imp_core,
        RowIndex: ri,
        ColIndex: ci
      },
      Gamma: {params.a, params.b, params.c},
      Constraint: params.constraint
    })
  end
  
  // Create and destroy a dummy progress bar around the task. Bug in TC will
  // mess up the last progress bar created.
  CreateProgressBar('', )
  obj.Run()
  DestroyProgressBar()
  
  r = obj.GetResult()
  return(r)
EndMacro

/*doc
This DC function uses the NestedLogitEngine in TC (not the older NLM).

The object name is "NLM.Model".  You can use GetClassMethodNames("NLM.Model") to
see all the methods available, but there is no help for them.  Caliper has
been willing to help explain some of them and how to use them.

One major difference between the DC and MC methods in GT is due to the fact that
TransCAD does not (currently) support market segments in the DC application of
the DC model. Thus, this macro has a fundamentally different looping structure
and steps required to build support for segments on top.

Inputs (all in a named array)
  * `period`
    * String
    * Time of day - e.g. "AM" or "PK". Must match a period in the param_file.
  * `tables`
    * Named array
    * Defines the file and (optional) selection set to use for each table data
      source. Must be nested by matrix names that match those in the template_mdl
      file. Must include a "zone_tbl" table.
    * For example:
      * tables.zone_tbl.file = se_bin
      * tables.zone_tbl.set_name = "internal"
      * tables.zone_tbl.query = "Select * where parish <> 'Ext'"
        * where "zone_tbl" is the name of one of the table data sources in the
          template_mdl file.
  * `matrices`
    * Named array
    * Defines the files and (optional) index to use for each matrix data source.
      Must be nested by matrix names that match those in the template_mdl file.
      Must include a "hwy_skim" file. If using logsums, include a "mc_mtx" file.
    * For example:
      * matrices.hwy_skim.file = ".../skim.mtx"
      * matrices.hwy_skim.index = "internal"
      * matrices.mc_mtx.file = ".../logsums.mtx"
      * matrices.mc_mtx.index = "internal"
    * By default, the first core of 'hwy_skim' will be assumed to be the distance
      core to use for the distance polynomial. You can specify a different core
      using:
      * matrices.hwy_skim.dist_core = "da_dist"
  * `template_dcm`
    * String
    * Path to the template model file (.dcm) to use. This file has matrix cores
      and table fields needed to calculate utilities. The coefficients are
      usually set to 0, as they are overwritten by the parameter file.
    * Must include the following data source names:
      * zone_tbl
      * hwy_skim
    * Optional mode choice matrix name:
      * mc_mtx
  * `param_file`
    * String
    * Path to the parameter file. This file contains the utility coefficients.
      It is specified by time period, purpose, and market segment.
    * For Example:  
    
| Period | Purpose | Segment | Section | Term     | Value | Description                         |
|--------|---------|---------|---------|----------|-------|-------------------------------------|
| PK     | HBW     | inc1    | coeff   | size     | 1     | coefficient of attraction size term |
| PK     | HBW     | inc1    | param   | dist_cap | 7     | cap on distance polynomial          |

  * `vars_file`
    * String
    * Path to the variables file. This file contains the variables used and
      their source file. For DC, there is only one alternative: "Destinations"
      (or whatever you've called it in the dcm file). Variables that can be
      included in the file: {purpose}, {segment}, {period}
    * For example:  
    
| alternative  | variable     | source                                 |
|--------------|--------------|----------------------------------------|
| Destinations | logsum       | mc_mtx.logsum_{purpose}_{segment}_ROOT |
| Destinations | dist         | hwy_skim.dist_capped                   |
| Destinations | size         | zone_tbl.dc_size                       |
| Destinations | shadow_price | zone_tbl.shadow_price                  |
    
      * The source file (e.g. hwy_skim) must match the source file names
        setup in the template mdl file. 'size' and 'shadow_price' are required
        variables as well as 'zone_tbl' and 'hwy_skim' sources.
  * `expr_vars`
    * Optional named array
    * Used to evaluate any {variables} found in the parameter files.
  * `output_matrix`
    * String
    * Path to the output directory. This is the folder where all outputs will
      be stored.
*/

Macro "GT - Destination Choice NLM" (MacroOpts)

  // Argument extraction
  period = MacroOpts.period
  output_matrix = MacroOpts.output_matrix
  template_dcm = MacroOpts.template_dcm
  param_file = MacroOpts.param_file
  vars_file = MacroOpts.vars_file
  expr_vars = MacroOpts.expr_vars
  tables = MacroOpts.tables
  matrices = MacroOpts.matrices
  dist_poly = MacroOpts.dist_poly

  // Argument checks
  if period = null then Throw("'period' not provided")
  if output_matrix = null then Throw("'output_matrix' not provided")
  if param_file = null then Throw("'param_file' not provided")
  if vars_file = null then Throw("'vars_file' not provided")
  if Right(vars_file, 4) <> ".csv" then Throw("'vars_file' must be a csv")
  df = CreateObject("df")
  df.read_csv(vars_file)
  if !df.in("size", df.tbl.variable)
    then Throw(
      "'size' variable must be included in 'vars_file'.\n" +
      "See 'GT - Destination Choice' code comment for help."
      )
  if !df.in("shadow_price", df.tbl.variable)
    then Throw(
      "'shadow_price' variable must be included in 'vars_file'.\n" +
      "See 'GT - Destination Choice' code comment for help."
      )
  if template_dcm = null then Throw("'template_dcm' not provided")
  if tables = null then Throw("'tables' not provided")
  if tables.zone_tbl = null then Throw("'tables' must contain a 'zone_tbl'")
  if matrices = null then Throw("'matrices' not provided")
  if matrices.hwy_skim = null then Throw("'matrices' must contain a 'hwy_skim'")
  if matrices.hwy_skim.dist_core = null then do
    mtx = OpenMatrix(matrices.hwy_skim.file, )
    matrices.hwy_skim.dist_core = GetMatrixCore()
    mtx = null
  end
  expr_vars.period = period

  {drive, folder, name, ext} = SplitPath(output_matrix)
  output_dir = RunMacro("Normalize Path", drive + folder)
  zone_tbl = tables.zone_tbl.file
  skim_file = matrices.hwy_skim.file
  dist_core = matrices.hwy_skim.dist_core

  // Read in the dc parameter file and check for a period column
  df = RunMacro("Filter Parameter File by Period", param_file, expr_vars, period)
  dc_params = df.to_params()
  num_purposes = dc_params.length

  // Open the zone_tbl file and add a dc_size and shadow price column
  se_tbl = OpenTable("ScenarioSE", "FFB", {zone_tbl})
  a_fields = {
    {"dc_size", "Real", 10, 2,,,,"dc size term|varies by purp and tod"},
    {"shadow_price", "Real", 10, 2,,,,"dc shadow price|varies by purp and tod"}
  }
  RunMacro("Add Fields", se_tbl, a_fields, {0, 0})
  CloseView(se_tbl)

  for p = 1 to num_purposes do
    purpose = dc_params[p][1]

    purp_params = dc_params.(purpose)
    num_segments = purp_params.length

    for s = 1 to num_segments do
      segment = purp_params[s][1]
      params = purp_params.(segment).param
      coeffs = purp_params.(segment).coeff

      prod_field = params.prod_field
      attr_field = params.attr_field
      max_iters = if (params.max_iters = null) then 1 else params.max_iters
      // if iterating shadow price, set a min number of iterations
      if max_iters > 1 then min_iters = min(10, max_iters)

      // Fill dc_size column with appropriate attraction info
      // Fill shadow price with 0s
      se_tbl = OpenTable("ScenarioSE", "FFB", {zone_tbl})
      v_attr = nz(GetDataVector(se_tbl + "|", attr_field, ))
      v_attr = if (v_attr = 0) then 0 else log(v_attr)
      SetDataVector(se_tbl + "|", "dc_size", v_attr, )
      v_sp = if (nz(v_attr) >= 0) then 0 else 0
      SetDataVector(se_tbl + "|", "shadow_price", v_sp, )
      CloseView(se_tbl)

      // Create a copy of the template dcm file and update its
      // attributes.
      // The DC Model Application GUI does not support market segments like MC.
      // For now, make a separate mdl copy for each segment in addition to
      // period and purpose. (4/18:) Caliper has confirmed that this has to be
      // improved in a later build/version of TC.
      prefix = period + "_" + purpose + "_" + segment
      dcm_file = output_dir + "/" + prefix + ".dcm"
      CopyFile(template_dcm, dcm_file)

      // Calculate distance cores required by DC
      RunMacro(
        "Calc DC Matrix Cores", params.dist_cap, skim_file, dist_core, period
      )

      // Start by updating the nlm sources
      nle_source_opts = RunMacro(
        "GT - Update NLM Sources", dcm_file, matrices, tables)

      // Then update the nlm variables
      expr_vars.period = period
      expr_vars.purpose = purpose
      expr_vars.segment = segment
      vars_tbl = RunMacro(
        "GT - prepare variable table", param_file, vars_file, expr_vars, purpose
      )
      vars_tbl.filter("segment = '" + segment + "'")
      vars_tbl.mutate("segment", "*")
      temp_file = output_dir + "/temp.csv"
      vars_tbl.write_csv(temp_file)
      RunMacro("GT - Set Utility Variables", dcm_file, temp_file, tables)
      DeleteFile(temp_file)

      // Create model object
      model = null
      model = CreateObject("NLM.Model")
      model.Read(dcm_file, 1)
      seg = model.GetSegment("*")

      // Change totals field (the productions). Assume that the zone_tbl
      // contains production info.
      source = model.Sources.Get("zone_tbl")
      da = source.CreateDataAccess("totals", prod_field, )
      seg.SetTotals(da)

      // Change coefficients
      for fld = 1 to model.GetFieldCount() do
        field = model.GetField(fld)
        term = seg.GetTerm(field.Name)
        term.Coeff = nz(coeffs.(field.Name))
      end

      // Set the skim index of destinations
      nlm_model = GetClassMethodNames("NLM.Model")
      nlm_seg = GetClassMethodNames("NLM.Segment")
      dest_index = matrices.hwy_skim.index
      if dest_index = null then do
        mtx = OpenMatrix(skim_file, )
        {ris, cis} = GetMatrixIndexNames(mtx)
        dest_index = cis[1]
        mtx = null
      end
      model.Segments.Items.[*].Alts.Items[2][2].DestIdx = dest_index

      // write out the new dcm_file file for manual review
      model.Write(dcm_file)
      model.Clear()

      // Run the model
      dc_iter = 1
      pct_rmse = 100
      rmse_target = 5 // percent
      while pct_rmse > rmse_target and dc_iter <= max_iters do
        nle_opts = CopyArray(nle_source_opts)
        nle_opts.Global.[Missing Method] = "Drop Mode"
        nle_opts.Global.[Base Method] = "On View"
        nle_opts.Global.[Small Volume To Skip] = 0.001
        nle_opts.Global.[Utility Scaling] = "None"
        nle_opts.Global.Model = dcm_file
        nle_opts.Flag.[To Output Utility] = 1
        nle_opts.Flag.Aggregate = 1
        nle_opts.Flag.[Destination Choice] = 1
        // Probability matrix
        prefix = purpose + "_" + segment
        prob_name = "probabilities_" + prefix + ".MTX"
        prob_file = output_dir + "/" + prob_name
        nle_opts.Output.[Probability Matrix].Label = prefix + " Probability"
        nle_opts.Output.[Probability Matrix].Compression = 1
        nle_opts.Output.[Probability Matrix].FileName = prob_name
        nle_opts.Output.[Probability Matrix].[File Name] = prob_file
        // Trips matrix
        trip_name = "trips_" + prefix + ".MTX"
        trip_file = output_dir + "/" + trip_name
        nle_opts.Output.[Applied Totals Matrix].Label = prefix + " Trips"
        nle_opts.Output.[Applied Totals Matrix].Compression = 1
        nle_opts.Output.[Applied Totals Matrix].FileName = trip_name
        nle_opts.Output.[Applied Totals Matrix].[File Name] = trip_file
        // Utility matrix
        util_name = "utilities_" + prefix + ".MTX"
        util_file = output_dir + "/" + util_name
        nle_opts.Output.[Utility Matrix].Label = prefix + " Utility"
        nle_opts.Output.[Utility Matrix].Compression = 1
        nle_opts.Output.[Utility Matrix].FileName = util_name
        nle_opts.Output.[Utility Matrix].[File Name] = util_file

        ok = RunMacro("TCB Run Procedure", "NestedLogitEngine", nle_opts, &Ret)
        if !ok then do
          string = "DC failed for " + period + " " + purpose + " " + segment
          Throw(string)
        end
        Ret = null

        // Shadow pricing

        // Export column marginals to table
        m = OpenMatrix(trip_file,)
        mc = CreateMatrixCurrency(m,,,,)
        marginal_bin = output_dir + "/marginal.bin"
        ExportMatrix(mc,, "Columns", "FFB", marginal_bin, {{"Marginal", "Sum"}})
        mc = null
        m = null

        // Open matrix marginal table table and join to the se table
        vw_se = OpenTable("se", "FFB", {zone_tbl})
        vw_marg = OpenTable("temp", "FFB", {marginal_bin,},)
        {flds, specs} = GetFields(vw_marg,)
        SetView(vw_se)
        vw_join = JoinViews("jv", vw_se + ".ID", vw_marg + "." + flds[1],)
        SetView(vw_join)
        qry = "Select * where " + vw_se + "." + attr_field + " > 0"
        n = SelectByQuery("selection", "several", qry)

        // Calculate RMSE
        v_target = GetDataVector(vw_join + "|", vw_se + "." + attr_field, )
        v_result = GetDataVector(vw_join + "|", vw_marg + "." + flds[2], )
        {rmse, pct_rmse} = RunMacro("Calculate Vector RMSE", v_target, v_result)

        // Calculate shadow price
        v_sp = nz(GetDataVector(vw_join + "|", vw_se + ".shadow_price", ))
        v_sp = v_sp + log(v_target / v_result)
        SetDataVector(vw_join + "|", vw_se + ".shadow_price", v_sp, )
        CloseView(vw_join)
        CloseView(vw_se)
        CloseView(vw_marg)

        // Require the min_iters be performed
        if dc_iter < min_iters then pct_rmse = 100
        dc_iter = dc_iter + 1

        // To simplify project code using this macro, make sure that the final
        // matrix dimensions include all centroids. Thus, if a selection set was
        // applied, expand the matrix. The new rows/columns will be null.
        if tables[1][2].query <> null
          then RunMacro("Expand Matrix to All Centroids", trip_file, skim_file)
      end

      // Add output matrices to list of matrices to combine
      trip_files = trip_files + {trip_file}
      prob_files = prob_files + {prob_file}
      util_files = util_files + {util_file}
    end
  end

  // Combine trip matrices and simplify core names. To simplify project code,
  // the probability and utility matrices are kept in a second matrix. This
  // allows projet code to combine trip matrices from multiple distribution
  // models easily (resident, CV, EE, etc.).
  opts = null
  opts.matrices = trip_files
  opts.output_matrix = output_matrix
  {drive, folder, name, ext} = SplitPath(output_matrix)
  opts.label = name
  opts.delete_orig = "true"
  RunMacro("GT - Combine Matrices", opts)
  // Remove "trips_" and "_Total" from core names
  mtx = OpenMatrix(output_matrix, )
  corenames = A2V(GetMatrixCoreNames(mtx))
  corenames = Right(corenames, StringLength(corenames) - 6)
  corenames = Left(corenames, StringLength(corenames) - 6)
  SetMatrixCoreNames(mtx, V2A(corenames))

  opts = null
  opts.matrices = prob_files + util_files
  {drive, folder, name, etc} = SplitPath(output_matrix)
  name = name + "_utilprob"
  opts.output_matrix = drive + folder + name + ".mtx"
  opts.label = name
  opts.delete_orig = "true"
  RunMacro("GT - Combine Matrices", opts)

  // Clean up workspace
  se_tbl = OpenTable("se", "FFB", {zone_tbl})
  RunMacro("Remove Field", se_tbl, "dc_size")
  RunMacro("Remove Field", se_tbl, "shadow_price")
  CloseView(se_tbl)
  DeleteFile(marginal_bin)
  DeleteFile(Substitute(marginal_bin, ".bin", ".DCB", ))

EndMacro

/*dontdoc
Helper macro
Adds additional matrix cores needed by DC to the skim file.
For distance polynomial cores, respects the distance cap if provided.

Critical Assumption:
By default, the first core in an output TC skim matrix is a length field.
The first core will be used as the base distance field (regardless of the name).
*/

Macro "Calc DC Matrix Cores" (dist_cap, skim_file, dist_core, period)

  if dist_cap = null then dist_cap = 1000

  // Open matrix and modify cores
  mtx = OpenMatrix(skim_file, )
  a_corenames = GetMatrixCoreNames(mtx)

  // Add new cores used by DC models
  a_new_cores = {
    "dist_capped",
    "dist_capped_sq",
    "dist_capped_cu",
    "dist_const",
    "intrazonal"
  }
  for nc = 1 to a_new_cores.length do
    if ArrayPosition(a_corenames, {a_new_cores[nc]}, ) = 0 then
      AddMatrixCore(mtx, a_new_cores[nc])
  end

  // Create currencies
  cur = CreateMatrixCurrencies(mtx, , , )

  // Calculate distance polynomial cores based on
  // potentially capped distances.
  cur.dist_capped := min(cur.(dist_core), dist_cap)
  cur.dist_capped_sq := Pow(cur.dist_capped, 2)
  cur.dist_capped_cu := Pow(cur.dist_capped, 3)
  cur.dist_const := 1

  // Calcualte the intrazonal core
  cur.intrazonal := 0
  rows = cur.(cur[1][1]).Rows
  opts = null
  opts.Constant = 1
  v_iz = Vector(rows, "Long", opts)
  opts = null
  opts.Diagonal = "True"
  SetMatrixVector(cur.intrazonal, v_iz, opts)

  cur = null
  mtx = null
EndMacro

/*dontdoc
Often, the NLM.Model is only applied to a subset of centroids (generally
internal zones) while the skim matrix includes both internal and external zones.
It makes everything easier to have the output matrices of DC and MC be the
right dimension.

Inputs
  mtx_file
    String
    Full path to matrix file to be expanded
    
  target_file
    String
    Full path to the matrix with the desired dimensions.
    
  target_ri
    Optional string
    Name of row index in the `target_file` to use. The default is the first.
    
  target_ci
    Optional string
    Name of column index in the `target_file` to use. The default is the first.
*/

Macro "Expand Matrix to All Centroids" 
  (mtx_file, target_file, target_ri, target_ci)

  // Copy the skim matrix structure to a temp file. Will only have one core.
  target_mtx = OpenMatrix(target_file, )
  a_target_mcs = CreateMatrixCurrencies(target_mtx, target_ri, target_ci, )
  {drive, folder, name, ext} = SplitPath(mtx_file)
  temp_mtx_file = drive + folder + "/temp.mtx"
  opts = null
  opts.[File Name] = temp_mtx_file
  opts.Label = purp + " " + period + " Trips"
  opts.Type = "Float"
  opts.Tables = {a_target_mcs[1][1]}
  CopyMatrixStructure({a_target_mcs[1][2]}, opts)

  // Open matrices and create currencies
  mtx = OpenMatrix(mtx_file, )
  a_mtx_mcs = CreateMatrixCurrencies(mtx, , , )
  temp_mtx = OpenMatrix(temp_mtx_file, )
  a_temp_mcs = CreateMatrixCurrencies(temp_mtx, , , )

  // Add each core from mtx_file into the temp matrix
  for mc = 1 to a_mtx_mcs.length do
    final_core_name = a_mtx_mcs[mc][1]
    final_cur = a_mtx_mcs.(final_core_name)

    if mc = 1 then do
      a_temp_mcs[1][2] := null
      MergeMatrixElements(a_temp_mcs[1][2], {final_cur}, , , )
      SetMatrixCoreName(temp_mtx, a_target_mcs[1][1], final_core_name)
    end else do
      AddMatrixCore(temp_mtx, final_core_name)
      temp_cur = CreateMatrixCurrency(temp_mtx, final_core_name, , , )
      MergeMatrixElements(temp_cur, {final_cur}, , , )
    end
  end

  // Change the row/col index to match
  {ri, ci} = GetMatrixIndex(mtx)
  {temp_ri, temp_ci} = GetMatrixIndex(temp_mtx)
  SetMatrixIndexName(temp_mtx, temp_ri, ri)
  SetMatrixIndexName(temp_mtx, temp_ci, ci)

  // Clean up workspace and replace mtx_file with temp_mtx_file
  target_mtx = null
  a_target_mcs = null
  a_mtx_mcs = null
  mtx = null
  temp_mtx = null
  a_temp_mcs = null
  final_cur = null
  temp_cur = null
  DeleteFile(mtx_file)
  {drive, directory, name, ext} = SplitPath(mtx_file)
  RenameFile(temp_mtx_file, name + ext)
EndMacro
