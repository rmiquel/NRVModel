/*
This rsc file contains the external macros - both EE and IEEI.

Macro "Externals" controls all other macros in this file.
*/

Macro "Through Trips"
  RunMacro("Convert EE CSV to MTX")
  RunMacro("Calculate EE IPF Marginals")
  RunMacro("IPF EE Seed Table")
  RunMacro("EE Symmetry")
  RunMacro("EE TOD")
EndMacro

/*
Convert the base year table to mtx.
The matrix is created based on the external stations in the node layer.
This ensures accurate matrix dimensions.  This matrix is then udpated
with the ee CSV file, which is created by ExternalDevelopment.rmd.
*/

Macro "Convert EE CSV to MTX"
  UpdateProgressBar("Convert EE CSV to MTX", 0)

  // Create EE table from node layer
  {nlayer, llayer} = GetDBLayers(Args.hwy_dbd)
  map = RunMacro("G30 new map", Args.hwy_dbd)
  SetLayer(nlayer)
  qry = "Select * where External = 1"
  n = SelectByQuery("ext", "Several", qry)
  if n = 0 then Throw("No external stations found")
  opts = null
  mtx_file = Args.[Scenario Folder] + "/inputs/external/base_ee_table.mtx"
  opts.[File Name] = mtx_file
  opts.Label = "EE Matrix"
  opts.Tables = {"trips"}
  row_spec = {
    nlayer + "|ext",
    nlayer + ".ID",
    "externals"
  }
  mtx = CreateMatrix(row_spec, , opts)

  // Update the EE matrix with the csv table
  csv = Args.[Scenario Folder] + "/inputs/external/base_ee_table.csv"
  view = OpenTable("csv", "CSV", {csv})
  opts = null
  opts.[Missing Is Zero] = "Yes"
  UpdateMatrixFromView(
    mtx,
    view + "|",
    "FROM",
    "TO",
    ,
    {view + ".trips"},
    "Replace",
    opts
  )

  // The [Missing is Zero] option is not working.
  // Manually change nulls to 0.
  a_corenames = GetMatrixCoreNames(mtx)
  {ri, ci} = GetMatrixIndex(mtx)
  cur = CreateMatrixCurrency(mtx, a_corenames[1], ri, ci, )
  cur := if (cur = null) then 0 else cur

  RunMacro("Close All")
EndMacro

/*
Uses the external_awdt.csv table to create a formula field
containing the EE trips at each external station.
*/

Macro "Calculate EE IPF Marginals"
  UpdateProgressBar("Calculate EE IPF Marginals", 0)
  shared margTbl

  margTbl = Args.[Scenario Folder] + "/inputs/external/external_awdt.csv"
  margTbl = OpenTable("margTbl", "CSV", {margTbl, })

  opts = null
  opts.Type = "Integer"
  CreateExpression(
    margTbl,
    "EEmarg",
    "(EERatio * AWDT" + String(MODELARGS.ext_awdt_year) + ") / 2",
  )

EndMacro

/*
Use the marginals calculated to IPF the base-year seed table.
*/

Macro "IPF EE Seed Table"
  UpdateProgressBar("IPF EE Seed Table", 0)
  shared margTbl

  // Open the input EE mtx (it is not modified)
  mtx_file = Args.[Scenario Folder] + "/inputs/external/base_ee_table.mtx"
  mtx = OpenMatrix(mtx_file, )
  a_corenames = GetMatrixCoreNames(mtx)
  {ri, ci} = GetMatrixIndex(mtx)
  cur = CreateMatrixCurrency(mtx, a_corenames[1], ri, ci, )

  // IPF to current year
  Opts = null
  Opts.Input.[Base Matrix Currency] = {mtx_file, a_corenames[1], ri, ci}
  Opts.Input.[PA View Set] = {
    Args.[Scenario Folder] + "/inputs/external/external_awdt.csv", margTbl, ,
  }
  Opts.Global.[Constraint Type] = "Doubly"
  Opts.Global.Iterations = 300
  Opts.Global.Convergence = 0.001
  Opts.Field.[Core Names Used] = a_corenames
  Opts.Field.[P Core Fields] = {margTbl + ".EEmarg"}
  Opts.Field.[A Core Fields] = {margTbl + ".EEmarg"}
  Opts.Output.[Output Matrix].Label = "EE Trips Matrix"
  Opts.Output.[Output Matrix].[File Name] = Args.ee_mtx
  ok = RunMacro("TCB Run Procedure", "Growth Factor", Opts, &Ret)
  if !ok then Throw("EE IPF failed")

  // Check each core for errors not captured automatically by TC
  for c = 1 to Opts.Field.[Core Names Used].length do
    // e.g., if the "Fail0" option in the second element of the
    // Ret array is greater than zero, it failed
    if Ret[2].("Fail" + String(c-1)) > 0 then do
      errorcore = Opts.Field.[Core Names Used][c]
      Throw(
        "EE IPF failed. Core: " + errorcore
        )
    end
  end

  RunMacro("Close All")
EndMacro

/*
This macro enforces symmetry on the EE matrix.
*/

Macro "EE Symmetry"
  UpdateProgressBar("EE Symmetry", 0)

  // Open the IPFd EE mtx
  mtx = OpenMatrix(Args.ee_mtx, )
  a_corenames = GetMatrixCoreNames(mtx)
  {ri, ci} = GetMatrixIndex(mtx)
  Cur = CreateMatrixCurrencies(mtx, ri, ci, )

  // Create a transposed EE matrix
  tmtx = GetTempFileName(".mtx")
  opts = null
  opts.[File Name] = tmtx
  opts.Label = transposed
  tmtx = TransposeMatrix(mtx, opts)

  // Create transposed currencies
  {tri, tci} = GetMatrixIndex(tmtx)
  tcur = CreateMatrixCurrencies(tmtx, tri, tci, )

  a_corename = GetMatrixCoreNames(mtx)
  // for each core
  for c = 1 to a_corename.length do
      corename = a_corename[c]

      // Add together and divide by two to ensure symmetry
      Cur.(corename) := (Cur.(corename) + tcur.(corename))/2
  end
EndMacro

/*
Use the HBO time factors to split up EE matrix cores

Depends
  gplyr
*/

Macro "EE TOD"
  UpdateProgressBar("EE TOD", 0)

  scen_dir = Args.[Scenario Folder]
  param_file = scen_dir + "/inputs/tod/time_of_day_factors.csv"
  ee_mtx = scen_dir + "/outputs/external/EETable.mtx"

  // Open tod parameter file and get factors
  df = CreateObject("df")
  df.read_csv(param_file)
  df.filter("from_field = 'HBO_ihvs'")
  df.select({"Period", "from_factor"})

  // Open ee matrix
  mtx = OpenMatrix(ee_mtx, )
  {ri, ci} = GetMatrixIndex(mtx)
  a_cores = GetMatrixCoreNames(mtx)
  daily_core = a_cores[1]

  // loop for each period
  for p = 1 to df.nrow() do
    period = df.tbl.Period[p]
    factor = df.tbl.from_factor[p]

    // Add core and create currencies
    new_core = "EE_" + period
    if ArrayPosition(a_cores, {new_core}, ) = 0 then
      AddMatrixCore(mtx, new_core)
    a_curs = CreateMatrixCurrencies(mtx, ri, ci, )

    // Calculate new core
    a_curs.(new_core) := nz(a_curs.(new_core)) + a_curs.(daily_core) * factor
  end


EndMacro
