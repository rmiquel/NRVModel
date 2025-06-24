/*
"Generation" is the main macro called by the GUI.  It converts
the global GUI variables (MODELARGS) into variables used by the
other macros.

Resident generation is handled by calls to the ResidentGeneration
library script.  So are CV trips.

IEEI trips are handled by macros in this script file.
*/

Macro "Generation" (Args)
  RunMacro("Create HH Marginals", Args)
  RunMacro("Create HH Joint Distribution", Args)
  RunMacro("Resident Trip Production", Args)
  RunMacro("Resident Attractions", Args)
  RunMacro("University Productions/Attractions", Args)
  RunMacro("CV Productions/Attractions", Args)
  RunMacro("IEEI Productions", Args)
  RunMacro("IEEI Attractions", Args)
  RunMacro("Balance Ps and As", Args)
  RunMacro("Close All")
  return(1)
EndMacro

/*
Creates the marginal HH distributions for each TAZ.
*/

Macro "Create HH Marginals" (Args)
  UpdateProgressBar("Create HH Marginals", 0)

  scen_dir = Args.[Scenario Folder]
  param_dir = scen_dir + "/inputs/generation"
  se_bin = Args.se_bin
  
  // Calculate the average/ratio fields that will be used to determine
  // marginals.
  opts = null
  opts.table = se_bin
  opts.param_file = param_dir + "/disagg_zonal_averages.csv"
  RunMacro("Calculate Fields", opts)

  opts = null
  opts.se_bin = se_bin
  opts.hh_field = "Households"
  opts.mtables.avg_size = param_dir + "/disagg_hh_size.csv"
  opts.mtables.avg_work = param_dir + "/disagg_hh_worker.csv"
  opts.mtables.avg_veh = param_dir + "/disagg_hh_vehicle.csv"
  opts.mtables.inc_ratio = param_dir + "/disagg_hh_income.csv"
  RunMacro("HH Marginal Creation", opts)

EndMacro

/*
Create the joint HH distribution for each TAZ
*/

Macro "Create HH Joint Distribution" (Args)
  UpdateProgressBar("Create HH Joint Distribution", 0)

  //Copy se_bin to se_csv for R  06_17_2025
  scen_dir = Args.[Scenario Folder]
  se_trans = OpenTable("SE", "FFB", {Args.se_bin, })
  ExportView("SE|", "CSV", scen_dir + "\\inputs\\sedata\\SE_Scenario.csv", ,{{"CSV Header", "True"}})
//  CopyTableFiles("SE", null, null, null, scen_dir + "\\inputs\\sedata\\SE_Scenario.csv", null)
  se_trans = null

  opts = null
  opts.se_bin = Args.se_bin
  opts.se_csv = scen_dir + "\\inputs\\sedata\\SE_Scenario.csv"
  rdir = Args.[Scenario Folder] + "/../../src/R"
  opts.rscriptexe = rdir + "/R-3.5.0/bin/Rscript.exe"
  gdir = Args.[Scenario Folder] + "/../../src/gisdk"
  opts.rscript = gdir + "/gisdk_tools/Generation.R"
  param_dir = Args.[Scenario Folder] + "/inputs/generation"
  opts.seed_tbl = param_dir + "/disagg_hh_joint.csv"
  opts.output_dir = Args.[Scenario Folder] + "/outputs/generation"
  RunMacro("HH Joint Distribution", opts)
EndMacro

/*
Resident Trip Productions
Use the cross-classification model
*/

Macro "Resident Trip Production" (Args)
  UpdateProgressBar("Resident Trip Production", 0)

  scen_dir = Args.[Scenario Folder]
  se_bin = Args.se_bin

  // Use GT to create work and nonwork trip data frames
  opts.param_work = Args.[Scenario Folder] +
    "/inputs/generation/prod_rates_work.csv"
  opts.param_nonwork = Args.[Scenario Folder] +
    "/inputs/generation/prod_rates_nonwork.csv"
  opts.disagg_file = scen_dir + "/outputs/generation/HHDisaggregation.csv"
  opts.return_dfs = "True"
  {work, nonwork} = RunMacro("Cross-Classification Method", opts)

  // Define work and non work market segments
  inc = work.tbl.inc
  wrk = work.tbl.disag_wrk
  veh = work.tbl.disag_veh
  v_market = Vector(work.nrow(), "String")
  v_market = if veh = 0 then "v0"
    else if inc = "L" & veh < wrk then "ilvi"
    else if inc = "L" & veh >= wrk then "ilvs"
    else if inc <> "L" & veh < wrk then "ihvi"
    else if inc <> "L" & veh >= wrk then "ihvs"
  work.mutate("market", v_market)
  work.select({"geo_taz", "purpose", "market", "trips"})
  inc = nonwork.tbl.inc
  siz = nonwork.tbl.disag_siz
  veh = nonwork.tbl.disag_veh
  v_market = Vector(nonwork.nrow(), "String")
  v_market = if veh = 0 then "v0"
    else if inc = "L" & veh < siz then "ilvi"
    else if inc = "L" & veh >= siz then "ilvs"
    else if inc <> "L" & veh < siz then "ihvi"
    else if inc <> "L" & veh >= siz then "ihvs"
  nonwork.mutate("market", v_market)
  nonwork.select({"geo_taz", "purpose", "market", "trips"})

  // Collapse trips by purpose and market as appropriate
  df = work.copy()
  df.bind_rows(nonwork)
  with_markets = {"HBW", "HBO"}
  markets = df.copy()
  no_markets = df.copy()
  for purpose in with_markets do
    if purpose = with_markets[1] then do
      markets.filter("purpose = '" + purpose + "'")
    end else do
      temp = df.copy()
      temp.filter("purpose = '" + purpose + "'")
      markets.bind_rows(temp)
    end
    no_markets.filter("purpose <> '" + purpose + "'")
  end
  markets.mutate("purpose", markets.tbl.purpose + "_" + markets.tbl.market)
  markets.group_by({"geo_taz", "purpose"})
  markets.summarize("trips", "sum")
  no_markets.group_by({"geo_taz", "purpose"})
  no_markets.summarize("trips", "sum")

  markets.bind_rows(no_markets)
  markets.rename("geo_taz", "TAZ")
  markets.spread("purpose", "sum_trips")
  markets.mutate(
    "HBW_tot",
    markets.tbl.HBW_v0 +
    markets.tbl.HBW_ilvi +
    markets.tbl.HBW_ilvs +
    markets.tbl.HBW_ihvi +
    markets.tbl.HBW_ihvs
  )
  markets.mutate(
    "HBO_tot",
    markets.tbl.HBO_v0 +
    markets.tbl.HBO_ilvi +
    markets.tbl.HBO_ilvs +
    markets.tbl.HBO_ihvi +
    markets.tbl.HBO_ihvs
  )
  csv_file = scen_dir + "/outputs/generation/productions.csv"
  markets.write_csv(csv_file)
  RunMacro ("Join Table To Layer", se_bin, "ID", csv_file, "TAZ")
EndMacro

/*
Resident Trip Attractions
*/

Macro "Resident Attractions" (Args)
  UpdateProgressBar("Resident Attractions", 0)

  opts = null
  opts.table = Args.[Scenario Folder] + "/outputs/sedata/ScenarioSE.bin"
  opts.param_file = Args.[Scenario Folder] + "/inputs/generation/attr_rates.csv"
  RunMacro("Calculate Fields - Simple", opts)
EndMacro

/*

*/

Macro "University Productions/Attractions" (Args)
  UpdateProgressBar("University Productions/Attractions", 0)
  
  se_bin = Args.se_bin
  se_csv = scen_dir + "\\inputs\\sedata\\SE_Scenario.csv"
  scen_dir = Args.[Scenario Folder]
  
  // Generate Ps and As
  opts = null
  opts.table = Args.se_bin
//  opts.table = se_csv
  opts.param_file = scen_dir + "/inputs/university/univ_generation.csv"
  RunMacro("Calculate Fields", opts)
EndMacro

/*
CV productions
Attractions are the same as productions
*/

Macro "CV Productions/Attractions" (Args)
  UpdateProgressBar("CV Productions/Attractions", 0)

  opts = null
  opts.table = Args.se_bin
  opts.param_file = Args.[Scenario Folder] + "/inputs/cv/cv_generation.csv"
  RunMacro("Calculate Fields - Simple", opts)
EndMacro

/*
Predicts IEEI productions
*/

Macro "IEEI Productions" (Args)
  UpdateProgressBar("IEEI Productions", 0)

  scen_dir = Args.[Scenario Folder]
  se_bin = Args.se_bin
  year = Args.ext_awdt_year

  // Open se table and add fields
  se_tbl = OpenTable("se", "FFB", {se_bin})
  a_fields = {
    {"AWDT", "Real", 10, 2,,,,"AWDT at external station"},
    {"IEEI", "Real", 10, 2,,,,
    "IEEI productions|AWDT at station - EE trips"}
  }
  RunMacro("TCB Add View Fields", {se_tbl, a_fields})

  /*
  Calculate IEEI productions by subtracting the total EE volume
  from the AWDT at the station.
  */

  // Get AWDT and set into se table
  awdtTbl = scen_dir + "/inputs/external/external_awdt.csv"
  awdtTbl = OpenTable("awdt", "CSV", {awdtTbl})
  opts = null
  opts.[Sort Order] = {{"ExtID", "Ascending"}}
  v_awdt = GetDataVector(awdtTbl + "|", "AWDT" + String(year), opts)
  SetView(se_tbl)
  qry = "Select * where InternalZone = 'External'"
  SelectByQuery("ext", "Several", qry)
  opts = null
  opts.[Sort Order] = {{"ID", "Ascending"}}
  SetDataVector(se_tbl + "|ext", "AWDT", v_awdt, opts)

  // Get EE trips from through trip matrix marginal
  mtx_file = scen_dir + "/outputs/external/EETable.mtx"
  mtx = OpenMatrix(mtx_file, )
  a_corenames = GetMatrixCoreNames(mtx)
  {ri, ci} = GetMatrixIndex(mtx)
  mc = CreateMatrixCurrency(mtx, a_corenames[1], ri, ci, )
  v_ee = A2V(GetMatrixMarginals(mc, "sum", "row"))
  v_ee = v_ee * 2

  // Take the difference and put into se table
  v_ieeip = max(v_awdt - v_ee, 0)
  SetView(se_tbl)
  qry = "Select * where InternalZone = 'External'"
  SelectByQuery("ext", "Several", qry)
  opts = null
  opts.[Sort Order] = {{"ID", "Ascending"}}
  SetDataVector(se_tbl + "|ext", "IEEI", v_ieeip, opts)

  RunMacro("Close All")
EndMacro

/*
IEEI trip attractions
*/

Macro "IEEI Attractions" (Args)
  UpdateProgressBar("IEEI Attractions", 0)

  opts = null
  opts.table = Args.se_bin
  opts.param_file = Args.[Scenario Folder] + "/inputs/external/ieei_generation.csv"
  RunMacro("Calculate Fields - Simple", opts)
EndMacro

/*
Calls the balance macro from the generation library and
writes out a report of the balance factors applied.
*/

Macro "Balance Ps and As" (Args)
  UpdateProgressBar("Balance Ps and As", 0)

  // Call the balance macro
  opts = null
  opts.tbl = Args.se_bin
  opts.balance_tbl = Args.[Scenario Folder] + "/inputs/generation/balance.csv"
  {tbl, unbalanced} = RunMacro("Balance", opts)

  // Write out report and unbalanced table
  df = CreateObject("df", tbl)
  df.write_csv(Args.[Scenario Folder] + "/outputs/generation/balance_report.csv")
  df = CreateObject("df", unbalanced)
  df.write_csv(Args.[Scenario Folder] + "/outputs/generation/unbalanced_pa.csv")
EndMacro
