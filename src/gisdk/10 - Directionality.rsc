/*
This script implements various macros that convert trip tables from
mode choice into the format needed by highway assignment. Dito for
transit assignment if implemented in the future.
*/

/*

*/

Macro "Directionality" (Args)
  RunMacro("Split Highway and Non-Highway Trips", Args)
  RunMacro("Apply Directionality", Args)
  RunMacro("Vehicle Occupancy", Args)
  RunMacro("Include Through Trips", Args)
EndMacro

/*

*/

Macro "Split Highway and Non-Highway Trips" (Args)
  UpdateProgressBar("Dir - Purpose Conversion", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period

  // Create the highway trip table
  opts = null
  opts.from_mtx = scen_dir + "/outputs/mode/_mc_modal_trips_" + period + ".mtx"
  opts.to_mtx = scen_dir + "/outputs/directionality/pa_person_hwy_trips_" +
    period + ".mtx"
  opts.to_mtx_label = "pa person hwy trips " + period
  opts.equiv_tbl = scen_dir + "/inputs/directionality/hwy_trip_definition.csv"
  RunMacro("Matrix Crosswalk", opts)

  // Create the transit trip table
  opts = null
  opts.from_mtx = scen_dir + "/outputs/mode/_mc_modal_trips_" + period + ".mtx"
  opts.to_mtx = scen_dir + "/outputs/directionality/pa_person_transit_trips_" +
    period + ".mtx"
  opts.equiv_tbl = scen_dir + "/inputs/directionality/transit_trip_definition_filtered.csv"
  opts.to_mtx_label = "pa person transit trips " + period
  RunMacro("Matrix Crosswalk", opts)
  
  // Create the non-motorized trip table
  opts = null
  opts.from_mtx = scen_dir + "/outputs/mode/_mc_modal_trips_" + period + ".mtx"
  opts.to_mtx = scen_dir + "/outputs/directionality/pa_person_nonmotorized_trips_" +
    period + ".mtx"
  opts.equiv_tbl = scen_dir + "/inputs/directionality/nonmotorized_trip_definition.csv"
  opts.to_mtx_label = "pa person non-motorized trips " + period
  RunMacro("Matrix Crosswalk", opts)
EndMacro

/*
Converts PA person trips to OD person trips.
Directionality factors are applied by purpose and tod.

Matrix core names from mode choice must be in the form of:
"Purpose_Mode"
*/

Macro "Apply Directionality" (Args)
  UpdateProgressBar("Apply Directionality", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  param_file = scen_dir + "/inputs/directionality/directionality_factors.csv"
  from_mtx = scen_dir + "/outputs/directionality/pa_person_hwy_trips_" +
    period + ".mtx"
  to_mtx = scen_dir + "/outputs/directionality/od_person_hwy_trips_" +
    period + ".mtx"

  // Read parameter file
  params = RunMacro("Read Parameter File", param_file)
  num_purposes = params.length

  // Copy matrix and create currencies
  CopyFile(from_mtx, to_mtx)
  mtx = OpenMatrix(to_mtx, )
  RenameMatrix(mtx, "od person hwy trips " + period)
  {ri, ci} = GetMatrixIndex(mtx)
  a_curs = CreateMatrixCurrencies(mtx, ri, ci, )
  a_corenames = GetMatrixCoreNames(mtx)

  // Create a temp transposed matrix and create currencies
  opts = null
  opts.[File Name] = GetTempFileName(".mtx")
  t_mtx = TransposeMatrix(mtx, opts)
  {t_ri, t_ci} = GetMatrixIndex(t_mtx)
  a_t_curs = CreateMatrixCurrencies(t_mtx, t_ri, t_ci, )

  for c = 1 to a_corenames.length do
    corename = a_corenames[c]

    // Determine the purpose of the current core based on it's name
    array = ParseString(corename, "_")
    purp = array[1]

    pa_fac = params.(purp).(period)
    a_curs.(corename) := a_curs.(corename) * pa_fac +
      a_t_curs.(corename) * (1 - pa_fac)
  end
EndMacro

/*
For highway modes (auto, drive alone, shared ride, etc.), converts
person trips in to vehicle trips by applying occupancy factors. The
factors are specified in a parameter table by purpose, mode, and tod.
*/

Macro "Vehicle Occupancy" (Args)
  UpdateProgressBar("Vehicle Occupancy", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  from_mtx = scen_dir + "/outputs/directionality/od_person_hwy_trips_" +
    period + ".mtx"
  to_mtx = scen_dir + "/outputs/directionality/od_vehicle_hwy_trips_" +
    period + ".mtx"
  param_file = scen_dir + "/inputs/directionality/veh_occ_factors.csv"

  // Read parameter file
  params = RunMacro("Read Parameter File", param_file)
  num_purposes = params.length

  // Open the matrix and create currencies
  CopyFile(from_mtx, to_mtx)
  mtx = OpenMatrix(to_mtx, )
  RenameMatrix(mtx, "od vehicle hwy trips " + period)
  {ri, ci} = GetMatrixIndex(mtx)
  a_curs = CreateMatrixCurrencies(mtx, ri, ci, )

  for p = 1 to num_purposes do
    purp = params[p][1]

    purp_params = params.(purp)
    num_segments = purp_params.length
    for s = 1 to num_segments do
      seg = purp_params[s][1]
      
      seg_params = purp_params.(seg)
      num_modes = seg_params.length
      for m = 1 to num_modes do
        mode = seg_params[m][1]

        occ_fac = params.(purp).(seg).(mode).(period)
        a_curs.(purp + "_" + seg + "_" + mode) := 
          a_curs.(purp + "_" + seg + "_" + mode) / occ_fac
      end
    end
  end
EndMacro

/*
Depening on the model, EE trips are either used as preloaded
assignment volumes or assigned along with all other classes.
This macro determines which method to use.

For Hickory, all trips are assigned together.
*/

Macro "Include Through Trips" (Args)
  UpdateProgressBar("Include Through Trips", 0)

  scen_dir = Args.[Scenario Folder]
  period = Args.period
  ee_mtx = scen_dir + "/outputs/external/EETable.mtx"
  v_mtx = scen_dir + "/outputs/directionality/od_vehicle_hwy_trips_" +
    period + ".mtx"


  // Open the ee matrix
  ee_mtx = OpenMatrix(ee_mtx, )
  {eri, eci} = GetMatrixIndex(ee_mtx)
  a_ee_curs = CreateMatrixCurrencies(ee_mtx, eri, eci, )

  // Open the OD vehicle trip matrix and add core
  v_mtx = OpenMatrix(v_mtx, )
  {vri, vci} = GetMatrixIndex(v_mtx)
  a_cores = GetMatrixCoreNames(v_mtx)
  if ArrayPosition(a_cores, {"EE"}, ) = 0 then
    AddMatrixCore(v_mtx, "EE")
  a_v_curs = CreateMatrixCurrencies(v_mtx, vri, vci, )
  a_v_curs.EE := 0

  // Update EE section of core with EE trips
  MergeMatrixElements(a_v_curs.EE, {a_ee_curs.("EE_" + period)}, , , )
EndMacro
