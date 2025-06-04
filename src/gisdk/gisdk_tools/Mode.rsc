/*
Script Notes:
This script file contains macros that apply the Nested Logit Engine in TransCAD
as well as some utility scripts that support manipulation of .mdl files.
*/

/*
Inputs (all in a named array)
  * `period`
    * String
    * Time of day - e.g. "AM" or "PK". Must match a period in the param_file.
  * `tables`
    * Named array
    * Defines the file and (optional) selection set to use for each table data
      source.

      For example:
        tables.zone_tbl.file = se_bin
        tables.zone_tbl.set_name = "internal"
        tables.zone_tbl.query = "Select * where parish <> 'Ext'"

      where "zone_tbl" is the name of one of the table data sources in the
      template_mdl file.
  * `matrices`
    * Named array
    * Defines the file and (optional) index to use for each matrix data source.
    * Must be nested by matrix names that match those in the template_mdl file.

      For example:
        matrices.hwy_skim.file = ".../skim.mtx"
        matrices.hwy_skim.index = "internal"

      where "hwy_skim" is the name of one of the matrix data sources in the
      template_mdl file. Note: a matrix named "hwy_skim" is required.
  * `template_mdl`
    * String
    * Path to the template model file (.mdl) to use. 
    * This file has the nesting structure defined as well as the matrix cores
      and table fields that each alternative will use to calculate utilities.
      The coefficients are usually set to 0, as they are overwritten by the
      parameter file. The nesting coefficients are also defined in this file.
  `coeffs_file`
    * String
    * Path to the coefficients file. This file contains utility coefficients
      by purpose and market segment. The coefficients are broken into three
      sections:
      * coeffs: coefficients to apply to matrix/table variables
      * asc: alternative-specific constants
      * nest_coeffs: nesting coefficients

      For Example:
        Purpose | Segment| Section    | Term     | Value | Description
        HBW     | inc1   | coeff      | init_wait| -0.2  | initial wait time
        HBW     | inc1   | asc        | wEB      | -1.2  | ASC for walk-to-express-bus
        HBW     | inc1   | nest_coeff | auto     |  0.7  | ASC for walk-to-express-bus
        etc

    * An optional "Period" can be included as the first column in the rare event
      that MC coefficients are different by time period. If included, all
      purposes, segments, and terms must be repeated for each time period.
  * `vars_file`
    * String
    * Path to the variables file. This file contains, for each modal alternative,
      the variables used and their source file.

      For example:
        alternative | variable     | source
        da          | auto_op_cost | hwy_skim.da_dist_cost
        w_lb        | fare         | trn_skim.w_lb_fare

    * The source file (e.g. hwy_skim) must match the source file names
      setup in the template mdl file.
  * `expr_vars`
    * Optional named array
    * Used to evaluate any {variables} found in the parameter files.
  * `output_matrix`
    * String
    * Path to the final output matrix. It will contain probabilities, logsums,
      and utilities.
  * `utility_scaling`
    * Optional string
    * Either "By Parent Theta" or "By Theta Product".
      * By Theta Product: Scale utilities by the product of all nesting
        coefficients between the root and alternative. This is how nearly
        every WSP model is done. This is also how ALOGIT estimates the model.
      * By Parent Theta: Scale utilities by the nesting coefficient (theta) of
        the parent nest only. Caliper recommends this method.
    * Defaults to "By Theta Product"
*/

Macro "GT - Mode Choice NLM" (MacroOpts)

  // Argument extraction
  period = MacroOpts.period
  tables = MacroOpts.tables
  matrices = MacroOpts.matrices
  template_mdl = MacroOpts.template_mdl
  coeffs_file = MacroOpts.coeffs_file
  vars_file = MacroOpts.vars_file
  expr_vars = MacroOpts.expr_vars
  output_matrix = MacroOpts.output_matrix
  utility_scaling = MacroOpts.utility_scaling
  
  // For debugging purposes
  nlm_model_methods = GetClassMethodNames("NLM.Model")
  nlm_segment_methods = GetClassMethodNames("NLM.Segment")

  // Argument checking
  if period = null then Throw("'period' not provided")
  if tables = null then Throw("'tables' not provided")
  if tables.zone_tbl = null then Throw("'tables' must contain a 'zone_tbl'")
  if matrices = null then Throw("'matrices' not provided")
  if matrices.hwy_skim = null then Throw("'matrices' must contain a 'hwy_skim'")
  for m = 1 to matrices.length do
    name = matrices[m][1]
    file = matrices.(name).file
    index = matrices.(name).index
    if index <> null then do
      mtx = OpenMatrix(file, )
      {ris, cis} = GetMatrixIndexNames(mtx)
      if ArrayPosition(ris, {index}, ) = 0 then error = "Row"
      if ArrayPosition(cis, {index}, ) = 0 then error = "Column"
      if error <> null then Throw(
        error + " index '" + index + "' not found in matrix '" + name + "'")
    end
  end
  if template_mdl = null then Throw("'template_mdl' not provided")
  if coeffs_file = null then Throw("'coeffs_file' not provided")
  if GetFileInfo(coeffs_file) = null then Throw("'coeffs_file' not found")
  if vars_file = null then Throw("'vars_file' not provided")
  if GetFileInfo(vars_file) = null then Throw("'vars_file' not found")
  if output_matrix = null then Throw("'output_matrix' not provided")
  expr_vars.period = period
  if utility_scaling = null then utility_scaling = "By Theta Product"
  if utility_scaling <> "By Parent Theta" and utility_scaling <> "By Theta Product"
    then Throw(
      "'utility_scaling' must be either 'By Parent Theta' or 'By Theta Product'"
    )

  {dir, folder, name, ext} = SplitPath(output_matrix)
  output_dir = RunMacro("Normalize Path", dir + folder)

  // Read in the coefficient parameters. Check for a period column.
  df = RunMacro("Filter Parameter File by Period", coeffs_file, expr_vars, period)
  mc_params = df.to_params()
  num_purposes = mc_params.length

  for p = 1 to num_purposes do
    purpose = mc_params[p][1]

    purp_params = mc_params.(purpose)
    num_markets = purp_params.length

    // Create a copy of the template mdl file to modify attributes
    mdl_file = output_dir + "/" + period + "_" + purpose + ".mdl"
    CopyFile(template_mdl, mdl_file)

    // Start by updating the nlm sources
    nle_opts = RunMacro(
      "GT - Update NLM Sources", mdl_file, matrices, tables)

    // Then set the nlm variables
    expr_vars.purpose = purpose
    vars_tbl = RunMacro(
      "GT - prepare variable table", coeffs_file, vars_file, expr_vars, purpose
    )
    temp_file = output_dir + "/temp.csv"
    vars_tbl.write_csv(temp_file)
    RunMacro("GT - Set Utility Variables", mdl_file, temp_file, tables)
    DeleteFile(temp_file)

    // Create model object.
    model = null
    model = CreateObject("NLM.Model")
    model.Read(mdl_file, 1)

    // Update ASCs and Thetas for each market segment
    for m = 1 to num_markets do
      market = purp_params[m][1]

      nle_opts.Global.Segments = nle_opts.Global.Segments + {market}

      thetas = purp_params.(market).nest_coeff
      ascs = purp_params.(market).asc

      seg = model.GetSegment(market)

      // Change alternative specific constant and nesting coefficients / thetas.
      alts_to_remove = null
      for a = 1 to seg.GetAlternativeCount() do
        alt = seg.GetAlternative(a)
        asc = nz(ascs.(alt.Name))
        theta = nz(thetas.(alt.Name))
        // Remove any leaves without access items (variables in the "utilities")
        // tab. This means the mode isn't present.
        if alt.IsLeaf and alt.Access.Items.length = 0 then do
          alts_to_remove = alts_to_remove + {alt}
          continue
        end
        if asc <> 0 then do
          seg.CreateAscTerm(alt)
          alt.ASC.Coeff = asc
        end
        if theta <> 0 then do
          seg.CreateThetaTerm(alt)
          alt.Theta.Coeff = theta
        end
      end
      
      for alt in alts_to_remove do
        seg.RemoveAlternative(alt)
      end
    end

    // write out the new mdl file for manual review
    model.Write(mdl_file)
    model.Clear()
    
    // Finish setup of NestedLogitEngine's options array
    nle_opts.Global.Model = mdl_file
    nle_opts.Global.[Missing Method] = "Drop Mode"
    nle_opts.Global.[Base Method] = "On Matrix"
    /* nle_opts.Global.[Base Method] = "On View" */
    nle_opts.Global.[Small Volume To Skip] = 0.001
    nle_opts.Global.[Utility Scaling] = utility_scaling
    nle_opts.Global.ShadowIterations = 10
    nle_opts.Global.ShadowTolerance = 0.001
    nle_opts.Flag.ShadowPricing = 0
    nle_opts.Flag.[To Output Utility] = 1
    nle_opts.Flag.[To Output Logsum] = 1
    nle_opts.Flag.Aggregate = 1
    // An output matrix is created for each market
    prob_mtxs = null
    util_mtxs = null
    logsum_mtxs = null
    for m = 1 to num_markets do
      market = purp_params[m][1]

      prob_name = "probabilities_" + purpose + "_" + market + ".MTX"
      prob_file = output_dir + "/" + prob_name
      opts = null
      opts.Label = purpose + "_" + market + " Probability"
      opts.Compression = 1
      opts.FileName = prob_name
      opts.[File Name] = prob_file
      opts.Type = "Automatic"
      opts.[File based] = "Automatic"
      opts.Sparse = "Automatic"
      opts.[Column Major] = "Automatic"
      prob_mtxs = prob_mtxs + {opts}

      util_name = "utilities_" + purpose + "_" + market + ".MTX"
      util_file = output_dir + "/" + util_name
      opts = null
      opts.Label = purpose + "_" + market + " Utility"
      opts.Compression = 1
      opts.FileName = util_name
      opts.[File Name] = util_file
      opts.Type = "Automatic"
      opts.[File based] = "Automatic"
      opts.Sparse = "Automatic"
      opts.[Column Major] = "Automatic"
      util_mtxs = util_mtxs + {opts}

      logsum_name = "logsums_" + purpose + "_" + market + ".MTX"
      logsum_file = output_dir + "/" + logsum_name
      opts = null
      opts.Label = purpose + "_" + market + " Logsum"
      opts.Compression = 1
      opts.FileName = logsum_name
      opts.[File Name] = logsum_file
      opts.Type = "Automatic"
      opts.[File based] = "Automatic"
      opts.Sparse = "Automatic"
      opts.[Column Major] = "Automatic"
      logsum_mtxs = logsum_mtxs + {opts}

      // Keep track of the file names in separate arrays to allow
      // for easy combination.
      prob_files = prob_files + {prob_file}
      util_files = util_files + {util_file}
      logsum_files = logsum_files + {logsum_file}
    end

    nle_opts.Output.[Probability Matrices] = prob_mtxs
    nle_opts.Output.[Utility Matrices] = util_mtxs
    nle_opts.Output.[Logsum Matrices] = logsum_mtxs

    // Run model
    ok = RunMacro("TCB Run Procedure", "NestedLogitEngine", nle_opts, &Ret)
    if !ok then do
      string = "Mode choice failed for " + period + " " + purpose + " " + market
      Throw(string)
    end
    Ret = null

    // Make sure output matrices match skim matrix dimensions
    if tables.zone_tbl.set_name <> null then do
      skim_file = matrices.hwy_skim.file
      // for each market segment
      for i = 1 to nle_opts.Output.[Probability Matrices].length do
        trip_path = nle_opts.Output.[Probability Matrices][i].[File Name]
        RunMacro("Expand Matrix to All Centroids", trip_path, skim_file)
      end
    end
  end

  // Combine all matrix currencies into a single matrix
  opts = null
  opts.matrices = prob_files + logsum_files + util_files
  opts.output_matrix = output_matrix
  opts.label = period + " MC Results"
  opts.delete_orig = "true"
  RunMacro("GT - Combine Matrices", opts)

  RunMacro("Close All")
EndMacro

/*dontdoc
Helper macro for "GT - Mode Choice NLM". Combines the coeffs_file and vars_file
variables into a single CSV file that is then used by "GT - Set Utility
Variables".
*/

Macro "GT - prepare variable table" (coeffs_file, vars_file, expr_vars, purpose)
  c = CreateObject("df")
  c.read_csv(coeffs_file, , expr_vars)
  c.filter("purpose = '" + purpose + "' and section = 'coeff'")
  if c.tbl.value.type = "string"
    then c.tbl.value = Value(c.tbl.value)
  c.select({"segment", "term", "value"})
  segments = c.unique("segment")
  v = CreateObject("df")
  v.read_csv(vars_file, , expr_vars)

  for segment in segments do
    temp = v.copy()
    temp.mutate("segment", segment)
    temp.select({"segment", "alternative", "variable", "type", "source"})
    temp.left_join(c, {"segment", "variable"}, {"segment", "term"})
    temp.rename("value", "coeff")
    temp.tbl.coeff = nz(temp.tbl.coeff)

    if final = null
      then final = temp.copy()
      else final.bind_rows(temp)
  end

  return(final)
EndMacro

/*
Extracts the data sources for each alternative on the "Utilies" tab of the Logit
Model Application GUI (for all segments).

For example, a variable in the utility equation might be
"drive_time" and an alternative named "DAToll" might use the matrix core
"hwy_skim.SOV_toll_time" to get the right value. In that case, the output
CSV would have a row like so:

segment  | alternative  | variable    | source                | type  | coeff
---------------------------------------------------------------------------
inc1     | DAToll       | drive_time  | hwy_skim.SOV_toll_time| Matrix| -.025

The 'type' column can have three values:
  * Matrix: Used for all matrix variables
  * Origin: Says that zonal variable comes from trip origin
  * Destination: Says that zonal variable comes from trip destination

For complex models, the MDL file can be difficult to check for errors. This
puts it in a format more conducive to error checking. The table can also be
used by "GT - Set Utility Variables".

It also serves to document some obscure methods of the NLM.Model.
*/

Macro "GT - Get Utility Variables" (mdl_file)

  if mdl_file = null then Throw("'mdl_file' not provided")
  if GetFileInfo(mdl_file) = null then Throw("'mdl_file' does not exist")

  // Create model object.
  model = null
  model = CreateObject("NLM.Model")
  model.Read(mdl_file, 1)

  // For each segment
  for s = 1 to model.GetSegmentCount() do
    seg = model.GetSegment(s)

    // For each alternative
    for a = 1 to seg.GetAlternativeCount() do
      alt = seg.GetAlternative(a)
      if alt.Access.Items <> null then do
        access = alt.Access

        // For each item in the data access list
        for d = 1 to access.Count() do
          fda = access.Get(d)

          variable_name = fda.Name
          term = seg.GetTerm(variable_name)
          core_or_field_name = fda.Access.Source.Name + "." + fda.Access.Name

          csv.segment = csv.segment + {seg.Name}
          csv.alternative = csv.alternative + {alt.Name}
          csv.variable = csv.variable + {variable_name}
          csv.source = csv.source + {core_or_field_name}
          csv.type = csv.type + {fda.Type}
          csv.coeff = csv.coeff + {term.Coeff}
          csv.description = csv.description + {""}
        end
      end
    end
  end

  model.Clear()

  // Create a data frame and write to CSV
  df = CreateObject("df", csv)
  {drive, directory, name, ext} = SplitPath(mdl_file)
  csv_file = drive + directory + name + ".csv"
  df.write_csv(csv_file)
EndMacro

/*
Sets the data sources and coefficients for each alternative and segment on the
"Utilies" tab of the Logit Model Application GUI. For example, it might tell the
drive- alone alternative which skim core to use for drive time. Also modifies
segments to match those in the csv_file.

Inputs
  csv_file
    String
    Path to CSV file with the same format produced by "GT - Get Utility
    Variables."

  mdl_file
    String
    Path to .mdl file that will have its variables set.

  tables
    Named array
    Used to check the csv_file for valid fields in table sources. ('matrices'
    not needed because the NLM.Model carries their file name internally.)
*/

Macro "GT - Set Utility Variables" (mdl_file, csv_file, tables)

  // For debugging, these will show all NLM.Model and NLM.Segment methods
  nlm_model = GetClassMethodNames("NLM.Model")
  nlm_segment = GetClassMethodNames("NLM.Segment")

  // Clear out any current utility variables
  RunMacro("GT - Clear Utility Variables", mdl_file, "true")

  // Read the csv parameter file
  df = CreateObject("df")
  df.read_csv(csv_file)
  a_segments = df.unique("segment")

  // Create model object.
  model = null
  model = CreateObject("NLM.Model")
  model.Read(mdl_file, 1)

  // Check that the csv source+variable combinations actually exist
  // For now, assume that all table variables are from zone_tbl
  zone_tbl = CreateObject("df")
  zone_tbl.read_bin(tables.zone_tbl.file)
  table_fields = zone_tbl.colnames()
  zone_tbl = null
  for s = 1 to df.tbl.source.length do
    source = df.tbl.source[s]
    type = df.tbl.type[s]

    {source_name, variable} = ParseString(source, ".")

    if type = "Matrix" then do
      file = model.Sources.Items.(source_name).FileName
      mtx = OpenMatrix(file, )
      corenames = GetMatrixCoreNames(mtx)
      if !df.in(variable, corenames)
        then Throw("Core '" + variable + "' not found in '" + source_name + "'")
    end else do
      if !df.in(variable, table_fields)
        then Throw("Field '" + variable + "' not found in 'zone_tbl'")
    end
  end
  mtx = null

  // Collect an array of existing variables in the model. They are called
  // "fields" in the NLM.Model.
  for f = 1 to model.Fields.Items.length do
    existing_fields = existing_fields + {model.Fields.Items[f][1]}
  end

  model_segs = model.GetAllSegments()
  first_seg = model.GetSegment(model_segs.Items[1][1])
  
  // For each segment in the csv file
  for segment in a_segments do

    seg_df = df.copy()
    seg_df.filter("segment = '" + segment + "'")
    
    first_seg.Clone(model, segment)
    seg = model.GetSegment(segment)
    seg.Label = segment
    if first_seg.Name = segment then preserve_first_seg = "true"
    
    // Collect an array of existing terms. Each segment can have different terms.
    existing_terms = null
    for t = 1 to seg.Terms.Items.length do
      existing_terms = existing_terms + {seg.Terms.Items[t][1]}
    end

    // For each alternative
    alternatives = seg_df.unique("alternative")
    for alternative in alternatives do

      alt_df = seg_df.copy()
      alt_df.filter("alternative = '" + alternative + "'")
      alt = seg.GetAlternative(alternative)

      // For each variable
      variables = alt_df.unique("variable")
      for variable in variables do

        var_df = alt_df.copy()
        var_df.filter("variable = '" + variable + "'")

        source = var_df.tbl.source[1]
        coeff = var_df.tbl.coeff[1]
        type = var_df.tbl.type[1]
        if !var_df.in(type, {"Matrix", "Origin", "Destination"})
          then Throw(
            "The 'type' column of the variable table can only\n" +
            "contain: 'Matrix', 'Origin', or 'Destination'"
          )

        {label, field_or_core} = ParseString(source, ".")

        // Create a model field if it doesn't already exist
        if existing_fields = null or !df.in(variable, existing_fields) then do
          fld = model.CreateField(variable, )
          existing_fields = existing_fields + {variable}
        end

        // Create a segment term if it doesn't already exist. Otherwise, set
        // it's coefficient value.
        if existing_terms = null or !df.in(variable, existing_terms) then do
          term = seg.CreateTerm(variable, coeff, )
          existing_terms = existing_terms + {variable}
        end else do
          term = seg.GetTerm(variable)
          term.Coeff = coeff
        end

        fld = model.GetField(variable)
        da = model.CreateDataAccess("data", label, field_or_core)
        alt.SetAccess(fld, da, )
        alt.Access.Items.(variable).Type = type
      end
    end
  end

  if !preserve_first_seg then model.RemoveSegment(first_seg)
  
  // write out the new mdl file for manual review
  model.Write(mdl_file)
  model.Clear()
EndMacro

/*
Clears out any values on the "Utilities" tab of the Logit Model Application GUI.
Clears values for all segments. Optionally, resets segments to just "*".
*/

Macro "GT - Clear Utility Variables" (mdl_file, reset_segments)

  // Create model object.
  model = null
  model = CreateObject("NLM.Model")
  model.Read(mdl_file, 1)

  // Clear all but one model segment
  if reset_segments then do
    model_segs = model.GetAllSegments()
    while model_segs.Items.length > 1 do
      seg_name = model_segs.Items[2][1]
      seg = model.GetSegment(seg_name)
      model.RemoveSegment(seg)
    end
    seg = model.GetSegment(model_segs.Items[1][1])
    model.RenameSegment(seg, "*")
    seg = model.GetSegment("*")
    seg.Label = null
  end

  // For each segment
  for s = 1 to model.GetSegmentCount() do
    seg = model.GetSegment(s)

    // For each alternative
    for a = 1 to seg.GetAlternativeCount() do
      alt = seg.GetAlternative(a)

      if alt.Access.Items <> null then do
        access = alt.Access

        // For each item in the data access list
        for name in access.GetNames() do
          fld = model.GetField(name)
          alt.SetAccess(fld, "", )
        end
      end
    end
  end

  // write out the new mdl file for manual review
  model.Write(mdl_file)
  model.Clear()
EndMacro

/*
Helper macro for DC and MC NLM macros. Updates the sources in the template
model file (either .mdl or .dcm) to those provided by project code.
*/

Macro "GT - Update NLM Sources" (nlm_file, matrices, tables)

  // Create model object
  model = null
  model = CreateObject("NLM.Model")
  model.Read(nlm_file, 1)
  
  // Update matrix sources and indices. This also begins building
  // the 'nle_opts' options array for the NestedLogitEngine macro.
  nle_source_opts = null
  for matrix in matrices do
    source_name = matrix[1]
    opts = matrix[2]
    file = Runmacro("Normalize Path", opts.file)
    mtx = OpenMatrix(file, )
    a_info = GetMatrixInfo(mtx)
    label = a_info[6].Label
    mtx = null

    if GetFileInfo(opts.file) = null
      then Throw("Could not find matrix:\n'" + opts.file + "'")
    source = model.Sources.Get(source_name)
    source.FileName = file
    source.FileLabel = label
    if opts.index <> null then do
      source.RowIdx = opts.index
      source.ColIdx = opts.index
    end
    nle_source_opts.Input.(source_name + " Matrix") = file
  end

  // Setup the table inputs for NLE
  for table in tables do
    source_name = table[1]
    opts = table[2]
    file = Runmacro("Normalize Path", opts.file)

    if GetFileInfo(file) = null
      then Throw("Could not find table:\n'" + opts.file + "'")
    source = model.Sources.Get(source_name)
    if opts.query <> null then do
      opts.query = RunMacro("Normalize Query", opts.query)
      source.Set = opts.set_name
    end
    {drive, directory, name, ext} = SplitPath(file)
    nle_source_opts.Input.(source_name + " Set") = {
      file, name, opts.set_name, opts.query
    }
  end

  model.Write(nlm_file)
  model.Clear()

  return(nle_source_opts)
EndMacro

/*doc
Uses standard matrix outputs from GTs distribution and MC macros to create a
trip matrix by mode.

Standard GT distribution output matrices have cores like:
  * HBW_v0
  * NHB_all
  * etc.
  
Standard GT MC output mactrices have cores like:
  * probabilities_HBW_v0_da
  * probabilities_NHB_all_w_lr
  * etc.
  
The `coeffs_file` file from `GT - Mode Choice NLM` is used to determine
the unique combinations of purpose and segment. Then, the trip matrix is split
into modal cores using the probability cores from the MC matrix.

Inputs
  * trip_matrix
    * String
    * Path to the trip matrix.
  * prob_matrix
    * String
    * Path to the 
  * coeffs_file
    * String
    * Path to the same coefficients file used in `GT - Mode Choice NLM`.
  * output_matrix
    * String
    * Path to the output matrix to be created.
  * period
    * Optional string
    * Time period (e.g. "AM", "OP", etc.). Only used to filter the `coeffs_file`
      if that file has a period column.

Returns
  * Nothing. Creates `output_matrix` by removing the total trip cores
    (e.g. HBW_v0) and replacing them with modal cores (e.g. HBW_v0_da).
*/

Macro "Split Trips by Mode" (MacroOpts)

  trip_matrix = MacroOpts.trip_matrix
  prob_matrix = MacroOpts.prob_matrix
  coeffs_file = MacroOpts.coeffs_file
  period = MacroOpts.period
  output_matrix = MacroOpts.output_matrix
  
  if trip_matrix = null then Throw("Split Trips: 'trip_matrix' not provided")
  if prob_matrix = null then Throw("Split Trips: 'prob_matrix' not provided")
  if coeffs_file = null then Throw("Split Trips: 'coeffs_file' not provided")
  if output_matrix = null then Throw("Split Trips: 'output_matrix' not provided")
  
  CopyFile(trip_matrix, output_matrix)
  trip_matrix = output_matrix
  
  // Read the mc coefficents file to get unique combinations of purpose
  // and market segment. Support an optional period column to filter by.
  df = RunMacro("Filter Parameter File by Period", coeffs_file, expr_vars, period)

  // Open the final MC matrix (trips) and probabilities matrix
  trip_mtx = OpenMatrix(trip_matrix, )
  label = if period <> null
    then period + " Modal Trips"
    else "Modal Trips"
  RenameMatrix(trip_mtx, label)
  prob_mtx = OpenMatrix(prob_matrix, )
  prob_corenames = GetMatrixCoreNames(prob_mtx)
  
  // Manipulate the probability core names to create a set to loop over
  tbl.name = prob_corenames
  df = CreateObject("df", tbl)
  df.separate("name", {"type", "purp", "seg", "alt"})
  df.unite({"purp", "seg"}, "purp_seg")
  df.filter("type = 'probabilities'")
  
  // Calculate trips by alternative
  for r = 1 to df.nrow() do
    row = df.get_row(r, , "true")
    
    trip_cur = CreateMatrixCurrency(trip_mtx, row.purp_seg, , , )
    new_trip_core = row.purp_seg + "_" + row.alt
    AddMatrixCore(trip_mtx, new_trip_core)
    new_trip_cur = CreateMatrixCurrency(trip_mtx, new_trip_core, , , )
    prob_core = row.type + "_" + row.purp_seg + "_" + row.alt
    prob_cur = CreateMatrixCurrency(prob_mtx, prob_core, , , )
    new_trip_cur := nz(trip_cur * prob_cur)
  end
  
  // Delete the original/total cores
  trip_mtx = null
  trip_cur = null
  new_trip_cur = null
  purp_segs = df.unique(df.tbl.purp_seg)
  RunMacro("Drop Cores", trip_matrix, purp_segs)
EndMacro

/*doc
An autocalibration function for GT mode choice models. Wraps the `Adjust ASC`
function into a while loop that also runs model steps.

This function requires the model's project code to be more or less modular, 
with steps able to be called indepenently of the GUI. If the project code is
not like this:

  * Option 1
    * Refactor project code
  * Option 2 (assuming refactor is not possible)
    * Write a project-specific equivalent macro that wraps `Adjust ASCs` to do
      a lot of the heavy lifting.
  * Option 3 (assuming model non-standard outputs prohibit `Adjust ASCs`)
    * In this case, a completely customized calibration algorithm will be
      needed. You can still look to `Adjust ASCs` to understand what is
      involved.

Inputs
  * `coeffs_file`, `target_file`, `modal_trip_matrices`, `equiv_file`
    * Arguments passed to `Adjust ASCs` macro. See that documentation for 
      details.
  * `model_steps`
    * Array of strings
    * Names of the model macros (in order) needed to update modal trip matrices.
  * `model_step_args`
    * Optional array of arguments needed for model steps
    * This is limited in functionality due to the syntax for passing arguments
      in TransCAD. Each model step can only have one argument; however, that
      argument can be an array of arguments. (See Example 2 below.)
  * `max_iters`
    * Optional numeric
    * Maximum number of iterations to perform calibration.
    * Defaults to 50.
  * `rel_gap`
    * Optional numeric
    * Value of %RMSE between observed and modelled modal percentages under
      which they are said to match.
    * Defaults to 0.1. ("zero-point-one percent")
      
Example 1:
```
opts = null
opts.max_iters = 50
opts.rel_gap = 0.1
opts.model_steps = {
  "Calc Mode Shares",
  "Apply Mode Shares"
}
opts.target_file = "Y:\\projects\\NRV\\repo\\docs\\data\\mc_targets.csv"
opts.coeffs_file = "Y:\\projects\\NRV\\repo\\master\\mode\\mc_coefficients.csv"
mode_dir = "Y:\\projects\\NRV\\repo\\scenarios\\Base_2016\\outputs\\mode"
opts.modal_trip_matrices = {
  mode_dir + "/_mc_modal_trips_AM.mtx",
  mode_dir + "/_mc_modal_trips_MD.mtx",
  mode_dir + "/_mc_modal_trips_PM.mtx",
  mode_dir + "/_mc_modal_trips_NT.mtx"
}
RunMacro("Calibrate MC", opts)
```

In the above example, the NRV model uses a global MODELARGS variable, and 
no arguments are needed to pass directly to the model steps. The example
below shows how the code would change with a more traditional model architecture.

Example 2:  
Given two model steps requring arguments:
```
Macro "Model Step 1" (scenario_directory)
  // does stuff
EndMacro

Macro "Model Step 2" ({arg1, arg2, arg3}) // note: they must be in an array
  // does more stuff
EndMacro
```

You would setup `model_steps` and `model_step_args` like so:
```
opts.model_steps = {
  "Model Step 1",
  "Model Step 2"
}
opts.model_step_args = {
  "Y:\\projects\\NRV\\repo\\scenarios\\Base_2016",
  {50, "true", "HBW"}
}
```
*/

Macro "Calibrate MC" (MacroOpts)
  
  // Argument extraction
  coeffs_file = MacroOpts.coeffs_file
  model_steps = MacroOpts.model_steps
  model_step_args = MacroOpts.model_step_args
  max_iters = MacroOpts.max_iters
  rel_gap = MacroOpts.rel_gap
  
  // Argument checking
  if coeffs_file = null then Throw("Calibrate MC: 'coeffs_file' not provided")
  if model_steps = null 
    then Throw("Calibrate MC: 'model_steps' not provided")
  
  // Create a file to log %RMSE for each loop
  {drive, folder, name, ext} = SplitPath(coeffs_file)
  output_dir = drive + folder + "/mc_calib_output"
  RunMacro("Create Directory", output_dir)
  log_file = output_dir + "/_rmse_log.csv"
  log_file = OpenFile(log_file, "w")
  WriteLine(log_file, "cycle,prmse")
  
  if max_iters = null then max_iters = 50
  if rel_gap = null then rel_gap = .1
  
  iter = 0
  prmse = 9999
  CreateProgressBar("", )
  while iter < max_iters and prmse > rel_gap do
    iter = iter + 1
    
    UpdateProgressBar(
      "Calibrating MC. Iteration " +
      String(iter) + " of " + String(max_iters) + "; " +
      "%RMSE: " + String(prmse),
      round(iter / max_iters * 100, 0)
    )
    
    // Run model macros that will calculate new modal trip matrices
    for s = 1 to model_steps.length do
      model_step = model_steps[s]
      if model_step_args[s] <> null then args = model_step_args[s]
      RunMacro(model_step, args)
    end
    
    // Adjust ASCs in the coeffs file
    MacroOpts.backup_suffix = String(iter)
    prmse = RunMacro("Adjust ASCs", MacroOpts)
    
    WriteLine(log_file, String(iter) + "," + String(prmse))
  end
  
  CloseFile(log_file)
  DestroyProgressBar()
EndMacro

/*doc
Performs one update to MC alternative-specific constants by comparing trip
matrices by mode to a target file. All inputs must be the result of the GT
MC macros (or formatted to match them).

Inputs
  * `coeffs_file`
    * String
    * Path to the `coeffs_file` used by "GT - Mode Choice NLM". It lists the
      coefficients for each combination of purpose, segment, and mode. This
      is what gets adjusted. Example:
      
    | purpose | segment | section | term      | value   |
    |---------|---------|---------|-----------|--------:|
    | HBW     | v0      | asc     | da        | -999    |
    | HBW     | v0      | asc     | sr2       | 0       |
    | HBW     | v0      | asc     | sr3       | -3.0048 |
    | HBW     | v0      | asc     | walk      | -3.9589 |
    | HBW     | v0      | asc     | bike      | -5.6167 |
    | …       | …       | …       | …         | …       |
    | HBO     | ilvi    | coeff   | ivt_drive | -0.025  |
    | etc.    | etc.    | etc.    | etc.      | etc.    |
  
    * ASCs of 0 and -999 are not adjusted.
      * 0: marks an alternative as a reference alternative
      * -999: effectively disables an alternative
  
  * `target_file`
    * String
    * Path to file containing MC targets. Looks like the following:
    
    | target_name | target |
    |-------------|-------:|
    | HBW_il_da   | 15000  |
    | HBW_ih_sr2  | 30000  |
    
    The targets are scaled to match total model trips by purpose and market.
    This means that successful calibration will match the percentage of trips
    by mode, but not necessarily the absolute trips by mode. Trip conservation
    checks and absolute target checks should be performed after calibration.
    
  * `modal_trip_matrices`
    * Array
    * Paths to trip matrices that should be combined into total trips.
    * Cores to use in calibration must follow the GT MC naming convention:
      purpose_segment_term (e.g. HBW_v0_da)
    * Other cores can exist in these matrices. If not in `coeffs_file`, they are
      ignored.
  * `equiv_file`
    * Optional string
    * Path to an equivalency between the modal matrix cores and the target file.
    * By default, it is assumed that each matrix core has an associated target
      in `target_file`,  but often the targets are more aggregate and require
      the matrix cores to be aggregated. In the example below, the matrix cores
      include segmentation by auto sufficiency and income. These are are
      collapsed to match targets, which only have market segmentation by income
      group (high and low).
      
      | core         | target     |
      |--------------|------------|
      | HBW_v0_da    | HBW_il_da  |
      | HBW_ilvi_da  | HBW_il_da  |
      | HBW_ihvs_sr2 | HBW_ih_sr2 |
      
  * `damp_factor`
    * Optional numeric
    * Value between 0 and 1 that dampens the adjustment factor. This reduces
      over-correction and helps ensure the calibration process converges.
    * Defaults to 0.75.
  * `backup_suffix`
    * Optional string
    * A backup of the original `coeffs_file` is created. This suffix is appended
      to the file name.
    * Defaults to "_previous".
  * `check_calib`
    * True/false
    * True: rather than adjusting the ASCs, the adjustment calculation will be
      displayed in a view. This is helpful to check if the model is still
      calibrated.
    * Defaults to false

Returns
  * The %RMSE between the observed and estimated modal trips.
  * Updates the `coeffs_file` ASCs.
  * Creates a backup of the original `coeffs_file` with `backup_suffix` appended.
    (e.g. mc_coefficients_original.csv)
*/

Macro "Adjust ASCs" (MacroOpts)
  CreateProgressBar("", )
  UpdateProgressBar("Adjusting ASCs", 0)
  
  target_file = MacroOpts.target_file
  coeffs_file = MacroOpts.coeffs_file
  equiv_file = MacroOpts.equiv_file
  modal_trip_matrices = MacroOpts.modal_trip_matrices
  damp_factor = MacroOpts.damp_factor
  backup_suffix = MacroOpts.backup_suffix
  check_calib = MacroOpts.check_calib
  
  if target_file = null then Throw("Adjust ASCs: 'target_file' not provided")
  if GetFileInfo(target_file) = null 
    then Throw("Adjust ASCs: 'target_file' not found")
  targets = CreateObject("df", target_file)
  targets.separate("target_name", {"purp", "market", "mode"}, , "true")
  targets.filter("mode = null")
  if targets.nrow() > 0
    then Throw(
      "Adjust ASCs: The 'target_name' column in the 'target_file' must be " +
      "formatted like so: purpose_market_mode. If not using market " +
      "segmentation, use 'all' for the market name."
    )
  if coeffs_file = null then Throw("Adjust ASCs: 'coeffs_file' not provided")
  if GetFileInfo(coeffs_file) = null 
    then Throw("Adjust ASCs: 'coeffs_file' not found")
  if equiv_file = null then Throw("Adjust ASCs: 'equiv_file' not provided")
  if GetFileInfo(equiv_file) = null 
    then Throw("Adjust ASCs: 'equiv_file' not found")
  if modal_trip_matrices = null 
    then Throw("Adjust ASCs: 'modal_trip_matrices' not provided")
  if damp_factor = null then damp_factor = .75
  if damp_factor < 0 or damp_factor > 1 
    then Throw("Adjust ASCs: 'damp_factor' must be between 0 and 1")
  if backup_suffix = null then backup_suffix = "_previous"
  
  // Create a directory to store outputs.
  {drive, folder, name, ext} = SplitPath(coeffs_file)
  output_dir = drive + folder + "/mc_calib_output"
  RunMacro("Create Directory", output_dir)
  backup_coeffs = output_dir + "/" + name + backup_suffix + ".csv"
  CopyFile(coeffs_file, backup_coeffs)
  total_matrix = output_dir + "/modal_trips.mtx"
  
  if TypeOf(modal_trip_matrices) = "string" 
    then modal_trip_matrices = {modal_trip_matrices}

  // Create a table of modal matrix statistics
  model = RunMacro("Matrix Stats", modal_trip_matrices)
  model.group_by("core")
  model.summarize("Sum", "sum")
  model.rename("sum_Sum", "trips")
  model.write_csv(output_dir + "/model_trip_stats" + backup_suffix + ".csv")
  
  // Use the equivalency table if provided to create a 'target' column
  if equiv_file <> null then do
    equiv = CreateObject("df", equiv_file)
    model.left_join(equiv, "core")
  end else do
    model.mutate("target", model.tbl.core)
  end
  
  // Summarize the model trips by target column
  model.group_by("target")
  collapsed = model.summarize("trips", "sum", "false")
  collapsed.filter("target <> null")
  collapsed.separate("target", {"purp", "market", "mode"}, , "true")
  collapsed.unite({"purp", "market"}, "purpseg")
  collapsed.rename("sum_trips", "trips")
  
  // Scale targets. This will ensure that the target totals by purpose and
  // market match the model. (Trip conservation checks should be performed
  // outside MC calibration.)
  targets = CreateObject("df", target_file)
  targets.separate("target_name", {"purp", "market", "mode"}, , "true")
  targets.unite({"purp", "market"}, "purpseg")
  tsummary = targets.copy()
  tsummary.group_by("purpseg")
  tsummary.summarize("target", "sum")
  targets.left_join(tsummary, "purpseg")
  targets.mutate("pct", targets.tbl.target / targets.tbl.sum_target)
  csummary = collapsed.copy()
  csummary.group_by("purpseg")
  csummary.summarize("trips", "sum")
  csummary.rename("sum_trips", "trips")
  targets.left_join(csummary, "purpseg")
  targets.mutate("scaled_target", targets.tbl.pct * targets.tbl.trips)
  targets.select({"target_name", "target", "sum_target", "pct", "scaled_target"})
  collapsed.select({"target", "trips"})
  collapsed.rename("trips", "model_trips")
  
  // Join model trips to targets to calculate adjustments and %rmse.
  targets.left_join(collapsed, "target_name", "target")
  observed = targets.tbl.scaled_target
  estimated = targets.tbl.model_trips
  {rmse, prmse} = RunMacro(
    "Calculate Vector RMSE", observed, estimated)
  adj = Log(observed / estimated) * damp_factor
  adj = if observed = 0
    then if estimated > 0
      then -.1
      else 0
    else adj
  adj = if estimated = 0
    then if observed > 0
      then .1
      else 0
    else adj
  targets.mutate("adjustment", adj)
  if check_calib then do
    targets.view('MC calibration check')
    DestroyProgressBar()
    ShowMessage('MC calibration checked only.\nNo parameters have been adjusted')
    return()
  end
  
  targets.write_csv(output_dir + "/adjustment_calc" + backup_suffix + ".csv")
  targets.left_join(equiv, "target_name", "target")
  targets.select({"core", "adjustment"})
  
  // Join adjustment to coeffs table and check for non-numerics
  coeffs = CreateObject("df", coeffs_file)
  coeffs.unite({"purpose", "segment", "term"}, "core")
  coeffs.left_join(targets, "core")
  if coeffs.tbl.value.type = "string" then do
    targets.view("targets")
    coeffs.view("coeffs")
    Throw(
      "The previous iteration wrote out non-numeric values.\n" +
      "Check the targets and coeffs tables to look for odd values."
    )
  end
  // If the adjustment would lead to a zero for an ASC that isn't, change
  // it by a small amount. This prevents it from becoming 0 and being seen as
  // a reference alternative on the next iteration.
  coeffs.tbl.adjustment = if coeffs.tbl.value + coeffs.tbl.adjustment = 0
    then coeffs.tbl.adjustment - .001
    else coeffs.tbl.adjustment
  // Adjust the coefficients
  new_value = if (coeffs.tbl.section = "asc" and coeffs.tbl.adjustment <> null
    and coeffs.tbl.value <> 0 and coeffs.tbl.value <> -999)
    then coeffs.tbl.value + coeffs.tbl.adjustment
    else coeffs.tbl.value
  coeffs.mutate("value", new_value)
  coeffs.remove({"core", "adjustment"})
  coeffs.write_csv(coeffs_file)
  
  DestroyProgressBar()
  return(prmse)
EndMacro

/*dontdoc
Helper function. DC and MC macros support an optional period column in their
parameter files. Rather than repeat the filtering code in each, it is stored
here.

Returns
  If `param_file` has a 'period' column, and if `period <> null`, then the
  returned data frame is filtered to the given period. Otherwise, the full
  data frame is returned.
*/

Macro "Filter Parameter File by Period" (param_file, expr_vars, period)
  
  df = CreateObject("df")
  df.read_csv(param_file, , expr_vars)
  colnames = df.colnames()
  for i = 1 to colnames.length do
    colname = colnames[i]

    if CompareStrings(colname, "period", ) then do
      if period = null 
        then Throw(
          "'param_file' has a period column, but 'period' not provided"
        )
      df.filter(colname + " = '" + period + "'")
      if df.nrow() = 0 
        then Throw(
          "'" + period + "' not found in the period column of 'param_file'"
        )
      df.remove(colname)
    end
  end
  
  return(df)
EndMacro
