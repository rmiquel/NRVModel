/*doc
Creates a simple .net file using just the length attribute. Many processes
require a simple network.

Inputs (all in a named array)
    * llyr
      * String - provide either llyr or hwy_dbd (not both)
      * Name of line layer to create network from. If provided, the macro assumes
        the layer is already in the workspace. Either 'llyr' or 'hwy_dbd' must
        be provided.
    * hwy_dbd
      * String - provide either llyr or hwy_dbd (not both)
      * Full path to the highway DBD file to create a network. If provided, the
        macro assumes that it is not already open in the workspace.Either 'llyr'
        or 'hwy_dbd' must be provided.
    * centroid_qry
      * Optional String
      * Query defining centroid set. If null, a centroid set will not be created.
        e.g. "FCLASS = 99"

Returns
  * net_file
    * String
    * Full path to the network file created by the network. Will be in the
      same directory as the hwy_dbd.
*/

Macro "Create Simple Highway Net" (MacroOpts)

  RunMacro("TCB Init")

  // Argument extraction
  llyr = MacroOpts.llyr
  llyr_provided = if (llyr <> null) then "true" else "false"
  hwy_dbd = MacroOpts.hwy_dbd
  hwy_dbd_provided = if (hwy_dbd <> null) then "true" else "false"
  centroid_qry = MacroOpts.centroid_qry

  // Argument checking
  if !llyr_provided and !hwy_dbd_provided = null then Throw(
    "Either 'llyr' or 'hwy_dbd' must be provided."
  )
  if llyr_provided and hwy_dbd_provided then Throw(
    "Provide only 'llyr' or 'hwy_dbd'. Not both."
  )

  // If llyr is provided, get the hwy_dbd
  // Get info about hwy_dbd
  if llyr_provided then do
    map = GetMap()
    SetLayer(llyr)
    if map = null then Throw("Simple Network: 'llyr' must be in current map")
    a_layers = GetMapLayers(map, "Line")
    in_map = if (ArrayPosition(a_layers, {llyr}, ) = 0) then "false" else "true"
    if !in_map then Throw("Simple Network: 'llyr' must be in the current map")

    hwy_dbd = GetLayerDB(llyr)
    {nlyr, } = GetDBLayers(hwy_dbd)
  // if hwy_dbd is provided, open it in a map
  end else do
    {nlyr, llyr} = GetDBLayers(hwy_dbd)
    map = RunMacro("G30 new map", hwy_dbd)
  end
  a_path = SplitPath(hwy_dbd)
  out_dir = RunMacro("Normalize Path", a_path[1] + a_path[2])

  // Create a simple network of the scenario highway layer
  SetLayer(llyr)
  set_name = null
  net_file = out_dir + "/simple.net"
  label = "Simple Network"
  link_fields = {{"Length", {llyr + ".Length", llyr + ".Length", , , "False"}}}
  node_fields = null
  opts = null
  opts.[Time Units] = "Minutes"
  opts.[Length Units] = "Miles"
  opts.[Link ID] = llyr + ".ID"
  opts.[Node ID] = nlyr + ".ID"
  opts.[Turn Penalties] = "Yes"
  nh = CreateNetwork(set_name, net_file, label, link_fields, node_fields, opts)

  // Add centroids to the network to prevent routes from passing through
  // Network Settings
  if centroid_qry <> null then do

    centroid_qry = RunMacro("Normalize Query", centroid_qry)

    opts = null
    opts.Input.Database = hwy_dbd
    opts.Input.Network = net_file
    opts.Input.[Centroids Set] = {
      hwy_dbd + "|" + nlyr, nlyr,
      "centroids", centroid_qry
    }
    ok = RunMacro("TCB Run Operation", "Highway Network Setting", opts, &Ret)
    if !ok then Throw(
      "Simple Network: Setting centroids failed"
    )
  end

  // Workspace clean up.
  // If this macro create the map, then close it.
  if hwy_dbd_provided then CloseMap(map)

  return(net_file)
EndMacro

/*doc
Creates a fully-specified highway network file (.net) using paramter files.
More complex version of "Create Simple Highway Network".

Inputs (all in a named array)

  * hwy_dbd
    * String
    * Path to the highway DBD file to create a .net file from
  * settings_tbl
    * String
    * Path to a csv with network settings (except field definitions). The file
      should be organized as shown below. The "default" network provides base
      settings for all networks. Other networks (like "da") can overwrite these
      settings with their own values.

      | Network | Parameter       | Value                             | Description                                                 |
      |---------|-----------------|-----------------------------------|-------------------------------------------------------------|
      | default | link_query      | Walk = 1 or Drive = 1             | The subset of links to be included in the .net file         |
      | default | out_file        | net.net                           | File name of output .net file.                              |
      | default | uturn_degrees   | 10                                | Tolerance that defines a u-turn. Default is 10.             |
      | default | through_degrees | 30                                | Tolerance that defines a through movement. Default is 30.   |
      | default | time_units      | Minutes                           |                                                             |
      | default | distance_units  | Miles                             |                                                             |
      | default | left_tp         | 0                                 | Penalty for left turns (in time_units). -1 means prohibited |
      | …       |                 |                                   |                                                             |
      | etc.    |                 |                                   |                                                             |
      | …       |                 |                                   |                                                             |
      | da      | link_query      | HOV = 0 & (Walk = 1 or Drive = 1) |                                                             |
      | da      | out_file        | da_{period}.net                   |                                                             |

  * fields_tbl
    * String
    * Path to a csv with the link and node fields to include in .net. AB/BA 
      field specs can include expression variables (e.g. {period}). These will
      be normalized using the 'expr_vars' array. For example:

      | layer | net_field_name | ab_field_name  | ba_field_name  |
      |-------|----------------|----------------|----------------|
      | link  | Length         | Length         | Length         |
      | link  | FFTime         | FFTime         | FFTime         |
      | link  | InitCongTime   | InitCongTime   | InitCongTime   |
      | link  | WalkTime       | WalkTime       | WalkTime       |
      | link  | Alpha          | Alpha          | Alpha          |
      | link  | Capacity       | ABAMCapE       | BAAMCapE       |

  * period
    * Time of day
  * expr_vars
    * Optional named array
    * Lookup for any {variables} in the parameters file. 'period' is included
      by default.
  * out_dir
    * String
    * Path to the output directory where the .net files will be created. The
      file name itself is specified in 'settings_tbl'.
  * label
    * Optional string
    * Network label. Default is "network".
*/

Macro "GT - Create Highway Networks" (MacroOpts)

  // Argument extraction
  hwy_dbd = MacroOpts.hwy_dbd
  settings_tbl = MacroOpts.settings_tbl
  fields_tbl = MacroOpts.fields_tbl
  period = MacroOpts.period
  expr_vars = MacroOpts.expr_vars
  out_dir = MacroOpts.out_dir
  label = MacroOpts.label

  // Argument checking
  if hwy_dbd = null then Throw("'hwy_dbd' not provided")
  if GetFileInfo(hwy_dbd) = null then Throw("'hwy_dbd' not found.")
  if settings_tbl = null then Throw("'settings_tbl' not provided")
  if GetFileInfo(settings_tbl) = null then Throw("'settings_tbl' not found.")
  if fields_tbl = null then Throw("'fields_tbl' not provided")
  if GetFileInfo(fields_tbl) = null then Throw("'fields_tbl' not found.")
  if period = null then Throw("'period' not provided")
  if out_dir = null then Throw("'out_dir' not provided")
  if label = null then label = "network"
  expr_vars.period = period

  all_settings = RunMacro("Read Parameter File", settings_tbl, expr_vars)

  // Read the fields table
  fields = CreateObject("df")
  fields.read_csv(fields_tbl, , expr_vars)
  link_fields = fields.copy()
  link_fields.filter("layer = 'link'")
  node_fields = fields.copy()
  node_fields.filter("layer = 'node'")

  for n = 1 to all_settings.length do
    net_name = all_settings[n][1]
    settings = all_settings.(net_name)

    // Set u-turn and through movement angles.
    // The default is:
    // U-turn: 10 degrees; Through: 30 degrees
    // This function is undocumented.
    if settings.through_degrees = null then settings.through_degrees = 30
    if settings.uturn_degrees = null then settings.uturn_degrees = 10
    SetTurnMovementTolerances(
      R2I(settings.uturn_degrees),
      R2I(settings.through_degrees)
    )

    // Open the link and node layers
    {nlyr, llyr} = GetDBLayers(hwy_dbd)
    llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)
    nlyr = AddLayerToWorkspace(nlyr, hwy_dbd, nlyr)
    SetLayer(llyr)

    // The following batch macro is documented in TC GISDK help. Type in
    // "Networks" into the help index and then select "Batch Mode".
    opts = null
    opts.Input.[Link Set] = {hwy_dbd + "|" + llyr, llyr}
    if settings.link_query <> null then do
      opts.Input.[Link Set] = opts.Input.[Link Set] + {
        "link_set",
        RunMacro("Normalize Query", settings.link_query)
      }
    end
    opts.Global.[Network Label] = label
    opts.Global.[Network Options].[Turn Penalties] = "Yes"
    opts.Global.[Network Options].[Keep Duplicate Links] = "FALSE"
    opts.Global.[Network Options].[Ignore Link Direction] = "FALSE"
    opts.Global.[Network Options].[Time Units] = settings.time_units
    // Create array of link fields to include
    for r = 1 to link_fields.nrow() do
      field_name = link_fields.tbl.net_field_name[r]
      ab_spec = llyr + "." + link_fields.tbl.ab_field_name[r]
      ba_spec = llyr + "." + link_fields.tbl.ba_field_name[r]
      opts.Global.[Link Options].(field_name) = {ab_spec, ba_spec, , , "False"}
    end
    // Create an array of node fields to include
    for r = 1 to node_fields.nrow() do
      field_name = node_fields.tbl.net_field_name[r]
      ab_spec = nlyr + "." + node_fields.tbl.ab_field_name
      ba_spec = nlyr + "." + node_fields.tbl.ba_field_name[r]
      opts.Global.[Node Options].(field_name) = {ab_spec, ba_spec, , , "False"}
    end
    opts.Global.[Length Units] = settings.distance_units
    out_file = out_dir + "/" + settings.out_file
    opts.Output.[Network File] = out_file
    ok = RunMacro("TCB Run Operation", "Build Highway Network", opts, &Ret)
    if !ok then Throw("Highway network creation failed")

    // Add llyr and nlyr back (the batch macro closes them)
    llyr = AddLayerToWorkspace(llyr, hwy_dbd, llyr)
    nlyr = AddLayerToWorkspace(nlyr, hwy_dbd, nlyr)

    // The code below calls the TransCAD batch macro to apply network settings.
    // This macro is documented in the help. In the GISDK help index, type
    // "settings" and then choose "Highway Networks".
    opts = null
    opts.Input.Database = hwy_dbd
    opts.Input.Network = out_file
    opts.Input.[Def Turn Pen Table] = settings.def_pen_file
    opts.Input.[Spec Turn Pen Table] = settings.spec_pen_file
    if settings.centroid_query <> null then do
      SetLayer(nlyr)
      centroid_set = CreateSet("centroid_set")
      centroid_query = RunMacro("Normalize Query", settings.centroid_query)
      count = SelectByQuery(centroid_set, "several", centroid_query)
      if count = 0
        then Throw("No centroids found using '" + settings.centroid_query + "'")
      opts.Input.[Centroids Set] = {
        hwy_dbd + "|" + nlyr, nlyr, centroid_set, centroid_query}
    end
    if settings.od_toll_query <> null then do
      SetLayer(llyr)
      od_toll_set = CreateSet("od_toll_set")
      od_toll_query = RunMacro("Normalize Query", settings.od_toll_query)
      count = SelectByQuery(od_toll_set, "several", od_toll_query)
      if count = 0
        then Throw("No OD toll links found using '" + settings.od_toll_query + "'")
      opts.Input.[OD Toll Set] = od_toll_set
    end
    if settings.toll_query <> null then do
      SetLayer(llyr)
      toll_set = CreateSet("toll_set")
      toll_query = RunMacro("Normalize Query", settings.toll_query)
      count = SelectByQuery(toll_set, "several", toll_query)
      if count = 0
        then Throw("No fixed toll links found using '" + settings.toll_query + "'")
      opts.Input.[Toll Set] = toll_set
    end
    opts.Global.[Link to Link Penalty Method] = "Table"
    opts.Global.[Global Turn Penalties] = {
      settings.left_tp,
      settings.right_tp,
      settings.straight_tp,
      settings.uturn_tp
    }
    if (settings.xfer_pen_field <> null and settings.xfer_line_type_field = null) or
      (settings.xfer_pen_field = null and settings.xfer_line_type_field <> null)
      then Throw(
        "Both 'xfer_pen_field' and 'xfer_line_type_field' must be provided\n" +
        "if either is."
      )
    if settings.xfer_pen_field <> null then do
      if settings.def_pen_file <> null or settings.spec_pen_file <> null
        then Throw(
          "A transfer penalty field on the link layer cannot be used\n" +
          "with a turn penalty table. Remove one or the other."
        )
      opts.Field.[Line ID] = settings.xfer_line_type_field
      opts.Field.[Xfer Pen] = settings.xfer_pen_field
    end
    ok = RunMacro("TCB Run Operation", "Network Settings", opts, &Ret)
    if !ok then Throw("Highway network settings failed")
  end
  RunMacro("Close All")
EndMacro

/*doc
Creates fully-specified transit network files (.tnw) that can be used for
skimming or assignment.

Inputs (all in named array)
  * rts_file
    * String
    * Path to the route system file
  * settings_file
    * String
    * Path to the transit net settings CSV
  * output_dir
    * String
    * Path to the output directory where the .net files will be created. The
      file name itself is specified in 'settings_tbl'.
  * mode_table
    * Optional string
    * Full path to a CSV that defines transit attributes at the route layer.
    * A specific format is required.
  * period
    * String
    * The period name for the networks being created. (e.g. "PK", "AM", etc)
  * flip_drive_access
    * True/False
    * Only applies to drive-to-transit networks (networks where a drive link
      query has been set).
      * True: Flip access to walk and egress to drive.
      * False (default): Standard drive access and walk egress.
*/

Macro "GT - Create Transit Networks" (MacroOpts)

  // Argument extraction
  rts_file = RunMacro("Normalize Path", MacroOpts.rts_file)
  settings_file = RunMacro("Normalize Path", MacroOpts.settings_file)
  mode_table = RunMacro("Normalize Path", MacroOpts.mode_table)
  period = MacroOpts.period
  flip_drive_access = MacroOpts.flip_drive_access
  output_dir = RunMacro("Normalize Path", MacroOpts.output_dir)

  // Argument checking
  if rts_file = null then Throw("'rts_file' not provided")
  if settings_file = null then Throw("'settings_file' not provided")
  if output_dir = null then Throw("'output_dir' not provided")
  if GetFileInfo(rts_file) = null then Throw("'rts_file' not found")
  if GetFileInfo(settings_file) = null then Throw("'settings_file' not found")

  // Filter the transit network settings file to remove any networks that
  // are not viable.
  opts = null
  opts.rts_file = rts_file
  opts.settings_file = settings_file
  opts.expr_vars.period = period
  opts.mode_table = mode_table
  opts.out_file = settings_file
  RunMacro("GT - Filter Transit Settings", opts)

  // Collect layer and DBD info from route system
  opts = null
  opts.file = rts_file
  {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", opts)
  hwy_dbd = GetLayerDB(llyr)
  stop_dbd = GetLayerDB(slyr)
  CloseMap(map)

  expr_vars.period = period
  expr_vars.rlyr = rlyr
  expr_vars.slyr = slyr
  expr_vars.llyr = llyr
  expr_vars.nlyr = nlyr

  // Read net settings file
  all_settings = RunMacro("Read Parameter File", settings_file, expr_vars)

  // Fill out the options array for each transit network to be
  // created.
  for i = 1 to all_settings.length do
    net_name = all_settings[i][1]
    settings = CopyArray(all_settings.(net_name))

    // Length
    opts = null
    opts.Global.[Network Options].[Street Attributes].Length =
      {llyr + ".Length", llyr + ".Length"}
    opts.Global.[Network Options].[Link Attributes] =
      {{"Length", {llyr + ".Length", llyr + ".Length"}, "SUMFRAC"}}
    // Travel time / impedance
    opts.Global.[Network Options].[Street Attributes].Impedance =
      {llyr + "." + settings.time_field_nt, llyr + "." + settings.time_field_nt}
    opts.Global.[Network Options].[Link Attributes] =
      opts.Global.[Network Options].[Link Attributes] +
      {{
        "Impedance",
        {llyr + "." + settings.time_field_t, llyr + "." + settings.time_field_nt},
        "SUMFRAC"
      }}
    // Fare
    opts.Global.[Network Options].[Route Attributes].(settings.fare_field )=
      {rlyr + "." + settings.fare_field}
    // Headway
    opts.Global.[Network Options].[Route Attributes].(settings.headway_field) =
      {rlyr + "." + settings.headway_field}

    opts.Input.[Transit RS] = rts_file
    opts.Input.[RS Set] = {rts_file + "|" + rlyr, rlyr}
    if settings.route_qry <> null then do
      route_qry = RunMacro("Normalize Query", settings.route_qry)
      opts.Input.[RS Set] = opts.Input.[RS Set] + {"route_set", route_qry}
    end
    opts.Input.[Stop Set] = {stop_dbd + "|" + slyr, slyr}
    if settings.stop_qry <> null then do
      stop_qry = RunMacro("Normalize Query", settings.stop_qry)
      opts.Input.[Stop Set] = opts.Input.[Stop Set] + {"stop_set", stop_qry}
    end
    opts.Input.[Walk Set] = {hwy_dbd + "|" + llyr, llyr}
    if settings.walk_link_qry <> null then do
      walk_link_qry = RunMacro("Normalize Query", settings.walk_link_qry)
      opts.Input.[Walk Set] = opts.Input.[Walk Set] + {"walk_links", walk_link_qry}
    end
    // Driving section 1 (because order of opts array mattered)
    if settings.drive_link_qry <> null then do
      drive_link_qry = RunMacro("Normalize Query", settings.drive_link_qry)
      opts.Input.[Drive Set] = {
        hwy_dbd + "|" + llyr, llyr, "drive_links", drive_link_qry
      }
    end
    opts.Global.[Network Label] = if settings.net_label <> null
      then settings.net_label
      else net_name + " Transit Network"
    opts.Global.[Network Options].Walk = if settings.allow_walk <> null
      then settings.allow_walk
      else "Yes"
    opts.Global.[Network Options].[Mode Field] = rlyr + "." +
      settings.route_mode_field
    opts.Global.[Network Options].[Walk Mode] = {
      llyr + "." + settings.link_mode_field,
      llyr + "." + settings.link_mode_field
    }
    opts.Global.[Network Options].TagField = settings.stop_node_id
    opts.Global.[Network Options].[Merge Stops] = {
      slyr + ".ID", slyr + "." + settings.stop_node_id
    }
    // Driving section 2 (because order of opts array mattered)
    if settings.drive_link_qry <> null then do
      opts.Global.[Network Options].[Drive Links] = llyr + "|drive_links"
      // Drive time field
      drive_time_field = settings.drive_time_field
      opts.Global.[Network Options].[Street Attributes].drive_time =
        {llyr + "." + drive_time_field, llyr + "." + drive_time_field}
      opts.Global.[Network Options].[Link Attributes] =
        opts.Global.[Network Options].[Link Attributes] +
        {{
          "drive_time",
          {llyr + "." + drive_time_field, llyr + "." + drive_time_field},
          "SUMFRAC"
        }}
    end
    net_file = output_dir + "\\" + settings.out_file
    opts.Output.[Network File] = net_file

    ok = RunMacro("TCB Run Operation", "Build Transit Network", opts, &Ret)
    if !ok then do
      Ret = {"Transit network creation failed. Error info:"} + Ret
      ShowArray(Ret)
      Throw("Failed building transit network " + net_name)
    end

    // Network Settings
    opts = null
    opts.Input.[Transit RS] = rts_file
    opts.Input.[Transit Network] = net_file
    opts.Input.[Centroid Set] = {hwy_dbd + "|" + nlyr, nlyr}
    if settings.centroid_query <> null then do
      centroid_query = RunMacro("Normalize Query", settings.centroid_query)
      opts.Input.[Centroid Set] = opts.Input.[Centroid Set] + {
        "centroid_set", centroid_query
      }
    end
    if mode_table <> null then do
    opts.Input.[Mode Table] = {mode_table}
    if settings.mode_used_column = null then Throw(
      "Mode table provided, but 'mode_used_column' not set in \n" +
      "'settings_file'. This option tells the model which \n" +
      "column in the mode table defines modes included in the network."
    )
    mode_opts = RunMacro("GT - Set Mode Table Opts", mode_table, settings.mode_used_column)
    opts = opts + mode_opts
    end
    if settings.mode_used_column <> null and mode_table = null then Throw(
      "'mode_used_column' set in 'settings_file', but 'mode_table' is null"
    )
    opts.Field.[Link Impedance] = "Impedance"
    if settings.drive_link_qry <> null
      then opts.Field.[Link Drive Time] = "drive_time"
    opts.Field.[Route Fare] = settings.fare_field
    opts.Field.[Route Headway] = settings.headway_field
    opts.Field.[Stop Dwell On Time] = settings.dwell_on_field
    opts.Field.[Stop Dwell Off Time] = settings.dwell_off_field
    // Classes not currently supported by this macro
    opts.Global.[Class Names] = {"Class 1"}
    opts.Global.[Class Description] = {"Class 1"}
    opts.Global.[current class] = "Class 1"
    opts.Flag.[Use All Walk Path] = settings.allow_walk_only
    opts.Flag.[Fare System] = settings.fare_system
    if mode_table <> null then opts.Flag.[Use Mode] = "Yes"
    // These global variabes cannot be overwritten by modal or route values
    opts.Global.[Walk Weight] = r2i(settings.global_walk_weight)
    opts.Global.[Max Trip Time] = r2i(settings.global_max_trip_time)
    opts.Global.[Max Xfer Number] = r2i(settings.global_max_xfer_number)
    opts.Global.[Value of Time] = settings.global_value_of_time
    opts.Global.[Interarrival Para] = settings.global_interarrival_para
    opts.Global.[Logit Scale Para] = settings.global_logit_scale_para
    opts.Global.[Global Max WACC Path] = r2i(settings.global_max_wacc_path)
    opts.Global.[Walk Path Threshold] = settings.global_walk_path_threshold
    opts.Global.[Drive Path Threshold] = settings.global_drive_path_threshold
    opts.Global.[Mid-block Threshold] = r2i(settings.global_midblock_threshold)
    // These global variables will be overwritten if specified by mode or route
    opts.Global.[Global Fare Value] = r2i(settings.global_fare_value)
    opts.Global.[Global Xfer Fare] = settings.global_xfer_fare
    opts.Global.[Global Fare Weight] = r2i(settings.global_fare_weight)
    opts.Global.[Global Imp Weight] = r2i(settings.global_imp_weight)
    opts.Global.[Global Init Weight] = r2i(settings.global_init_weight)
    opts.Global.[Global Xfer Weight] = r2i(settings.global_xfer_weight)
    opts.Global.[Global IWait Weight] = r2i(settings.global_iwait_weight)
    opts.Global.[Global XWait Weight] = r2i(settings.global_xwait_weight)
    opts.Global.[Global Dwell Weight] = r2i(settings.global_dwell_weight)
    opts.Global.[Global Headway] = r2i(settings.global_headway)
    opts.Global.[Global Init Time] = r2i(settings.global_init_time)
    opts.Global.[Global Xfer Time] = r2i(settings.global_xfer_time)
    opts.Global.[Global Max IWait] = r2i(settings.global_max_iwait)
    opts.Global.[Global Min IWait] = r2i(settings.global_min_iwait)
    opts.Global.[Global Max XWait] = r2i(settings.global_max_xwait)
    opts.Global.[Global Min XWait] = r2i(settings.global_min_xwait)
    opts.Global.[Global Layover Time] = r2i(settings.global_layover_time)
    opts.Global.[Global Dwell On Time] = settings.global_dwell_on
    opts.Global.[Global Dwell Off Time] = settings.global_dwell_off
    opts.Global.[Global Max Access] = r2i(settings.global_max_access)
    opts.Global.[Global Max Egress] = r2i(settings.global_max_egress)
    opts.Global.[Global Max Transfer] = r2i(settings.global_max_transfer)
    opts.Global.[Global Max Imp] = r2i(settings.global_max_imp)
    opts.Global.[Path Threshold] = settings.global_path_threshold

    // PNR/KNR options
    if settings.drive_link_qry <> null then do
      opts.Input.[Parking Node Set] = {hwy_dbd + "|" + nlyr, nlyr}
      if settings.parking_node_qry <> null then do
        parking_node_qry = RunMacro("Normalize Query", settings.parking_node_qry)
        opts.Input.[Parking Node Set] = opts.Input.[Parking Node Set] +
        {"parking_set", parking_node_qry}
      end

      // Invert drive access/egress
      if flip_drive_access then do
        opts.Flag.[Use Park and Ride] = "No"
        opts.Flag.[Use Egress Park and Ride] = "Yes"
        opts.Flag.[Use P&R Walk Access] = "Yes"
        opts.Flag.[Use P&R Walk Egress] = "No"
        opts.Input.[Egress Parking Node Set] = opts.Input.[Parking Node Set]
        opts.Input.[Parking Node Set] = null
      end else do
        opts.Flag.[Use Park and Ride] = "Yes"
        opts.Flag.[Use Egress Park and Ride] = "No"
        opts.Flag.[Use P&R Walk Access] = "No"
        opts.Flag.[Use P&R Walk Egress] = "Yes"
      end
      // TODO: add support for parking capacity constraint
      opts.Flag.[Use Parking Capacity] = "No"

      opts.Global.[Global Max PACC] = r2i(settings.global_max_pacc)
      opts.Global.[Drive Time Weight] = r2i(settings.drive_time_weight)
      opts.Global.[Max Acce Drive Time] = r2i(settings.max_acce_drive_time)
      opts.Global.[Max Egre Drive Time] = r2i(settings.max_egre_drive_time)
      opts.Global.[Max Acce Drive Paths] = r2i(settings.max_acce_drive_paths)
    end
    ok = RunMacro("TCB Run Operation", "Transit Network Setting PF", opts, &Ret)
    if !ok then do
      Ret = {"Transit network settings failed. Error info:"} + Ret
      ShowArray(Ret)
      Throw("Transit network settings failed")
    end
  end
EndMacro

/*
This macro automates the setting of mode table opts given an input mode table.
In order to do this, the field names must be in a certain format.

Inputs
  mode_table
    String
    Full path to the transit mode table to use. Many options can be set using
    this table by adding fields. Those fields then correspond to options in
    the options array that must be set. In order to automate this process, the
    field name in the mode table must be based on the option name: remove
    spaces, use all lowercase, and remove the leading "Mode".

    For example:

    Option Array Name  | Mode Table Field Name
    ------------------------------------------
    Mode Fare          | fare
    Mode Xfer Weight   | xfer_weight
    Mode Off Dwell Par | off_dwell_par
    etc.

    The exception to this rule:
    The mode table must also contain binary fields that describe, for a given
    network, which modes to include. (When setting up a transit network
    manually, you would select this column for the "Mode Used" drop down.) These
    field names must match the network names found in the transit network
    settings CSV. (e.g. "w_lb")

  mode_used_column
    String
    This specifies which column in the transit mode table to use as the
    "Mode Used" option.
*/

Macro "GT - Set Mode Table Opts" (mode_table, mode_used_column)

  // Argument checking
  if mode_table = null then Throw("'mode_table' not provided")
  if mode_used_column = null then Throw("'mode_used_column' not provided")
  if GetFileInfo(mode_table) = null then Throw("'mode_table' not found")

  df = CreateObject("df")
  df.read_csv(mode_table)
  colnames = df.colnames()
  for colname in colnames do
    if df.in(colname, {"mode_name", "mode_id"}) then continue
    if colname = "net_defs" then break
    opt_name = "Mode " + Proper(Substitute(colname, "_", " ", ))
    opts.Field.(opt_name) = colname
  end

  if df.in("fare_type", colnames)
    then opts.Flag.[Fare By Mode] = "Yes"
    else opts.Flag.[Fare By Mode] = "No"
  opts.Flag.[Use Mode Cost] = "No"
  opts.Flag.[Combine By Mode] = "Yes"
  opts.Flag.[M2M Fare Method] = 2
  opts.Field.[Mode Used] = mode_used_column

  return(opts)
EndMacro

/*
Checks the transit network settings route query and optional transit mode table,
determines which networks are valid in the route system, and removes any that
aren't. A common example is removing rail network settings from base year models
that don't have rail.

Inputs
  MacroOpts
    Named array
    Contains all arguments for the function

    rts_file
      String
      Full path to the route system file (.rts)

    settings_file
      String
      Full path to transit network settings. Same format as
      "GT - Create Transit Networks".

    expr_vars
      Optional named array
      Used to evaluate any {variables} found in 'settings_file'.

    mode_table
      Optional string
      Full path to the mode table. If provided, the "mode_used_column" from the
      settings file will be used to identify which column in the mode table lists
      the modes.

    out_file
      String
      Full path where the output file will be written.

Returns
  Nothing. Writes out a new settings CSV at the same location as 'settings_file'
  with the suffice '_filtered' added.
*/

Macro "GT - Filter Transit Settings" (MacroOpts)

  // Argument extraction
  rts_file = MacroOpts.rts_file
  settings_file = MacroOpts.settings_file
  expr_vars = MacroOpts.expr_vars
  mode_table = MacroOpts.mode_table
  out_file = MacroOpts.out_file

  // Argument checking
  if rts_file = null then Throw("'rts_file' not provided")
  if GetFileInfo(rts_file) = null then Throw("'rts_file' not found")
  if settings_file = null then Throw("'settings_file' not provided")
  if GetFileInfo(settings_file) = null then Throw("'settings_file' not found")
  if mode_table <> null and GetFileInfo(mode_table) = null
    then Throw("'mode_table' not found")
  if out_file = null then Throw("'out_file' not provided")

  all_settings = RunMacro("Read Parameter File", settings_file, expr_vars)
  // Also read the settings into a data frame. This will be used to filter out
  // invalid networks. Importantly, do not evaluate any expressions/variables
  // found. When written out, the settings file needs to still be generic.
  df = CreateObject("df")
  df.read_csv(settings_file)

  opts = null
  opts.file = rts_file
  {map, {rlyr, slyr, , nlyr, llyr}} = RunMacro("Create Map", opts)
  hwy_dbd = GetLayerDB(llyr)
  stop_dbd = GetLayerDB(slyr)

  for s = 1 to all_settings.length do
    net_name = all_settings[s][1]
    settings = all_settings[s][2]

    // Check to make sure there are routes in the route_qry
    SetLayer(rlyr)
    route_qry = RunMacro ("Normalize Query", settings.route_qry)
    n = SelectByQuery("check", "several", route_qry)
    if n = 0 then do
      df.filter("Network != '" + net_name + "'")
      continue
    end

    // If provided, check the mode table against the route system
    if mode_table <> null then do
      mode_df = CreateObject("df")
      mode_df.read_csv(mode_table)
      mode_df.filter("nz(" + settings.mode_used_column + ") > 0")
      max = ArrayMax(V2A(mode_df.tbl.(settings.mode_used_column)))
      // if the max value in the mode_used column is 1, then check to make sure
      // the highest mode listed exists. If the max is greater than one, it
      // indicates that those modes are required - check them all.
      if max > 1
        then mode_df.filter(
          "nz(" + settings.mode_used_column + ") = " + String(max))
        else do
          max_mode_num = ArrayMax(V2A(mode_df.tbl.mode_id))
          mode_df.filter("mode_id = " + String(max_mode_num))
        end

      v_mode = mode_df.tbl.mode_id
      l_mode_field = settings.link_mode_field
      r_mode_field = settings.route_mode_field
      for i = 1 to v_mode.length do
        id = v_mode[i]

        SetLayer(llyr)
        qry = "Select * where " + l_mode_field + " = " + String(id)
        n = SelectByQuery("check", "several", qry)
        SetLayer(rlyr)
        qry = "Select * where " + r_mode_field + " = " + String(id)
        m = SelectByQuery("check", "several", qry)
        if n + m = 0 then do
          df.filter("Network != '" + net_name + "'")
          break
        end
      end
    end
  end

  CloseMap(map)
  df.write_csv(out_file)
EndMacro

/*doc
During assignment, GT saves the MSA travel time to a "___MSATime" field (3
underscores), but this only happens on one net file. For feedback and skimming,
the other net files need to have the field added or updated.

Inputs (all in a named array)
  * net_settings_file
    * String
    * Full path to the csv file that describes the network settings. This is the
      same file used by GTs create network functions. Highway or transit
      setting files can be used.
  * expr_vars
    * Optional array of strings
    * Used to evaluate variables found in net_settings_file.
  * congested_net_file
    * String
    * Full path to the .net file used in assignment that has the latest
      ___MSATime.
    * All networks to update must be in the same directory as this one.
  * dbd_or_rts
    * String
    * Full path to the highway DBD or transit RTS that the `net_settings_file`
      is based on.
*/

Macro "Update MSATime" (MacroOpts)
  RunMacro("TCB Init")
  
  // Argument extraction
  net_settings_file = MacroOpts.net_settings_file
  expr_vars = MacroOpts.expr_vars
  congested_net_file = MacroOpts.congested_net_file
  dbd_or_rts = RunMacro("Normalize Path", MacroOpts.dbd_or_rts)
  
  // Argument checking
  if net_settings_file = null then Throw("'net_settings_file' not provided")
  if GetFileInfo(net_settings_file) = null 
    then Throw("'net_settings_file' not found")
  if congested_net_file = null then Throw("'congested_net_file' not provided")
  if GetFileInfo(congested_net_file) = null 
    then Throw("'congested_net_file' not found")
  if dbd_or_rts = null then Throw("'dbd_or_rts' not provided")
  if GetFileInfo(dbd_or_rts) = null then Throw("'dbd_or_rts' not found")
  {drive, folder, name, ext} = SplitPath(dbd_or_rts)
  if ext = ".dbd" then network_type = "dbd"
  else if ext = ".rts" then do
    network_type = "rts"
    stop_dbd = Substitute(dbd_or_rts, ".rts", "S.dbd", )
  end
  else Throw("'dbd_or_rts' is not a .dbd or .rts file")
  
  // Create an MSA time view from the congested network. This uses an
  // undocumented TC function.
  temp_bin = GetTempFileName(".bin")
  opts = null
  opts.[Flow Fields] = {"__MSATime"}
  opts.[Write To] = {temp_bin, "FFB", "temp"}
  congested_net = ReadNetwork(congested_net_file)
  vw = CreateTableFromNetworkVars(congested_net, opts)
  
  // Open highway network and join the msa time info
  opts = null
  opts.file = dbd_or_rts
  opts.minimized = "true"
  if network_type = "dbd"
    then {map, {nlyr, llyr}} = RunMacro("Create Map", opts)
    else {map, {rlyr, slyr, pslyr, nlyr, llyr}} = RunMacro("Create Map", opts)
  jv = JoinViews("jv", llyr + ".ID", vw + ".ID1", )
  
  {drive, folder, name, ext} = SplitPath(congested_net_file)
  net_dir = RunMacro("Normalize Path", drive + folder)
  
  // Loop over each network in the settings file and add/update MSATime
  settings = RunMacro("Read Parameter File", net_settings_file, expr_vars)
  for s = 1 to settings.length do
    name = settings[s][1]
    
    net_file = net_dir + "/" + settings.(name).out_file
    
    // if updating highway
    if network_type = "dbd" then do
      opts = null
      opts.Input.Network = net_file
      opts.Input.[Update Link Source Sets] = {
        {{dbd_or_rts + "|" + llyr, temp_bin, {"ID"}, {"ID1"}}, "jv"}
      }
      opts.Input.Database = dbd_or_rts
      opts.Global.[Update Network Fields].Links.__MSATime = {
        jv + ".AB___MSATime", jv + ".BA___MSATime", , , "False"
      }
      opts.Global.[Update Network Fields].Formulas = {}
      opts.Global.[Link to Link Penalty Method] = "Table"
      ok = RunMacro("TCB Run Operation", "Network Settings", opts, &Ret)
      if !ok then Throw("'Update MSATime' failed")
    
    // if updating transit
    end else do
      opts = null
      opts.Input.[Transit RS] = dbd_or_rts
      opts.Input.[Stop View] = {stop_dbd + "|" + slyr, slyr}
      opts.Input.Network = net_file
      opts.Global.[Update Attributes].[Transit Attributes] = {
        {"Impedance", {jv + ".AB___MSATime", jv + ".BA___MSATime"}},
        {"drive_time", {jv + ".AB___MSATime", jv + ".BA___MSATime"}}
      }
      opts.Global.[Update Attributes].[Walk Attributes] = {
        {"Impedance", {jv + ".WalkTime", jv + ".WalkTime"}},
        {"drive_time", {jv + ".AB___MSATime", jv + ".BA___MSATime"}}
      }
      ok = RunMacro("TCB Run Operation", "Update Transit Network Attributes", opts, &Ret)
      if !ok then Throw("'Update MSATime' failed")
    end
  end
  
  CloseView(jv)
  CloseMap(map)
EndMacro
