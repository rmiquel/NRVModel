/*
Mode choice is broken into two steps:

Calc Mode Shares (this script file)
  Calculates utilities, probabilities, and logsums for every ij pair using
  skim and zonal data.  This makes the logsum available to the
  distribution model.

Apply Mode Shares (different script file)
  Applies to the probabilities calculated in MC1 to the trip matrices output
  by the distribution model.
*/

Macro "Calc Mode Shares" (Args)
  RunMacro("Update MC Variables File")
  RunMacro("Run NLM MC")
EndMacro

/*
The master variables file contains data for all networks (.net and .tnw). Some
transit modes may not be present in a scenario (e.g. BRT or CR). This macro uses
the .net and .tnw files to determine which are present. Bike and walk modes
are included by default (no networks created separately for them).
*/

Macro "Update MC Variables File" (Args)
  UpdateProgressBar("Update MC Variables File", 0)

  scen_dir = Args.[Scenario Folder]
  period = MODELARGS.period
  net_dir = scen_dir + "/outputs/networks"
  var_tbl = scen_dir + "/inputs/mode/mc_variables.csv"
  out_tbl = scen_dir + "/outputs/mode/mc_variables_updated.csv"

  query = "Select * where alternative = 'bike' or alternative = 'walk'"

  a_tnws = RunMacro ("Catalog Files", net_dir, {"net", "tnw"})
  for tnw in a_tnws do

    {drive, folder, name, ext} = SplitPath(tnw)
    name = Substitute(name, "_" + period, "", )
    query = query + " or alternative = '" + name + "'"
  end

  df = CreateObject("df")
  df.read_csv(var_tbl)
  df.filter(query)
  df.write_csv(out_tbl)
EndMacro

/*
This MC macro uses the NestedLogitEngine in TC.

The object name is "NLM.Model".  You can use GetClassMethodNames("NLM.Model") to
see all the methods available, but there is no help for them.  Caliper has
been willing to help explain some of them and how to use them.
*/

Macro "Run NLM MC" (Args)
  UpdateProgressBar("Run NLM MC", 0)

  scen_dir = Args.[Scenario Folder]
  se_bin = Args.se_bin
  period = MODELARGS.period
  skim_dir = scen_dir + "/outputs/skims"
  mc_dir = scen_dir + "/inputs/mode"
  template_mdl = mc_dir + "/template_mc.mdl"
  coeffs_file = mc_dir + "/mc_coefficients.csv"
  vars_file = scen_dir + "/outputs/mode/mc_variables_updated.csv"
  output_dir = scen_dir + "/outputs/mode"

  opts = null
  opts.tables.zone_tbl.file = se_bin
  opts.tables.zone_tbl.set_name = "internal"
  opts.tables.zone_tbl.query = "Select * where InternalZone = 'Internal'"
  opts.template_mdl = template_mdl
  opts.coeffs_file = coeffs_file
  opts.vars_file = vars_file
  opts.output_matrix = output_dir + "/_mc_resident_" + period + ".mtx"
  opts.period = period
  opts.matrices.hwy_skim.file = skim_dir + "/highway/_hwy_skim_" + period + ".mtx"
  opts.matrices.hwy_skim.index = "internal"
  opts.matrices.trn_skim.file = skim_dir + "/transit/_trn_skim_" + period + ".mtx"
  opts.matrices.trn_skim.index = "internal"
  opts.utility_scaling = "By Theta Product"
  RunMacro("GT - Mode Choice NLM", opts)
EndMacro
