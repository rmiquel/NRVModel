/*

*/

Macro "Distribution" (Args)
    for period in Args.Periods do
      Args.period = period
      RunMacro("Convert to Distribution Purposes", Args)
      RunMacro("Add Inter-County Skim Core", Args)
      RunMacro("Resident DC", Args)
      RunMacro("HBU Gravity", Args)
      RunMacro("Commercial Gravity", Args)
      RunMacro("IEEI Gravity", Args)
      RunMacro("NHBNR", Args)
      RunMacro("Aggregate Matrices", Args)
    end
    return(1)
EndMacro

/*
This macro converts trip fields from a previous step
into those needed by distribution.  For example, a number of
purposes might be collapsed into HBO. The crosswalk is controlled
by an equivalency table.
*/

Macro "Convert to Distribution Purposes" (Args)
  UpdateProgressBar(Args.period + ": Convert to Distribution Purposes", 0)

  period = Args.period
  se_bin = Args.se_bin
  param_file = Args.[Scenario Folder] + "/inputs/distribution/d_purp_conversion.csv"

  opts = null
  opts.table = se_bin
  opts.param_file = param_file
  opts.expr_vars.period = period
  RunMacro("Calculate Fields - Simple", opts)

  RunMacro("Close All")
EndMacro

/*
For school trips, the surveyed showed that trips did not cross county
lines. This intra-county core is used to penalize cross-county school
trips in distribution.
*/

Macro "Add Inter-County Skim Core" (Args)
  UpdateProgressBar(Args.period + ": Add Inter-County Skim Core", 0)

  period = Args.period
  scen_dir = Args.[Scenario Folder]
  taz_dbd = Args.taz_dbd

  skim_file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"

  // Open the skim_file and add a new core of ones
  mtx = OpenMatrix(skim_file, )
  a_corenames = GetMatrixCoreNames(mtx)
  new_core = "intercounty"
  RunMacro("Add Cores", mtx, new_core, 1)

  // Add the TAZ layer and get list of counties
  {tlyr} = GetDBLayers(taz_dbd)
  AddLayerToWorkspace(tlyr, taz_dbd, tlyr)
  county_field = "COUNTYFP10"
  v_counties = GetDataVector(tlyr + "|", county_field, )
  opts = null
  opts.Unique = "true"
  v_counties = SortVector(v_counties, opts)
  v_county_names = "County" + v_counties

  // For each county
  for c = 1 to v_counties.length do
    county = v_counties[c]
    county_name = v_county_names[c]

    // Select zones in that county
    SetLayer(tlyr)
    string = if TypeOf(county) = "string"
      then "'" + county + "'"
      else county
    qry = "Select * where " + county_field + " = " + string
    set = CreateSet("selection")
    SelectByQuery(set, "several", qry)

    // Create a matrix index
    a_names = GetMatrixIndexNames(mtx)
    a_names = a_names[1] + a_names[2]
    if ArrayPosition(a_names, {county_name}, ) <> 0
      then DeleteMatrixIndex(mtx, county_name)
    idx = CreateMatrixIndex(
      county_name, mtx, "Both", tlyr + "|" + set, "ID", "ID"
    )

    // Fill a currency from and to that index with 1's
    mc = CreateMatrixCurrency(mtx, new_core, idx, idx, )
    mc := 0
  end

  RunMacro("Close All")
EndMacro

/*
Prepares arguments for the "Destination Choice" macro
in the Distribution.rsc library.
*/

Macro "Resident DC" (Args)
  UpdateProgressBar(Args.period + ": Resident DC", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  se_bin = Args.se_bin

  opts = null
  opts.period = period
  opts.param_file = scen_dir + "/inputs/distribution/dc_parameters.csv"
  opts.vars_file = scen_dir + "/inputs/distribution/dc_variables.csv"
  opts.output_matrix = scen_dir + "/outputs/distribution/trips_resident_" + period + ".mtx"
  opts.template_dcm = scen_dir + "/inputs/distribution/template.dcm"
  opts.tables.zone_tbl.file = se_bin
  opts.tables.zone_tbl.set_name = "internal"
  opts.tables.zone_tbl.query = "Select * where InternalZone = 'Internal'"
  opts.matrices.hwy_skim.file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
  opts.matrices.hwy_skim.index = "internal"
  opts.matrices.hwy_skim.dist_core = "da_dist"
  opts.matrices.mc_mtx.file = scen_dir + "/outputs/mode/_mc_resident_" + period + ".mtx"
  RunMacro("GT - Destination Choice NLM", opts)

  RunMacro("Close All")
EndMacro

/*
Prepares arguments for the "Gravity" macro
in the Distribution.rsc library.
*/

Macro "HBU Gravity" (Args)
  UpdateProgressBar(Args.period + ": HBU Gravity", 0)
  
  scen_dir = Args.[Scenario Folder]
  period = Args.period
  opts = null
  opts.scen_dir = scen_dir
  opts.se_bin = Args.se_bin
  opts.period = period
  opts.param_file = scen_dir + "/inputs/university/univ_distribution.csv"
  opts.skim_file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
  opts.output_matrix = scen_dir + "/outputs/distribution/trips_HBU_" + period + ".mtx"
  RunMacro("Gravity2", opts)

  RunMacro("Close All")
EndMacro

/*
Prepares arguments for the "Gravity" macro
in the Distribution.rsc library.
*/

Macro "Commercial Gravity" (Args)
  UpdateProgressBar(Args.period + ": Commercial Gravity", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  opts = null
  opts.scen_dir = scen_dir
  opts.se_bin = Args.se_bin
  opts.period = period
  opts.param_file = scen_dir + "/inputs/cv/cv_distribution.csv"
  opts.skim_file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
  opts.output_matrix = scen_dir + "/outputs/distribution/trips_CV_" + period + ".mtx"
  RunMacro("Gravity2", opts)

  RunMacro("Close All")
EndMacro

/*
Prepares arguments for the "Gravity" macro
in the Distribution.rsc library.
*/

Macro "IEEI Gravity" (Args)
  UpdateProgressBar(Args.period + ": IEEI Gravity", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  opts = null
  opts.scen_dir = scen_dir
  opts.se_bin = Args.se_bin
  opts.period = period
  opts.param_file = scen_dir + "/inputs/external/ieei_distribution.csv"
  opts.skim_file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
  opts.output_matrix = scen_dir + "/outputs/distribution/trips_IEEI_" + period + ".mtx"
  RunMacro("Gravity2", opts)

  RunMacro("Close All")
EndMacro

/*
Non-home-based non-resident trips
People traveling into the region make NHB trips like residents.
After the IEEI model distribution is complete, the model knows where the EI
travellers went and produces NHB trips in those zones.

This macro performs generation and distribution of the NHBNR trips.
*/

Macro "NHBNR" (Args)
  UpdateProgressBar(Args.period + ": NHBNR", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  se_bin = Args.se_bin

  // Collect vector of IEEI trip attractions
  mtx_file = scen_dir + "/outputs/distribution/trips_IEEI_" + period + ".mtx"
  mtx = OpenMatrix(mtx_file, )
  {ri, ci} = GetMatrixIndex(mtx)
  a_curs = CreateMatrixCurrencies(mtx, ri, ci, )
  opts = null
  opts.Marginal = "Column Sum"
  v_ieei_attr = GetMatrixVector(a_curs.IEEI, opts)
  a_curs = null
  mtx = null

  // Generate NHBNR productions
  // Use the IEEI directionality factor and the NHBNR generation factor
  dir_param = scen_dir + "/inputs/directionality/directionality_factors.csv"
  dir_param = RunMacro("Read Parameter File", dir_param)
  v_ei_attr = v_ieei_attr * dir_param.IEEI.(period)
  param = scen_dir + "/inputs/external/nhbnr_generation.csv"
  param = RunMacro("Read Parameter File", param)
  v_nhb_prod = v_ei_attr * (param.pctNHBNR / 100)

  // Use the resident NHB attractions for NHBNR
  vw_se = OpenTable("se", "FFB", {se_bin})
  v_nhb_attr = GetDataVector(vw_se + "|", "d_NHBa_all_" + period, )

  // Write this data to the se data table
  a_fields = {
    {"ieei_attr_" + period, "Real", 10, 2,,,,"IEEI attractions after distribution"},
    {"ei_attr_" + period, "Real", 10, 2,,,,"EI attractions (a percent of IEEI attrs)"},
    {"d_NHBNR_all_" + period, "Real", 10, 2,,,,"NHB productions from non residents"},
    {"d_NHBNRa_all_" + period, "Real", 10, 2,,,,"NHB attractions from non residents"}
  }
  RunMacro("Add Fields", vw_se, a_fields)
  SetDataVector(vw_se + "|", "ieei_attr_" + period, v_ieei_attr, )
  SetDataVector(vw_se + "|", "ei_attr_" + period, v_ei_attr, )
  SetDataVector(vw_se + "|", "d_NHBNR_all_" + period, v_nhb_prod, )
  SetDataVector(vw_se + "|", "d_NHBNRa_all_" + period, v_nhb_attr, )

  // Distribute the trips using the dc model and nhbnr param file
  // (same model and parameters as resident NHB)
  opts = null
  opts.period = period
  opts.param_file = scen_dir + "/inputs/external/nhbnr_dc_parameters.csv"
  opts.vars_file = scen_dir + "/inputs/external/nhbnr_dc_variables.csv"
  opts.output_matrix = scen_dir + "/outputs/distribution/trips_nhbnr_" + period + ".mtx"
  opts.template_dcm = scen_dir + "/inputs/distribution/template.dcm"
  opts.tables.zone_tbl.file = se_bin
  opts.tables.zone_tbl.set_name = "internal"
  opts.tables.zone_tbl.query = "Select * where InternalZone = 'Internal'"
  opts.matrices.hwy_skim.file = scen_dir + "/outputs/skims/highway/_hwy_skim_" + period + ".mtx"
  opts.matrices.hwy_skim.index = "internal"
  opts.matrices.hwy_skim.dist_core = "da_dist"
  opts.matrices.mc_mtx.file = scen_dir + "/outputs/mode/_mc_resident_" + period + ".mtx"
  RunMacro("GT - Destination Choice NLM", opts)

  RunMacro("Close All")
EndMacro

/*
Prepares arguments for the "Aggregate Distribution Matrices" macro
in the Distribution.rsc library.
*/

Macro "Aggregate Matrices" (Args)
  UpdateProgressBar(Args.period + ": Aggregate Matrices", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  dist_dir = scen_dir + "/outputs/distribution"

  opts.matrices = {
    dist_dir + "/trips_resident_" + period + ".mtx",
    dist_dir + "/trips_HBU_" + period + ".mtx",
    dist_dir + "/trips_CV_" + period + ".mtx",
    dist_dir + "/trips_IEEI_" + period + ".mtx",
    dist_dir + "/trips_nhbnr_" + period + ".mtx"
  }
  opts.output_matrix = dist_dir + "/_trips_" + period + ".mtx"
  opts.label = period + " distribution results"
  opts.delete_orig = "false"
  opts.core_prefix = 0
  RunMacro("GT - Combine Matrices", opts)
EndMacro
