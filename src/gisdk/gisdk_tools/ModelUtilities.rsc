/*
This script provides a library of tools that are generally useful when
running GISDK models.
*/

/*
This macro clears the workspace.
Optionally, it also cleans up DCC files created from csv tables.

Inputs
  scen_dir
    Optional String
    Full path to the scenario directory. If provided, the macro will clear
    any DCC files in the directory (and all sub directories). If null, the macro
    will look for a global Args.[Scenario Folder] variable. If neither are present,
    then the DCC file cleaning step does not occur.
*/

Macro "Close All" (scen_dir)

  // Close maps
  maps = GetMapNames()
  if maps <> null then do
    for i = 1 to maps.length do
      CloseMap(maps[i])
    end
  end

  // Close any views
  views = GetViewNames()
  for view in views do
    Closeview(view)
  end

  // Close matrices
  mtxs = GetMatrices()
  if mtxs <> null then do
    handles = mtxs[1]
    for i = 1 to handles.length do
      handles[i] = null
    end
  end

  // Delete any DCC files in the scenario folder
  // if scen_dir is passed to the function, then use it. If not, look for
  // the global variable MODELARGS (that should be established in
  // your project code). If neither exists, do nothing.
  if scen_dir = null then scen_dir = Args.[Scenario Folder]
  if scen_dir <> null then do
    a_files = RunMacro("Catalog Files", scen_dir, {"DCC"})
    for f = 1 to a_files.length do
      DeleteFile(a_files[f])
    end
  end
endMacro

/*
Removes any progress bars open
TC does not have a function to get all open progress bars.
As a result, keep calling DestroyProgressBar() until you
hit an error (meaning they are all closed).
*/

Macro "Destroy Progress Bars"
  on notfound goto quit
  while 0 < 1 do
    DestroyProgressBar()
  end
  quit:
  on notfound default
EndMacro

/*
Similar to Destroy Progress Bars, but the name of the stopwatch
is required.  Thus, any stopwatches used in the model must
be added by name to this list.
*/

Macro "Destroy Stopwatches"
  on notfound goto quit
  DestroyStopwatch("run_time")
  quit:
  on notfound default
EndMacro

/*
Checks the UI date against the rsc/lst files used to create it.  If any of the
rsc files are newer than the UI, the UI should be recompiled.

Inputs:
ui_dbd       complete path to the UI file
scriptDir   path to folder containing RSC files

Returns:
Shows a warning message if the UI is out of date.
*/

Macro "Recompile UI Check" (ui_dbd, scriptDir)

  a_files = RunMacro("Catalog Files", scriptDir, {"rsc", "lst"})
  // Check the *.1 file instead of *.dbd.
  // The .dbd file doesn't get updated on recompile.
  a_uiInfo = GetFileInfo(Substitute(ui_dbd, ".dbd", ".1", ))
  uiTime = a_uiInfo[9]
  a_units = {"year", "month", "day", "hour", "minute", "second", "millisecond"}
  recompile = "False"
  for i = 1 to a_files.length do
    file = a_files[i]

    a_info = GetDirectoryInfo(file, "File")
    fileTime = a_info[1][9]
    for j = 1 to a_units.length do
      unit = a_units[j]
      uT = uiTime.(unit)
      fT = fileTime.(unit)

      // If the year is greater in the UI than rsc, no problem.
      // Don't check any more date units on the current file.
      if uiTime.(unit) > fileTime.(unit) then do
        j = a_units.length + 1
      end

      // If the year is less in UI than rsc, then there is a problem.
      // Don't check any more date units OR files.
      if uiTime.(unit) < fileTime.(unit) then do
        recompile = "True"
        problemFile = file
        j = a_units.length + 1
        i = a_files.length + 1
      end

      // Otherwise, the years are the same, and the j loop must continue to
      // compare the months (then days, hours, etc.)
    end
  end

  // Show warning if necessary
  if recompile then ShowMessage("The compiled UI is older than " +
    problemFile + "\n(and possibly other .rsc files)\nRe-compile the UI " +
    "before using the model.")
EndMacro

/*
Wraps "Read Named Array" with some additional features including support for a
description field and {variables} using "Noramlize Expression". It also supports
default values using the key/reserved word "default" in the parameter file. This
greatly reduces the size of parameter files by eliminating to repeat the same
values for each combination of, for example, purpose and time period.

Inputs
  param_file
    String
    Full path to CSV file of parameters

  expr_vars
    Named array
    Used to evaluate {variables} found in param file.

  desc_col
    String
    The name of the field containing description information if the file
    has one. Defaults to "description" (not case sensitive).

  return_desc
    True/False
    Whether to return description field info instead of parameters.
    Defaults to false.

Outputs
  By default, returns a named array of parameters. Can optionally return the
  description column.
*/

Macro "Read Parameter File" (param_file, expr_vars, desc_col, return_desc)

  // Determine if a description field exists and split the columns
  if desc_col = null then desc_col = "description"

  df = CreateObject("df")
  df.read_csv(param_file, , expr_vars)
  if return_desc
    then return(df.tbl.(desc_col))
  // Remove description column and anything to the right of it
  colnames = df.colnames()
  for colname in colnames do
    if CompareStrings(colname, desc_col, ) then break
    cols_to_keep = cols_to_keep + {colname}
  end
  df.select(cols_to_keep)
  colnames = df.colnames()
  // Remove any rows with null values
  qry = colnames[1] + " <> null"
  for c = 2 to colnames.length do
    qry = qry + " and " + colnames[c] + " <> null"
  end
  df.filter(qry)
  temp_csv = GetTempFileName("*.csv")
  df.write_csv(temp_csv)
  params = RunMacro("Read Named Array", temp_csv)
  params = ExcludeArrayElements(params, 1, 1)

  params = RunMacro("Propagate Default Parameters", params)

  return(params)
EndMacro

/*
Helper to "Read Parameter File". Searches a named array for the keyword
'default'. If found, it fills in missing key-value pairs with the default
values. If a key-value pair is already present, it is not modified.
*/

Macro "Propagate Default Parameters" (params, depth)

  depth =
    if depth = null then 1
    else depth + 1

  // Propagate any default values at the current depth
  if params.default <> null then do
    defaults = params.default
    params.default = null

    for d = 1 to defaults.length do
      default_name = defaults[d][1]

      for p = 1 to params.length do
        param_name = params[p][1]

        if params.(param_name).(default_name) = null then do
          params.(param_name).(default_name) = defaults.(default_name)
        end
      end
    end
  end

  // Check each depth for more default values
  for p = 1 to params.length do
    param_name = params[p][1]


    if RunMacro("Is Named Array", params.(param_name)) then do
      params.(param_name) = RunMacro(
        "Propagate Default Parameters", params.(param_name), depth
      )
    end
  end

  return(params)
EndMacro

/*
Checks to see if a variable is a named array. (e.g.: {{"name"}, {value}})
*/

Macro "Is Named Array" (var)
  if TypeOf(var) <> "array"  then return("false")
  if TypeOf(var[1]) <> "array"  then return("false")
  if var[1].length <> 2  then return("false")
  if TypeOf(var[1][1]) <> "string" then return("false")
  return("true")
EndMacro

/*
Recursive macro used by other functions to read named arrays.

Input:
OptsArray   Array   The options array in which to insert information.  If empty,
                    a new options array will be created.

path        Array   Names of the sub-arrays describing the location to insert.
                    e.g., {"HBW", "AM"} would create the following location:
                    OptsArray.HBW.AM

value               The value to be placed into the specified location

Output:
An options array with the value inserted into the specified location
*/

Macro "Insert into Opts Array" (OptsArray, path, value)

  location = path[1]
  if path.length > 1 then do
    path = ExcludeArrayElements(path, 1, 1)
    OptsArray.(location) = RunMacro(
      "Insert into Opts Array", OptsArray.(location), path, value
      )
  end else do
    OptsArray.(location) = value
  end

  return(OptsArray)
EndMacro

/*
Abstracts "Write Named Array" to include support for column names and a
description field.

Inputs
  params
    Named array
    Parameters to write.

  out_file
    String
    Full path to CSV file to write to.

  colnames
    Array of strings
    Column names for the parameter file.

  v_description
    Optional vector of description info. If provided, will be added to the CSV.
*/

Macro "Write Parameter File" (params, out_file, colnames, v_description)

  // Argument checking
  if params = null then Throw("'params' not provided")
  if out_file = null then Throw("'out_file' not provided")
  if colnames = null then Throw("'colnames' not provided")

  // Write column names
  file = OpenFile(out_file, "w")
  if colnames <> null then do
    str = colnames[1]
    for i = 2 to colnames.length do
      str = str + "," + colnames[i]
    end
    WriteLine(file, str)
  end

  RunMacro("Write Named Array", params, file)
  CloseFile(file)

  if v_description <> null then do
    df = CreateObject("df")
    df.read_csv(out_file)
    df.mutate("description", v_description)
    df.write_csv(out_file)
  end
EndMacro

/*
Used by "Write Parameter File"
Recursively works through every level of an options array and writes a line.
Expects the bottom level of the options array to be made up of "value" and
"desc" values and includes both in the same line.
*/

Macro "Recursive OptsArray Writing" (OptsArray, string, file)

  for i = 1 to OptsArray.length do
    newOptsArray = OptsArray[i]

    test1 = newOptsArray[1]
    test2 = newOptsArray[2]

    if TypeOf(newOptsArray[2]) = "array" then do
      if string = null then newString = newOptsArray[1]
      else newString = string + "," + newOptsArray[1]

      RunMacro("Recursive OptsArray Writing", newOptsArray[2], newString, file)
    end else do

      value = OptsArray.value
      if TypeOf(value) <> "string" then value = String(value)
      desc = OptsArray.desc
      if TypeOf(desc) <> "string" then value = String(desc)

      newString = string + "," + value + "," + desc

      WriteLine(file, newString)
      return()
    end
  end

EndMacro

/*
It can be difficult to debug the large, named (options) arrays needed for some
of TransCADs macros (eg transit skimming). Often, however, you can batch record
one that works. This macro will compare two options arrays and show differecnes.

Used for debugging only.

Inputs
  opts1
    Named array
    First array to compare

  opts2
    Named array
    Second array to compare

  output_dir
    Optional string
    Full path of the output directory. If provided, the two options arrays will
    also be written out to this directory for manual inspection.
*/

Macro "Compare Named Arrays" (opts1, opts2, output_dir)

  if opts1 = null then Throw("'opts1' not provided")
  if opts2 = null then Throw("'opts2' not provided")
  if output_dir = null then Throw("'output_dir' not provided")

  if GetDirectoryInfo(output_dir, "All") = null then CreateDirectory(output_dir)
  csv1 = output_dir + "/opts1.csv"
  csv2 = output_dir + "/opts2.csv"
  RunMacro("Write Named Array", opts1, csv1)
  RunMacro("Write Named Array", opts2, csv2)

  RunMacro("Compare Text Files", csv1, csv2)
EndMacro


/*
This removes any nesting structure from an array, returning a 1D array.
For example:

{1, {2, 3, 4}, 5} becomes {1, 2, 3, 4, 5}

opts.input.pce = {1, 1}
opts.Input.pce_field = {"None", "None"}
opts.Global.test = 4

becomes 

{
  input,
  pce,
  1,
  1,
  input,
  pce_field,
  None,
  None,
  Global,
  test,
  4
}
*/

Macro "Flatten Array" (array, new_array)
  
  array_type = TypeOf(array)
  
  if array_type = "array" then do
    first_element = array[1]
    element_type = TypeOf(first_element)
    if element_type = "array" then do
      new_array = RunMacro("Flatten Array", first_element, new_array)
      array = ExcludeArrayElements(array, 1, 1)
      if array <> null then do
        new_array = RunMacro("Flatten Array", array, new_array)
      end else do
        return(new_array)
      end
    end else do
      new_array = new_array + {first_element}
      array = ExcludeArrayElements(array, 1, 1)
      if array <> null then do
        new_array = RunMacro("Flatten Array", array, new_array)
      end else do
        return(new_array)
      end
    end
  end else do
    new_array = new_array + {array}
    array = ExcludeArrayElements(array, 1, 1)
    return(new_array)
  end
  
  return(new_array)
EndMacro

/*
Determines if the argument passed is a simple array e.g.:
{1, 2, 3}
named array e.g.:
{{"test1",1}}        (created like opts.test1 = 1)
nested array e.g.:
{1, {2, 3}}
or not an array

Output
  Returns either "simple", "named",  "false" (for not an array), or
  "unknown" for complex nested arrays that aren't name-value pairs.

*/

Macro "Get Array Type" (array)
  if array = null then Throw("'array' not provided")
  if TypeOf(array) <> "array" then return("false")
  if TypeOf(array[1]) = "array" then do
    if array[1].length = 2 and TypeOf(array[1][1]) = "string"
      then return("named")
      else return("nested")
  end
  return("simple")
EndMacro

/*
Translates a named array into a CSV file

Inputs
  array
    Named array
    Input array to write out

  file
    String or file handle
    If string, then full path to CSV file to be written. The file will be
    completely re-written. If a file handle, the array will be appended to
    the end of the file.

  string
    null
    Not used when calling the macro (used during recursion only)

  depth
    null
    Not used when calling the macro (used during recursion only)
*/

Macro "Write Named Array" (array, file, string, depth)

  type = TypeOf(file)
  if type = "string" then file = OpenFile(file, "w")
  if depth = null then depth = 1
  else depth = depth + 1

  for i = 1 to array.length do
    new_array = array[i]

    if RunMacro("Is Named Array", new_array[2]) then do
      if string = null then newString = new_array[1]
      else newString = string + "," + new_array[1]

      RunMacro("Write Named Array", new_array[2], file, newString, depth)
    // If 'array' is not named
    end else do
      last_name = new_array[1]
      value = new_array[2]

      // If it's another array type, convert it into a string representation
      if TypeOf(value) = "array" then do
        next_string = RunMacro("A2S", value)
        next_string = "\"" + next_string + "\""
      end else if TypeOf(value) <> "string"
        then next_string = String(value)
        else next_string = value

      if string = null then newString = last_name + "," + next_string
      else newString = string + "," + last_name + "," + next_string

      WriteLine(file, newString)
    end
  end

  depth = depth - 1
  if depth = 0 and type = "string" then CloseFile(file)
  return()
EndMacro

/*
Takes a CSV file of the format output by "Write Named Array" and turns it into
a named array.

Inputs
  csv
    String
    Full path to csv containing named array to read

Returns
  A named array
*/

Macro "Read Named Array" (csv)
  file = OpenFile(csv, "r")

  result.starter = 1

  while !FileAtEOF(file) do
    line = ReadLine(file)
    // if the final value is quoted (contains commas)
    if Right(line, 1) = "\"" then do
      values = ParseString(line, "\"")
      value = values[2]
      // if the quoted value represents an array (ie is bracketed)
      if Right(value, 1) = "}" then value = RunMacro("S2A", value)
      values = values[1]
      path = ParseString(values, ",")
    // if the final value is a string/int/etc
    end else do
      values = ParseString(line, ",")
      path = ExcludeArrayElements(values, values.length, 1)
      value = values[values.length]
      value = if value = "0"
        then 0
        else if Value(value) = 0
          then value
          else Value(value)
    end
    RunMacro("Insert into Opts Array", result, path, value)
  end

  CloseFile(file)
  result.starter = null
  return(result)
EndMacro

/*
Converts arrays to strings (and vice versa). An array of {1,2,3} will be
converted to "{1,2,3}".
*/

Macro "A2S" (array)

  if TypeOf(array) <> "array" then Throw("'array' must be an array")

  for a = 1 to array.length do
    temp = array[a]

    if TypeOf(temp) = "matrix" then temp = RunMacro("M2A", temp)
    if TypeOf(temp) = "array" then temp = RunMacro("A2S", temp)
    else if TypeOf(temp) <> "string" then temp = String(temp)

    if a = 1 then string = string + "{" + temp
    else string = string + ", " + temp
  end
  string = string + "}"

  return(string)
EndMacro

/*
Takes a string representation of any array and turns it into an actual array.
e.g. "{{1, 2}, {3, {4, 5}}}"
*/

Macro "S2A" (string)

  if string = null then return(string)
  if TypeOf(string) <> "string"
    then Throw("'string' must be a string (e.g. '{{1, 2}, {3, {4, 5}}}')")

  if string[1] <> "{" then do
    if Value(string) <> 0 then string = Value(string)
    return(string)
  end

  temp_string = Left(string, StringLength(string) - 1)
  temp_string = Right(temp_string, StringLength(temp_string) - 1)

  depth = 1
  for c = 1 to StringLength(temp_string) do
    char = temp_string[c]

    if char = "{" then depth = depth + 1
    if char = "}" then depth = depth - 1

    if depth = 1 and char = "," then temp_string[c] = "|"
  end

  temp_array = SplitString(temp_string)
  for i = 1 to temp_array.length do
    temp_array[i] = Trim(temp_array[i])
  end

  for i = 1 to temp_array.length do
    temp_array[i] = RunMacro("S2A", temp_array[i])
  end

  return(temp_array)
EndMacro

/*
Converts a matrix handle to an array
*/

Macro "M2A" (mtx)
  array.Name = mtx.Name
  array.nCores = mtx.nCores
  array.nIndices = mtx.nIndices
  return(array)
EndMacro

/*
Removes a field from a view/layer

Input
viewName  Name of view or layer (must be open)
field_name Name of the field to remove. Can pass string or array of strings.
*/

Macro "Drop Field" (viewName, field_name)
  Throw("'Drop Field' is deprecated. The function is now called 'Remove Field'.")
EndMacro

Macro "Remove Field" (viewName, field_name)
  a_str = GetTableStructure(viewName)

  if TypeOf(field_name) = "string" then field_name = {field_name}

  for fn = 1 to field_name.length do
    name = field_name[fn]

    for i = 1 to a_str.length do
      a_str[i] = a_str[i] + {a_str[i][1]}
      if a_str[i][1] = name then position = i
    end
    if position <> null then do
      a_str = ExcludeArrayElements(a_str, position, 1)
      ModifyTable(viewName, a_str)
    end
  end
EndMacro

/*
Recursively searches the directory and any subdirectories for files
unlike TransCADs "GetDirectoryInfo", which only searches top level.

This can be useful for cataloging all the files created by the model.
It is also used by "Recompile UI Check" To search for .rsc files that
might be contained in library-style subfolders.

Inputs:
dir
  String
  The directory to search

ext
  Optional string or array of strings
  extensions to limit the search to.
  e.g. "rsc" or {"rsc", "lst", "bin"}
  If null, finds files of all types.

Output:
An array of complete paths for each file found
*/

Macro "Catalog Files" (dir, ext)

  if TypeOf(ext) = "string" then ext = {ext}

  a_dirInfo = GetDirectoryInfo(dir + "/*", "Directory")

  // If there are folders in the current directory,
  // call the macro again for each one.
  if a_dirInfo <> null then do
    for d = 1 to a_dirInfo.length do
      path = dir + "/" + a_dirInfo[d][1]

      a_files = a_files + RunMacro("Catalog Files", path, ext)
    end
  end

  // If the ext parameter is used
  if ext <> null then do
    for e = 1 to ext.length do
      if Left(ext[e], 1) = "." 
        then path = dir + "/*" + ext[e]
        else path = dir + "/*." + ext[e]

      a_info = GetDirectoryInfo(path, "File")
      if a_info <> null then do
        for i = 1 to a_info.length do
          a_files = a_files + {dir + "/" + a_info[i][1]}
        end
      end
    end
  // If the ext parameter is not used
  end else do
    a_info = GetDirectoryInfo(dir + "/*", "File")
    if a_info <> null then do
      for i = 1 to a_info.length do
        a_files = a_files + {dir + "/" + a_info[i][1]}
      end
    end
  end

  return(a_files)
EndMacro

/*
Simple wrapper to "Catalog Files" that writes out the full path to
every file in given directory (and it's subdirectories) to a csv.

Inputs
  * dir
    * String
    * Directory to document

Returns
  Writes a CSV file listing all files in "dir"
*/

Macro "List Files in CSV" (dir)

  if dir = null then do
    on escape do
      return()
    end
    dir = ChooseDirectory("Choose a Directory to Document", )
    on escape default
  end

  dir = RunMacro("Normalize Path", dir)

  a_files = RunMacro("Catalog Files", dir)
  file = dir + "/list_of_files.csv"
  file = OpenFile(file, "w")
  for f = 1 to a_files.length do
    WriteLine(file, a_files[f])
  end
  CloseFile(file)
EndMacro

/*doc
Uses the batch shell to copy the folders and subfolders from
one directory to another.

Inputs (all in a named array)
  * from
    * String
    * Full path of directory to copy
  * to
    * String
    * Full path of destination
  * copy_files
    * Optional true/false
    * Whether or not to copy files
    * Defaults to true
  * subdirectories
    * Optional true/false
    * Whether or not to include subdirectories
    * Defaults to true
  * purge
   * Optional true/false
   * Whether to delete files in `to` that are no longer present in `from`
   * Defaults to true
*/

Macro "Copy Directory" (MacroOpts)

  from = MacroOpts.from
  to = MacroOpts.to
  copy_files = MacroOpts.copy_files
  subdirectories = MacroOpts.subdirectories
  purge = MacroOpts.purge

  if from = null then Throw("Copy Diretory: 'from' not provided") 
  if to = null then Throw("Copy Diretory: 'from' not provided") 
  if copy_files = null then copy_files = "true"
  if subdirectories = null then subdirectories = "true"
  if purge = null then purge = "true"

  RunMacro("Normalize Path", from)
  RunMacro("Normalize Path", to)

  from = "\"" +  from + "\""
  to = "\"" +  to + "\""
  cmd = "cmd /C robocopy " + from + " " + to
  if !copy_files then cmd = cmd + " /t"
  if subdirectories then cmd = cmd + " /e"
  if purge then cmd = cmd + " /purge"
  opts.Minimize = "true"
  RunProgram(cmd, opts)
EndMacro

/*doc
Uses batch shell to delete everything in a given directory.
Removes entire directory and then recreates it.

Inputs
  * dir
    * String
    * Directory to clear
*/

Macro "Clear Directory" (dir)
  if dir = null then Throw("Clear Directory: 'dir' not provided") 

  dir = "\"" +  dir + "\""
  cmd = "cmd /C rmdir /s /q " + dir
  opts.Minimize = "True"
  RunProgram(cmd, opts)

  cmd = "cmd /C mkdir " + dir
  opts.Minimize = "True"
  RunProgram(cmd, opts)
EndMacro

/*doc
Simple improvement on TCs CreateDirectory(). This only creates a directory if it
doesn't already exist. It does not throw an error like CreateDirectory(). It
also normalizes the path of `dir` (resolves relative paths and removes any
trailing slashes).

Inputs
  * dir
    * String
    * Path of directory to create.
*/

Macro "Create Directory" (dir)
  if dir = null then Throw("Create Directory: 'dir' not provided") 
  dir = RunMacro("Normalize Path", dir)
  if GetDirectoryInfo(dir, "All") = null then CreateDirectory(dir)
EndMacro

/*doc
Base GISDK has a RemoveDirectory(), but the directory must be empty.
This macro will delete the directory including all contents using recursion.

Inputs
  * dir
    * String
    * Complete path of the directory
*/

Macro "Delete Directory" (dir)

  // If there are folders in the current directory,
  // call the macro again for each one.
  a_dir_info = GetDirectoryInfo(dir + "/*", "Directory")
  if a_dir_info <> null then do
    for d = 1 to a_dir_info.length do
      path = dir + "/" + a_dir_info[d][1]

      RunMacro("Delete Directory", path)
    end
  end

  // Delete all files in the directory before deleting the directory itself
  a_file_info = GetDirectoryInfo(dir + "/*", "File")
  if a_file_info <> null then do
    for i = 1 to a_file_info.length do
      DeleteFile(dir + "/" + a_file_info[i][1])
    end
  end
  RemoveDirectory(dir)
EndMacro

/*doc
Creates a zip archive of the contents of the directory specified. This requires
powershell and may not work on older versions of it (e.g. Windows 7). Failure
does not cause a crash; `dir` simply won't be zipped.

Inputs
  * `dir`
    * String
    * Full path to directory to zip
  * `archive_file`
    * Optional string
    * Full path to the zip file to be created.
    * Defaults to `dir + ".zip"`
*/

Macro "Zip Directory" (dir, archive_file)
  
  if dir = null then do
    on escape do
      return()
    end
    dir = ChooseDirectory("Choose the gisdk_tools folder to compile", )
    on escape default
  end
  dir = RunMacro("Normalize Path", dir)
  if archive_file = null then archive_file = dir + ".zip"
  archive_file = RunMacro("Normalize Path", archive_file)
  dir = "\"" + dir + "\""
  archive_file = "\"" + archive_file + "\""
  
  cmd = "powershell " +
    "Get-Childitem " + dir + " | " +
    "Compress-Archive -DestinationPath " + archive_file + " -Force"
  RunProgram(cmd, )
EndMacro

/*doc
An alternative to Caliper's JoinTableToLayer() macro (now works as of TC 8).
This version is a little more flexible and intuitive.

Inputs
  * masterFile
    * String
    * Full path of master geographic or binary file
  * mID
    * String
    * Name of master field to use for join.
  * slaveFile
    * String
    * Full path of slave table.  Can be FFB or CSV.
  * sID
    * String
    * Name of slave field to use for join.
  * overwrite
    * Boolean
    * Whether or not to replace any existing
    * fields with joined values.  Defaults to true.
    * If false, the fields will be added with ":1".

Returns
Nothing. Permanently appends the slave data to the master table.

Example application
Attaching an SE data table to a TAZ layer
*/

Macro "Join Table To Layer" (masterFile, mID, slaveFile, sID, overwrite)

  if overwrite = null then overwrite = "True"

  // Determine master file type
  path = SplitPath(masterFile)
  if path[4] = ".dbd" then type = "dbd"
  else if path[4] = ".bin" then type = "bin"
  else Throw("Master file must be .dbd or .bin")

  // Open the master file
  if type = "dbd" then do
    {nlyr, master} = GetDBLayers(masterFile)
    master = AddLayerToWorkspace(master, masterFile, master)
    nlyr = AddLayerToWorkspace(nlyr, masterFile, nlyr)
  end else do
    masterDCB = Substitute(masterFile, ".bin", ".DCB", )
    master = OpenTable("master", "FFB", {masterFile, })
  end

  // Determine slave table type and open
  path = SplitPath(slaveFile)
  if path[4] = ".csv" then s_type = "CSV"
  else if path[4] = ".bin" then s_type = "FFB"
  else Throw("Slave file must be .bin or .csv")
  slave = OpenTable("slave", s_type, {slaveFile, })

  // If mID is the same as sID, rename sID
  if mID = sID then do
    // Can only modify FFB tables.  If CSV, must convert.
    if s_type = "CSV" then do
      tempBIN = GetTempFileName("*.bin")
      ExportView(slave + "|", "FFB", tempBIN, , )
      CloseView(slave)
      slave = OpenTable("slave", "FFB", {tempBIN, })
    end

    str = GetTableStructure(slave)
    for s = 1 to str.length do
      str[s] = str[s] + {str[s][1]}

      str[s][1] = if str[s][1] = sID then "slave" + sID
        else str[s][1]
    end
    ModifyTable(slave, str)
    sID = "slave" + sID
  end

  // Remove existing fields from master if overwriting
  if overwrite then do
    {a_mFields, } = GetFields(master, "All")
    {a_sFields, } = GetFields(slave, "All")

    for f = 1 to a_sFields.length do
      field = a_sFields[f]
      if field <> sID & ArrayPosition(a_mFields, {field}, ) <> 0
        then RunMacro("Remove Field", master, field)
    end
  end

  // Join master and slave. Export to a temporary binary file.
  jv = JoinViews("perma jv", master + "." + mID, slave + "." + sID, )
  SetView(jv)
  a_path = SplitPath(masterFile)
  tempBIN = a_path[1] + a_path[2] + "temp.bin"
  tempDCB = a_path[1] + a_path[2] + "temp.DCB"
  ExportView(jv + "|", "FFB", tempBIN, , )
  CloseView(jv)
  CloseView(master)
  CloseView(slave)

  // Swap files.  Master DBD files require a different approach
  // from bin files, as the links between the various database
  // files are more complicated.
  if type = "dbd" then do
    // Join the tempBIN to the DBD. Remove Length/Dir fields which
    // get duplicated by the DBD.
    opts = null
    opts.Ordinal = "True"
    JoinTableToLayer(masterFile, master, "FFB", tempBIN, tempDCB, mID, opts)
    master = AddLayerToWorkspace(master, masterFile, master)
    nlyr = AddLayerToWorkspace(nlyr, masterFile, nlyr)
    RunMacro("Remove Field", master, "Length:1")
    RunMacro("Remove Field", master, "Dir:1")

    // Re-export the table to clean up the bin file
    new_dbd = a_path[1] + a_path[2] + a_path[3] + "_temp" + a_path[4]
    {l_names, l_specs} = GetFields(master, "All")
    {n_names, n_specs} = GetFields(nlyr, "All")
    opts = null
    opts.[Field Spec] = l_specs
    opts.[Node Name] = nlyr
    opts.[Node Field Spec] = n_specs
    ExportGeography(master + "|", new_dbd, opts)
    DropLayerFromWorkspace(master)
    DropLayerFromWorkspace(nlyr)
    DeleteDatabase(masterFile)
    CopyDatabase(new_dbd, masterFile)
    DeleteDatabase(new_dbd)

    // Remove the sID field
    master = AddLayerToWorkspace(master, masterFile, master)
    RunMacro("Remove Field", master, sID)
    DropLayerFromWorkspace(master)

    // Delete the temp binary files
    DeleteFile(tempBIN)
    DeleteFile(tempDCB)
  end else do
    // Remove the master bin files and rename the temp bin files
    DeleteFile(masterFile)
    DeleteFile(masterDCB)
    RenameFile(tempBIN, masterFile)
    RenameFile(tempDCB, masterDCB)

    // Remove the sID field
    view = OpenTable("view", "FFB", {masterFile})
    RunMacro("Remove Field", view, sID)
    CloseView(view)
  end

EndMacro

/*doc
This function is deprecated and will be removed. Use "Join Table To Layer".
*/

Macro "Perma Join"
  Throw(
    "'Perma Join' is deprecated. The function is now called \n" +
    "'Join Table To Layer'."
  )
EndMacro

/*doc
General macro to run R scripts from GISDK.  Creates a batch to run the script.
If the script fails, it adds a pause to the batch and re-runs so the error is
visible.

Inputs
  * rscriptexe
    * String
    * Path to "Rscript.exe"
  * rscript
    * String
    * Path to the actual r script "*.R"
  * OtherArgs
    * Optional array
    * Array of other arguments to pass to the R environment. These arguments will be
      specific to the R script run.
*/

Macro "Run R Script" (rscriptexe, rscript, OtherArgs)

  // Create the command line call
  // Put each argument in quotes to handle potential spaces
  command = "\"" + rscriptexe + "\" \"" + rscript + "\""
  for i = 1 to OtherArgs.length do
    command = command + " \"" + OtherArgs[i] + "\""
  end

  // Create a batch file to run the R script
  batFile = GetTempFileName(".bat")
  bat = OpenFile(batFile,"w")
  WriteLine(bat,command)
  CloseFile(bat)

  // Run the batch file
  opts = null
  opts.Minimize = "True"
  ret = RunProgram(batFile, opts)

  // If the batch script fails, re-run it with a pause
  if ret <> 0 then do

    bat = OpenFile(batFile,"a")
    WriteLine(bat, "pause")
    CloseFile(bat)
    RunProgram(batFile, )

    a_path = SplitPath(rscript)
    file = a_path[3] + a_path[4]

    Throw(
      file + " did not run sucessfully.\n" +
      "It was re-run with a pause included to view the error."
      )
  end
EndMacro

/*
Adds a field.  Replacement for hidden "TCB Add View Fields", which has
some odd behavior.  Takes the same field info array.  See ModifyTable()
for the 12 potential elements.

view
  String
  view name

a_fields
  Array of arrays
  Each sub-array contains the 12-elements that describe a field.
  e.g. {{"Density", "Real", 10, 3, , , , "Used to calculate initial AT"}}
  (See ModifyTable() TC help page for full array info)

initial_values
  Number, string, or array of numbers/strings (optional)
  If not provided, any fields to add that already exist in the table will not be
  modified in any way. If provided, the added field will be set to this value.
  This can be used to ensure that a field is set to null, zero, etc. even if it
  already exists.
*/

Macro "Add Fields" (view, a_fields, initial_values)

  // Argument check
  if view = null then Throw("'view' not provided")
  if a_fields = null then Throw("'a_fields' not provided")
  for field in a_fields do
    if field = null then Throw("An element in the 'a_fields' array is missing")
  end
  if initial_values <> null then do
    if TypeOf(initial_values) <> "array" then initial_values = {initial_values}
    if TypeOf(initial_values) <> "array"
      then Throw("'initial_values' must be an array")
  end

  // Get current structure and preserve current fields by adding
  // current name to 12th array position
  a_str = GetTableStructure(view)
  for s = 1 to a_str.length do
    a_str[s] = a_str[s] + {a_str[s][1]}
  end
  for f = 1 to a_fields.length do
    a_field = a_fields[f]

    // Test if field already exists (will do nothing if so)
    field_name = a_field[1]
    exists = "False"
    for s = 1 to a_str.length do
      if a_str[s][1] = field_name then do
        exists = "True"
        break
      end
    end

    // If field does not exist, create it
    if !exists then do
      dim a_temp[12]
      for i = 1 to a_field.length do
        a_temp[i] = a_field[i]
      end
      a_str = a_str + {a_temp}
    end
  end

  ModifyTable(view, a_str)

  // Set initial field values if provided
  if initial_values <> null then do
    nrow = GetRecordCount(view, )
    for f = 1 to initial_values.length do
      field = a_fields[f][1]
      type = a_fields[f][2]
      init_value = initial_values[f]

      if type = "Character" then type = "String"

      opts = null
      opts.Constant = init_value
      v = Vector(nrow, type, opts)
      SetDataVector(view + "|", field, v, )
    end
  end
EndMacro

/*
table   String Can be a file path or view of the table to modify
field   Array or string
string  Array or string
*/

Macro "Add Field Description" (table, field, description)

  if table = null or field = null or description = null then Throw(
    "Missing arguments to 'Add Field Description'"
    )
  if TypeOf(field) = "string" then field = {field}
  if TypeOf(description) = "string" then description = {description}
  if field.length <> description.length then Throw(
    "The same number of fields and descriptions must be provided."
  )
  isView = RunMacro("Is View", table)

  // If the table variable is not a view, then attempt to open it
  if isView = "no" then table = OpenTable("table", "FFB", {table})

  str = GetTableStructure(table)
  for f = 1 to str.length do
    str[f] = str[f] + {str[f][1]}
    name = str[f][1]

    pos = ArrayPosition(field, {name}, )
    if pos <> 0 then str[f][8] = description[pos]
  end
  ModifyTable(table, str)

  // If this macro opened the table, close it
  if isView = "no" then CloseView(table)
EndMacro

/*
Renames a field in a TC view

Inputs
  view_name
    String
    Name of view to modify

  current_name
    String
    Name of field to rename

  new_name
    String
    New name to use
*/

Macro "Rename Field" (view_name, current_name, new_name)

  // Argument Check
  if view_name = null then Throw("Rename Field: 'view_name' not provided")
  if current_name = null then Throw("Rename Field: 'current_name' not provided")
  if new_name = null then Throw("Rename Field: 'new_name' not provided")

  // Get and modify the field info array
  a_str = GetTableStructure(view_name)
  field_modified = "false"
  for s = 1 to a_str.length do
    a_field = a_str[s]
    field_name = a_field[1]

    // Add original field name to end of field array
    a_field = a_field + {field_name}

    // rename field if it's the current field
    if field_name = current_name then do
      a_field[1] = new_name
      field_modified = "true"
    end

    a_str[s] = a_field
  end

  // Modify the table
  ModifyTable(view_name, a_str)

  // Throw error if no field was modified
  if !field_modified
    then Throw(
      "Rename Field: Field '" + current_name +
      "' not found in view '" + view_name + "'"
    )
EndMacro

/*
Tests whether or not a string is a view name or not
*/

Macro "Is View" (string)

  a_views = GetViewNames()
  if ArrayPosition(a_views, {string}, ) = 0 then return("false")
  if ArrayPosition(a_views, {string}, ) = 0 then return("false")
  else return("true")
EndMacro


/*
Many steps in the model boil down to simply aggregating/disaggregating
fields - sometimes applying a factor during the process. This macro allows
this to be done with a parameter file.

Note: if a more-complex formula is needed, see "Calculate Fields".

MacroOpts
  Options array
  Contains all required arguments

  MacroOpts.tbl
    String or gplyr data frame
    Either a path to a table file (bin or csv) where the cross walk will take
    place or a gplyr data frame.

  MacroOpts.equiv_tbl
    The CSV file used to convert.  Must have a "from_field", "to_field", "to_desc",
    and "from_factor" columns.  Data in the from_field is added into to_field
    after applying the factor.  "to_desc" is used as the field description for the
    "to_field" and helps users understand model output.

    Each row of the table generates the following formula:
    to_field = to_field + factor * from_field

  MacroOpts.field_prefix
  MacroOpts.field_suffix
    Optional String
    Prefix/Suffix applied to "from_field" and "to_field" when getting/setting
    values. Commonly used to prevent the equiv_tbl from repeating itself over
    things like time of day.  For example, if HBS is being collapsed into HBO,
    and you don't want the equiv table to look like this:

    from_field  to_field  ...
    HBS_AM      HBO_AM
    HBS_MD      HBO_MD
    ...

    Simply have the equiv table look like this:

    to_field  from_field  ...
    HBO       HBS

    And loop over time of day passing the suffix into the function for each
    period. e.g.

    opts.tbl = tbl
    opts.equiv_tbl = equiv_tbl
    opts.suffix = "_AM"
    RunMacro("Field Crosswalk", opts)
    opts.suffix = "_MD"
    RunMacro("Field Crosswalk", opts)
    ...

    The macro will look for "HBS_AM" in the table and convert to "HBO_AM".
*/

Macro "Field Crosswalk" (MacroOpts)
  Throw("'Field Crosswalk' is deprecated. See 'Calculate Fields - Simple'")
EndMacro

/*doc
Uses a specially-formatted parameter file to quickly calculate fields from
other fields multiplied by factors. Useful for simple equilency operations
or when the factors themselves are the parameters of interest
(e.g. production/attraction rates).

Inputs (all in a named array)
  * `table`
    * String or gplyr data frame
    * Either a path to a table file (bin or csv) or the data frame where the cross
      walk will take place.
  * `param_file`
    * String
    * The CSV file used to convert.  Must have a "from_field", "to_field",
      "to_desc", and "from_factor" columns.  Data in the from_field is added into
      to_field after applying the factor.  "to_desc" is used as the field
      description for the "to_field" and helps users understand model output.
    * Each row of the table generates the following formula:  
      to_field = to_field + factor * from_field
  * `expr_vars`
    * Optional named array
    * Used to evaluate {variables} found in `equiv_tbl`  
  * `skip_missing`
    * Optional true/false
    * If true, will skip over any rows where the `from_field` isn't present in
      `table`.
    * If false (default), will throw an error if fields are missing.    
  * `start_fields_at_zero`
    * Optional true/false
    * True by default. Sets all 'to_field' entries to zero before executing
      the parameter file. This prevents multiple calls to the macro from
      incrementing the fields repeatedly. Set to False if that is desired.
      If, however, a 'to_field' is listed multiple times in 'param_file', it will
      increment.
*/

Macro "Calculate Fields - Simple" (MacroOpts)

  // Argument extraction
  table = MacroOpts.table
  param_file = MacroOpts.param_file
  expr_vars = MacroOpts.expr_vars
  skip_missing = MacroOpts.skip_missing
  start_fields_at_zero = MacroOpts.start_fields_at_zero

  // Argument checking
  type = TypeOf(table)
  if type <> "object" then do
    if type = "string" then do
      table_file = table
      {drive, directory, name, ext} = SplitPath(table_file)
      table = CreateObject("df")
      if ext = ".csv"
        then do
          type = "csv"
          table.read_csv(table_file)
        end else if ext = ".bin" then do
          type = "bin"
          table.read_bin(table_file)
        end else Throw("'table' must be bin, csv, or gplyr data frame")
    end else Throw("'table' must be bin, csv, or gplyr data frame")
  end
  if param_file = null then Throw("'param_file' not provided")
  if TypeOf(param_file) <> "string" then Throw("'param_file' must be a string")
  if GetFileInfo(param_file) = null then Throw("'param_file' does not exist")
  {drive, directory, name, ext} = SplitPath(param_file)
  if ext <> ".csv" then Throw("'param_file' must be a CSV file")
  param = CreateObject("df")
  param.read_csv(param_file, , expr_vars)
  fields = {"to_field", "to_desc", "from_field", "from_factor"}
  for field in fields do
    if !(param.in(field, param.colnames()))
      then Throw("Required field '" + field + "' missing from 'param_file'")
  end
  param.filter("to_field <> null and from_field <> null and from_factor <> null")
  for from_field in param.tbl.from_field do
    if table.tbl.(from_field).type = null then do
      if skip_missing then param.filter("from_field <> '" + from_field + "'")
      else Throw("Field '" + from_field + "' not found in 'table'")
    end
  end
  if start_fields_at_zero = null then start_fields_at_zero = "true"

  // Initialize each to_field in the data frame
  for to_field in param.tbl.to_field do
    if table.tbl.(to_field) <> null and start_fields_at_zero
      then table.mutate(to_field, 0)
    if table.tbl.(to_field) = null
      then table.mutate(to_field, 0)
  end

  for r = 1 to param.nrow() do
    {to_field, field_desc, from_field, factor} = param.get_row(r, fields, "false")

    table.tbl.(to_field) = table.tbl.(to_field) + 
      nz(table.tbl.(from_field)) * factor
    if field_desc <> null then table.desc.(to_field) = field_desc
  end

  if type = "object" then return(table)
  if type = "csv" then table.write_csv(table_file)
  if type = "bin" then table.update_bin(table_file)
EndMacro

/*
This function uses a parameter table to calculate fields based on formulas.
Useful for complex functions.

Note: if simply combining fields (with optional factors), see
"Calculate Fields - Simple".

Inputs
  MacroOpts
    Named array containing all arguments for the function

    table
      String
      Either:
        Path to bin/dbd file where field will be added.
        Name of a view already open.

    param_file
      String
      Path to csv paramter table that contains formulas to use.

      e.g.
      to_field  field_desc        formula                aggregation
      HBW       HBW productions   hh1 * 1 + Pow(hh2, 2)  null

      'to_field' is the name of the new field that is created.
      'field_desc' is the field description of the new field.
      'formula' is the expression that will be evaluated.
      'aggregation' is an optional field. After evaluating the formula, the
        function in `aggregation` will summarize the table column. For example,
        "Sum" would evaluate `formula`, sum up the results, and place that value
        in every row of the table. The allowable aggregation values are the same
        as those accepted by VectorStatistic(). Most common are "Sum", "Min",
        "Max", and "Mean".

    expr_vars
      Optional named string
      Used to evaluate variables found in param_file. See macro "Normalize
      Expression" for more detail.
*/

Macro "Calculate Fields" (MacroOpts)

  // Argument extraction
  table = MacroOpts.table
  param_file = MacroOpts.param_file
  expr_vars = MacroOpts.expr_vars

  // Argument checking
  if table = null then Throw("'table' not provided")
  is_view = RunMacro("Is View", table)
  if is_view then do
    {class, spec} = GetViewTableInfo(table)
    if class <> "FFB" and class <> "DBASE"
      then Throw("View 'table' must be from a BIN or DBD file to be modified")
  end else do
    {dir, path, name, ext} = SplitPath(table)
    if Lower(ext) = ".bin" then is_bin = "true"
    else if Lower(ext) = ".dbd" then is_dbd = "true"
    else Throw("'table' must be either a BIN or DBD file to be modified")
  end
  if param_file = null then Throw("'param_file' not provided")
  {dir, path, name, ext} = SplitPath(param_file)
  if ext <> ".csv" then Throw("'param_file' must be a .csv file")

  // Open the table
  if is_view then view = table
  else if is_bin then view = OpenTable("view", "FFB", {table})
  else if is_dbd then do
    a_layers = GetDBLayers(table)
    // TAZ DBDs have 1 layer, Link DBDs have two.
    if a_layers.length = 1 then view = a_layers[1] else view = a_layers[2]
    view = AddLayerToWorkspace(view, table, view)
  end

  // Open paramter table
  params = CreateObject("df")
  params.read_csv(param_file, , expr_vars)
  req_fields = {"to_field", "field_desc", "formula"}
  colnames = params.colnames()
  for req_field in req_fields do
    if !params.in(req_field, colnames)
      then Throw("Column '" + req_field + "' missing from 'param_file'")
  end

  for r = 1 to params.nrow() do
    to_field = params.tbl.to_field[r]
    field_desc = params.tbl.field_desc[r]
    formula = params.tbl.formula[r]
    if TypeOf(params.tbl.aggregation) <> "null"
      then aggregation = params.tbl.aggregation[r]

    // Verify expression (and get info about it)
    {type, width} = VerifyExpression(view, formula)

    // Create a new field and delete if it already exists. This prevents type
    // problems from occuring when changing formulas during model development.
    {field_names, field_specs} = GetFields(view, "All")
    if params.in(to_field, field_names)
      then RunMacro("Remove Field", view, to_field)
    if type = "String" then do
      type2 = "Character"
      constant = null
    end else do
      type2 = type
      constant = 0
    end
    a_fields = {{to_field, type2, width, 3, , , , field_desc}}

    RunMacro("Add Fields", view, a_fields, constant)

    // Create a temporary expression field
    opts = null
    opts.Type = type
    opts.Width = width
    exp_field = CreateExpression(view, "temp", formula, opts)

    v = GetDataVector(view + "|", "temp", )

    // If an aggregation was provided, summarize the entire vector
    if aggregation <> null then do
      constant = VectorStatistic(v, aggregation, )
      opts = null
      opts.Constant = constant
      v = Vector(v.length, type2, opts)
    end

    // Set expression result into permanent field and destroy expression field
    SetDataVector(view + "|", to_field, v, )
    DestroyExpression(view + "." + exp_field)
  end

  if is_bin then CloseView(view)
  else if is_dbd then DropLayerFromWorkspace(view)
EndMacro

/*
Similar to "Calculate Fields - Simple"

Note: if a more-complex formula is needed, see "Calculate Cores".

Inputs (all in named array)
  * `from_mtx`
    * String
    * Full path to matrix file to take cores from
  * `to_mtx`
    * String
    * Full path to matrix file where cores will be added.
  * `to_mtx_label`
    * Optional string
    * Name/Label to assign to to_mtx. By default, uses
      "Created by Matrix Crosswalk"
  * `equiv_tbl`
    * String
    * Full path to parameter CSV files that describes crosswalk
  * `expr_vars`
    * Optional named array
    * Used to evaluate {variables} found in `equiv_tbl`
  * `skip_missing`
    * Optional true/false
    * If true, will skip over any rows where the `from_core` isn't present in
      `from_mtx`.
    * If false (default), will throw an error if cores are missing.
  * `delete_existing_output`
    * Optional true/false
    * True (default): the output matrix is deleted if it already exists.
    * False: the output matrix is not deleted. This means that the output
      matrix will build up with repeated calls to this macro.
*/

Macro "Matrix Crosswalk" (MacroOpts)

  from_mtx = MacroOpts.from_mtx
  to_mtx = MacroOpts.to_mtx
  equiv_tbl = MacroOpts.equiv_tbl
  expr_vars = MacroOpts.expr_vars
  skip_missing = MacroOpts.skip_missing
  to_mtx_label = MacroOpts.to_mtx_label
  delete_existing_output = MacroOpts.delete_existing_output

  if from_mtx = null then Throw("'from_mtx' not provided")
  if to_mtx = null then Throw("'to_mtx' not provided")
  if equiv_tbl = null then Throw("'equiv_tbl' not provided")
  if to_mtx_label = null then to_mtx_label = "Created by Matrix Crosswalk"
  if delete_existing_output = null then delete_existing_output = "true"
  param = CreateObject("df")
  param.read_csv(equiv_tbl, , expr_vars)
  from_mtx = OpenMatrix(from_mtx, )
  a_from_curs = CreateMatrixCurrencies(from_mtx, , , )
  from_cores = V2A(param.unique(param.tbl.from_core))
  for from_core in from_cores do
    if a_from_curs.(from_core) = null then do
      if skip_missing then param.filter("from_core <> '" + from_core + "'")
      else Throw(
        "Matrix Crosswalk: Core '" + from_core + "' not found in 'from_mtx'")
    end
  end
  
  // Get from-core, to-core, and factor
  v_to_core = param.tbl.to_core
  v_from_core = param.tbl.from_core
  v_from_fac = param.tbl.from_factor

  // Create/Open matrix
  if delete_existing_output then do
    if GetFileInfo(to_mtx) <> null then DeleteFile(to_mtx)
    create_matrix = "true"
  end else do
    if GetFileInfo(to_mtx) = null then create_matrix = "true"
    else to_mtx = OpenMatrix(to_mtx, )
  end
  if create_matrix then do
    opts = null
    opts.[File Name] = to_mtx
    opts.Label = to_mtx_label
    opts.Tables = {v_to_core[1]}
    to_mtx = CopyMatrixStructure({a_from_curs.(v_from_core[1])}, opts)
  end
  
  {to_ri, to_ci} = GetMatrixIndex(to_mtx)

  // Loop over every row of the equiv_tbl
  for c = 1 to v_to_core.length do
    to_core = v_to_core[c]
    from_core = v_from_core[c]
    factor = v_from_fac[c]

    // Create the to core if it doesn't already exist and create currency
    a_corenames = GetMatrixCoreNames(to_mtx)
    if ArrayPosition(a_corenames, {to_core}, ) = 0 then
      AddMatrixCore(to_mtx, to_core)
    to_cur = CreateMatrixCurrency(to_mtx, to_core, to_ri, to_ci, )

    // Calculate the new core
    to_cur := nz(to_cur) + nz(a_from_curs.(from_core)) * factor
  end
EndMacro

/*
Calculates matrix cores by reading formulas from a parameter file. All cores
must be in the same matrix file, and the formula is applied to all cells.

Note: if just combining cores (with optional factors) see "Matrix Crosswalk".

Inputs
  MacroOpts
    Named array containing all arguments for the function

    mtx_file
      String
      Path to the base matrix

    param_file
      String
      Path to the parameter csv file. e.g.:

      to_core     formula
      core_a      core_b + .25 * [core c]

      *Note that spaces or other non-standard characters in a core name require
      it to be surrounded in brackets

    expr_vars
      Optional named string
      Used to evaluate variables found in param_file. See macro "Normalize
      Expression" for more detail.
*/

Macro "Calculate Cores" (MacroOpts)

  mtx_file = MacroOpts.mtx_file
  param_file = MacroOpts.param_file
  expr_vars = MacroOpts.expr_vars

  params = CreateObject("df")
  params.read_csv(param_file, , expr_vars)

  mtx = OpenMatrix(mtx_file, )

  for r = 1 to params.nrow() do
    to_core = params.tbl.to_core[r]
    formula = params.tbl.formula[r]

    RunMacro("Add Cores", mtx, to_core)
    cur = CreateMatrixCurrency(mtx, to_core, , , )
    EvaluateMatrixExpression(cur, formula, , , )
  end
EndMacro

/*doc
Enhanced version of TCs AddMatrixCore(). If the core already exists,
it is left alone instead of causing an error. Use `initial_values` to reset the
core to 0 (or null) if that is desired.

Inputs
  * string or matrix handle
    * Either a string pointing the matrix file to modify or it's handle.
  * cores
    * String or array of strings
    * Name of core(s) to add.
  * initial_values
    * Optional number or array of numbers
    * Values to fill the new cores with (must be numeric)
*/

Macro "Add Cores" (mtx, cores, initial_values)

  // Argument check
  if mtx = null then Throw("'mtx' not provided")
  if cores = null then Throw("'cores' not provided")
  if TypeOf(mtx) = "string" then mtx = OpenMatrix(mtx, )
  if TypeOf(cores) = "string" then cores = {cores}
  if initial_values <> null then do
    if TypeOf(initial_values) <> "array" then initial_values = {initial_values}
    if initial_values.length <> cores.length
      then Throw("If provided, 'initial_values' must be same length as 'cores'")
  end

  // Get matrix cores
  a_current_cores = GetMatrixCoreNames(mtx)

  // Loop over each core to add
  for c = 1 to cores.length do
    core = cores[c]

    // Add the new core if it doesn't exist
    pos = ArrayPosition(a_current_cores, {core}, )
    if pos = 0 then AddMatrixCore(mtx, core)

    // Set initial value if provided
    if initial_values <> null then do
      cur = CreateMatrixCurrency(mtx, core, , , )
      cur := initial_values[c]
    end
  end
EndMacro

/*doc
Calculates the RMSE and %RMSE of two vectors.

Inputs
  * v_target
    * Vector
    * First vector to use in calculation.
  * v_compare
    * Vector
    * Second vector to use in calculation.
    
Returns
  * Array in form of {RMSE, %RMSE}
*/

Macro "Calculate Vector RMSE" (v_target, v_compare)

  // Argument check
  if v_target.length = null then Throw("Missing 'v_target'")
  if v_compare.length = null then Throw("Missing 'v_compare'")
  if TypeOf(v_target) = "array" then v_target = A2V(v_target)
  if TypeOf(v_compare) = "array" then v_target = A2V(v_compare)
  if TypeOf(v_target) <> "vector" then Throw("'v_target' must be vector or array")
  if TypeOf(v_compare) <> "vector" then Throw("'v_compare' must be vector or array")
  if v_target.length <> v_compare.length then Throw("Vectors must be the same length")

  n = v_target.length
  tot_target = VectorStatistic(v_target, "Sum", )
  tot_result = VectorStatistic(v_compare, "Sum", )

  // RMSE and Percent RMSE
  diff_sq = Pow(v_target - v_compare, 2)
  sum_sq = VectorStatistic(diff_sq, "Sum", )
  rmse = sqrt(sum_sq / n)
  pct_rmse = 100 * rmse / (tot_target / n)
  return({rmse, pct_rmse})
EndMacro

/*
Takes a path like this:
C:\\projects\\model\\..\\other_model

and turns it into this:
C:\\projects\\other_model

Works whether using "\\" or "/" for directory markers

Also removes any trailing slashes
*/

Macro "Normalize Path" (rel_path)

  a_parts = ParseString(rel_path, "/\\")
  for i = 1 to a_parts.length do
    part = a_parts[i]

    if part <> ".." then do
      a_path = a_path + {part}
    end else do
      a_path = ExcludeArrayElements(a_path, a_path.length, 1)
    end
  end

  for i = 1 to a_path.length do
    if i = 1
      then path = a_path[i]
      else path = path + "\\" + a_path[i]
  end

  return(path)
EndMacro

Macro "Resolve Path" (rel_path)
  Throw("Macro 'Resolve Path' has been renamed to 'Normalize Path'")
EndMacro

/*
Takes a query string and makes sure it is of the form:
"Select * where ...""

Inputs
  query
    String
    A query. Can be "Select * where ID = 1" or just the "ID = 1"

Returns
  A query of the form "Select * where ..."
*/

Macro "Normalize Query" (query)

  if query = null then Throw("Normalize Query: 'query' not provided")

  if Left(query, 15) = "Select * where "
    then return(query)
    else return("Select * where " + query)
EndMacro

/*
Replaces variables in 'expr' (identified with curly brackets) with values
from 'vars'.

Inputs
  expr
    String or array/vector of values
    Expression(s) to resolve. Variables are surrounded in {}. Numerical values
    are left as is.

  vars
    Named array
    Named values in 'vars' will replace the names found in 'expr'

Returns
  result
    An array where any {variables} are replaced.

Example:
  expr = "{scen_dir}/outputs/networks/{period}net.net"
  vars.scen_dir = "Y:\\repo/scenarios/Base_2016"
  vars.period = "AM"
  result = RunMacro("Resolve Expression", expr, vars)
  // result = "Y:\\repo/scenarios/Base_2016/outputs/networks/AMnet.net"
*/

Macro "Normalize Expression" (expr, vars)

  type = TypeOf(expr)
  if type = "string" then expr = {expr}
  else if type = "vector" then expr = V2A(expr)
  else if type <> "array"
    then Throw("'expr' must be a string, array or vector")
  if vars = null then Throw("'vars' not provided")
  if TypeOf(vars) <> "array" then Throw("'vars' not an array")

  for e in expr do
    new_e = null
    if TypeOf(e) <> "string" then new_e = e else do

      // Count how many opening curly brackets are in the expression
      open_bracket_count = 0
      for c in e do
        if c = "{" then open_bracket_count = open_bracket_count + 1
      end

      // Split up the expression and replace parts. Keep track of how many
      // are replaced.
      opts.[Include Empty] = "true"
      a_parts = ParseString(e, "{}")
      replaced_count = 0
      for part in a_parts do
        if vars.(part) <> null
          then do
            new_e = new_e + vars.(part)
            replaced_count = replaced_count + 1
          end else new_e = new_e + part
      end

      // Check that all variables were replaced
      if open_bracket_count <> replaced_count
        then Throw("Variables were found that were not normalized.")
    end
    result = result + {new_e}
  end

  return(result)
EndMacro

/*
Macro to simplify the process of map creation.

Inputs
  MacroOpts
    Named array that holds argument names

    file
      String
      Full path to the file to map. Supported types:
        Point, Line, Polygon geographic files. RTS files.

    minimized
      Optional String ("true" or "false")
      Defaults to "true".
      Whether to minimize the map. Makes a number of geospatial calculations
      faster if the map does not have to be redrawn.

Returns
  An array of two things:
  1. the name of the map
  2. an array of layer names
    * for dbd files: {node, link}
    * for rts files: {route, stops, phys. stops, node, link}
*/

Macro "Create Map" (MacroOpts)

  // Argument extraction
  file = MacroOpts.file
  minimized = MacroOpts.minimized

  // Argument checking
  if file = null then Throw("Create Map: 'file' not provided")
  if minimized = null then minimized = "true"

  // Determine file extension
  {drive, directory, filename, ext} = SplitPath(file)
  if Lower(ext) = ".dbd" then file_type = "dbd"
  else if Lower(ext) = ".rts" then file_type = "rts"
  else Throw("Create Map: 'file' must be either a '.dbd.' or '.rts' file")

  // Get a unique name for the map
  map_name = RunMacro("Get Unique Map Name")

  // Create the map if a dbd file was passed
  if file_type = "dbd" then do
    a_layers = GetDBLayers(file)
    {scope, label, rev} = GetDBInfo(file)
    opts = null
    opts.scope = scope
    map_name = CreateMap(map_name, opts)
    if minimized then MinimizeWindow(GetWindowName())
    for layer in a_layers do
      l = AddLayer(map_name, layer, file, layer)
      RunMacro("G30 new layer default settings", l)
      actual_layers = actual_layers + {l}
    end
  end

  // Create the map if a RTS file was passed
  if file_type = "rts" then do

    // Get the RTS's highway file
    opts = null
    opts.rts_file = file
    hwy_dbd = RunMacro("Get RTS Highway File", opts)
    {scope, label, rev} = GetDBInfo(hwy_dbd)
    opts = null
    opts.Scope = scope
    map = CreateMap(map_name, opts)
    if minimized then MinimizeWindow(GetWindowName())
    {, , opts} = GetRouteSystemInfo(file)
    rlyr = opts.Name
    actual_layers = AddRouteSystemLayer(map, rlyr, file, )
    if !minimized then do
      for layer in actual_layers do
        // Check for null - the physcial stops layer is often null
        if layer <> null then RunMacro("G30 new layer default settings", layer)
      end
    end
  end

  return({map_name, actual_layers})
EndMacro

/*
Helper to "Create Map" macro.
Avoids duplciating map names by using an odd name and checking to make
sure that map name does not already exist.

Similar to "unique_view_name" in gplyr.
*/

Macro "Get Unique Map Name"
  {map_names, idx, cur_name} = GetMaps()
  if map_names.length = 0 then do
    map_name = "gisdk_tools1"
  end else do
    num = 0
    exists = "True"
    while exists do
      num = num + 1
      map_name = "gisdk_tools" + String(num)
      exists = if (ArrayPosition(map_names, {map_name}, ) <> 0)
        then "True"
        else "False"
    end
  end

  return(map_name)
EndMacro

/*
This macro expands the base functionality of SelectNearestFeatures() to perform
a spatial join. Only works on point and area layers. Master and
slave layers must be open in the same (current) map.

Inputs
  MacroOpts
    Named array of macro arguments (e.g. MacroOpts.master_view)

    master_layer
      String
      Name of master layer (left side of table)

    master_set
      Optional string
      Name of selection set of features to be joined. If null, all features
      are joined.

    slave_layer
      String
      Name of the slave layer (right side of table)

    slave_set
      Optional string
      Name of selection set that slave features must be in to be joined.

    threshold
      Optional string
      Maximum distance to search around each feature in the slave layer.
      Defaults to 100 feet.


Returns
  The name of the joined view.
  Also modifies the master table by adding a slave ID field (this is how the
  join is accomplished).
*/

Macro "Spatial Join" (MacroOpts)

  // Argument extraction
  master_layer = MacroOpts.master_layer
  master_set = MacroOpts.master_set
  slave_layer = MacroOpts.slave_layer
  slave_set = MacroOpts.slave_set
  threshold = MacroOpts.threshold

  // Argument checking
  if master_layer = null then Throw("Spatial Join: 'master_layer' not provided")
  if slave_layer = null then Throw("Spatial Join: 'slave_layer' not provided")
  if threshold = null then do
    units = GetMapUnits("Plural")
    threshold = if units = "Miles" then 100 / 5280
      else if units = "Feet" then 100
    if threshold = null then Throw("Map units must be feet or miles")
  end

  // Add fields to the master_layer
  a_fields = {
    {"slave_id", "Integer", 10, ,,,,"used to join to slave layer"},
    {"slave_dist", "Real", 10, 3,,,,"used to join to slave layer"}
  }
  RunMacro("Add Fields", master_layer, a_fields, )

  // Tag the master layer with slave IDs and distances
  TagLayer(
    "Value",
    master_layer + "|" + master_set,
    master_layer + ".slave_id",
    slave_layer + "|" + slave_set,
    slave_layer + ".ID"
  )
  TagLayer(
    "Distance",
    master_layer + "|" + master_set,
    master_layer + ".slave_dist",
    slave_layer + "|" + slave_set,
  )

  // Select records where the tagged distance is greater than the threshol and
  // remove those tagged IDs.
  SetLayer(master_layer)
  qry = "Select * where nz(slave_dist) > " + String(threshold)
  set = CreateSet("set")
  n = SelectByQuery(set, "several", qry)
  if n > 0 then do
    v = Vector(n, "Long", )
    SetDataVector(master_layer + "|" + set, "slave_id", v, )
  end
  DeleteSet(set)

  // Create a joined view based on the slave IDs
  jv = JoinViews("jv", master_layer + ".slave_id", slave_layer + ".ID", )

  SetView(jv)
  return(jv)
EndMacro

/*
Checks a table/view for required fields. Displays which fields, if any, are
missing.

Inputs

  tbl
    String
    View name or path to bin/csv file.

  req_fields
    Array of strings
    Field names of field that 'tbl' must contain.

Returns
  Nothing
  If any fields are missing, an error message will list their names.
*/

Macro "Check View for Required Fields" (tbl, req_fields)

  if !RunMacro("Is View", tbl) then do
    {drive, folder, name, ext} = SplitPath(tbl)
    if Lower(ext) = ".bin" then tbl = OpenTable("view", "FFB", {tbl})
    else if Lower(ext) = ".csv" then tbl = OpenTable("view", "CSV", {tbl})
    else Throw("Only .bin and .csv files are supported.")
  end

  {names, specs} = GetFields(tbl, "All")

  for field in req_fields do
    if ArrayPosition(names, {field}, ) = 0 then missing = missing + " " + field
  end

  if missing <> null then Throw(
    "The following fields are missing from '" + tbl + "': " + missing
  )
EndMacro

/*
Simplified version of TCs CombineMatrices(). If not providing the
'core_prefix' argument, all matrix file names must be unique, even if in
different folders (file name is used to differentiate cores).

Inputs
  MacroOpts
    Named array of all input arguments

    matrices
      Array of strings
      Paths to the matrix files to combine.

    output_matrix
      String
      Where the combined matrix will be stored.

    label
      Optional string
      Matrix label. Defaults to "Combined Matrix"

    delete_orig
      Logical
      Defaults to false: input matrices are not deleted
      true: input matrices are deleted

    core_prefix
      Optional array of strings or 0
      By default, each core is prefixed by the name of the matrix file it came
      from plus a trailing "_". This can be used to override that behavior.
      The array must match the length and order of 'matrices'. Each core in the
      first matrix will get the first prefix in 'core_prefix', etc.

      If 0, no core prefix will be attached, if duplicate core names are found
      it will cause the macro to crash.

Outputs
  A single matrix with cores from all input matrices combined. The matrix file
  names become prefixes. (e.g. the "length" core of "example.mtx" would become
  "example_length")
*/

Macro "GT - Combine Matrices" (MacroOpts)

  // Argument extraction
  matrices = MacroOpts.matrices
  output_matrix = MacroOpts.output_matrix
  label = MacroOpts.label
  delete_orig = MacroOpts.delete_orig
  core_prefix = MacroOpts.core_prefix

  // Argument checking
  if matrices = null
    then Throw("'matrices' not provided")
  if TypeOf(matrices) <> "array"
    then Throw("'matrices' must be an array of matrix file paths")
  if output_matrix = null
    then Throw("'output_matrix' not provided")
  if label = null then label = "Combined Matrix"
  if GetFileInfo(output_matrix) <> null then DeleteFile(output_matrix)
  if core_prefix = null then do
    for matrix in matrices do
      {drive, folder, name, etc} = SplitPath(matrix)
      core_prefix = core_prefix + {name + "_"}
    end
  end
  if TypeOf(core_prefix) = "int" and core_prefix = 0 then do
    opts = null
    opts.Constant = ""
    core_prefix = V2A(Vector(matrices.length, "string", opts))
  end

  for m = 1 to matrices.length do
    mtx_file = matrices[m]
    prefix = core_prefix[m]

    mtx = OpenMatrix(mtx_file, )
    {drive, path, file, ext} = SplitPath(mtx_file)
    a_corenames = GetMatrixCoreNames(mtx)
    a_corenames = V2A(prefix + A2V(a_corenames))
    all_corenames = all_corenames + a_corenames
    a_temp = CreateMatrixCurrencies(mtx, , , )
    for a = 1 to a_temp.length do
      all_curs = all_curs + {a_temp[a][2]}
    end
    mtx = null
    a_corenames = null
    a_temp = null
  end

  opts = null
  opts.[File Name] = output_matrix
  opts.Label = label
  mtx = CombineMatrices(all_curs, opts)
  SetMatrixCoreNames(mtx, all_corenames)

  all_curs = null
  mtx = null
  mtx_file = null
  a_corenames = null
  opts = null
  all_corenames = null

  if delete_orig then do
    for mtx_file in matrices do
      DeleteFile(mtx_file)
    end
  end
EndMacro

/*
Does a very basic diff between two text files. Shows which lines of text
match exactly, the nearest matches for those that don't, and then any
remaining lines after the nearest matches have been exhausted.
*/

Macro "Compare Text Files" (file1, file2)

  {drive1, folder1, name1, ext1} = SplitPath(file1)
  {drive2, folder2, name2, ext2} = SplitPath(file2)
  output_file = drive1 + folder1 + "compare_" + name1 + "_to_" + name2 + ".csv"

  files = {file1, file2}
  for f = 1 to files.length do
    file = OpenFile(files[f], "r")

    while not FileAtEOF(file) do
      line = ReadLine(file)
      array.("file" + String(f)) = array.("file" + String(f)) + {line}
    end
  end

  lines1 = array.file1
  lines2 = array.file2

  for i = 1 to lines1.length do
    line1 = lines1[i]
    match = "false"

    for j = 1 to lines2.length do
      line2 = lines2[j]

      opts.[Case Sensitive] = "true"
      match = CompareStrings(line1, line2, opts)
      if match then do
        matching = matching + {line1}
        lines1 = ExcludeArrayElements(lines1, i, 1)
        i = i-1
        lines2 = ExcludeArrayElements(lines2, j, 1)
        break
      end
    end
  end

  if lines1 = null and lines2 = null then Throw("Files are identical")

  // After removing matching lines, identify the lines in lines2 that most-
  // closely match lines1. Match closeness is determined by how many characters
  // in the string are the same before a difference is found.
  for i = 1 to lines1.length do
    line1 = lines1[i]
    same_char_max = 0
    max_pos = 0

    if lines2 = null then do
      left_over1 = left_over1 + {line1}
      continue
    end

    // Check each line of file2 and determine which most closely matches
    for j = 1 to lines2.length do
      line2 = lines2[j]
      same_char_count = 0

      for c = 1 to StringLength(line1) do
        if c > StringLength(line2) then break
        opts = null
        opts.[Case Sensitive] = "true"
        if CompareStrings(line1[c], line2[c], opts)
          then same_char_count = same_char_count + 1
          else break
      end

      if same_char_count > same_char_max then do
        max_pos = j
        same_char_max = same_char_count
      end
    end

    // If the nearest match had at least 1 common character
    if max_pos > 0 then do
      line2 = lines2[max_pos]
      left = Left(line2, same_char_max)
      right = Right(line2, StringLength(line2) - same_char_max)
      nearest_matches2 = nearest_matches2 + {left + "**" + right}
      left = Left(line1, same_char_max)
      right = Right(line1, StringLength(line1) - same_char_max)
      nearest_matches1 = nearest_matches1 + {left + "**" + right}
      lines2 = ExcludeArrayElements(lines2, max_pos, 1)
    end else left_over1 = left_over1 + {line1}
  end

  left_over2 = CopyArray(lines2)

  // Write out comparison
  file = OpenFile(output_file, "w")
  WriteLine(file, "File1:," + file1)
  WriteLine(file, "File2:," + file2)
  WriteLine(file, "")
  WriteLine(file, "")
  WriteLine(file, "Lines from File1 without exact matches in File2")
  WriteLine(file, "Nearest matches shown underneath")
  WriteLine(file, "A '**' marks the first difference")
  WriteLine(file, "")
  WriteLine(file, "File,String")
  for i = 1 to nearest_matches1.length do
    if i > 1 then WriteLine(file, "")
    WriteLine(file, "File1," + nearest_matches1[i])
    WriteLine(file, "File2," + nearest_matches2[i])
  end

  WriteLine(file, "")
  WriteLine(file, "")
  WriteLine(file, "Additional lines from File1 not matched to File2")
  for line in left_over1 do
    WriteLine(file, line)
  end

  WriteLine(file, "")
  WriteLine(file, "")
  WriteLine(file, "Additional lines from File2 not matched to File1")
  for line in left_over2 do
    WriteLine(file, line)
  end

  WriteLine(file, "")
  WriteLine(file, "")
  WriteLine(file, "Lines that match exactly in File1 and File2")
  for line in matching do
    WriteLine(file, line)
  end

  CloseFile(file)
  ShowMessage(
    "Comparison file written to:\n" +
    output_file
  )
EndMacro

/*doc
Improved version of TransCADs DropMatrixCore(). Mainly, it can drop the
first matrix core. If dropping the first core, the matrix cannot be open
in TransCAD. (This also means you have to pass the matrix path instead of
the handle.)

Inputs
  * matrix
    * String or matrix handle
    * If string, it is the full path to the matrix file.
  * cores
    * String, array, or vector of strings
    * Core(s) to drop.
    
Returns
  * The handle of the matrix.
*/

Macro "Drop Cores" (matrix, cores)

  // Argument check
  if matrix = null then Throw("Drop Cores: 'matrix' is null")
  if TypeOf(matrix) = "string" then do
    if GetFileInfo(matrix) = null then Throw("Drop Cores: 'matrix' not found")
    mtx_file = matrix
    matrix = OpenMatrix(matrix, )
  end else do
    if TypeOf(matrix) <> "matrix" then Throw(
      "Drop Cores: 'matrix' must be either a string or matrix handle")
    mtx_file = matrix.Name
  end
  type = TypeOf(cores)
  if type = "string" then cores = {cores}
    else if type = "vector" then cores = V2A(cores)
      else if type <> "array" then Throw(
        "Drop Cores: 'cores' must be either a string, array, or vector.")
  cores_to_drop = cores
    
  // Check if first core should be dropped
  corenames = GetMatrixCoreNames(matrix)
  first_core = corenames[1]
  position = ArrayPosition(cores_to_drop, {first_core}, )
  if position <> 0 then do
    core_indices = V2A(Vector(corenames.length, "long", {{"Sequence", 1, 1}}))
    core_indices = ExcludeArrayElements(core_indices, 1, 1)
    cur = CreateMatrixCurrency(matrix, corenames[2], , , )
    info = GetMatrixInfo(matrix)
    label = info[6].Label
    
    opts = null
    temp_file = Substitute(mtx_file, ".mtx", "2.mtx", )
    opts.[File Name] = temp_file
    opts.Label = label
    opts.Cores = core_indices
    CopyMatrix(cur, opts)
    matrix = null
    cur = null
    info = null
    if RunMacro("Is Matrix Open", mtx_file) then do
      DeleteFile(temp_file)
      Throw("Drop Cores: Can't drop first core because 'mtx_file' is open.")
    end
    DeleteFile(mtx_file)
    RenameFile(temp_file, mtx_file)
    matrix = OpenMatrix(mtx_file, )
    
    cores_to_drop = ExcludeArrayElements(cores_to_drop, position, 1)
  end
  
  // Drop all cores other than the first.
  for core in cores_to_drop do
    DropMatrixCore(matrix, core)
  end
  
  return(matrix)
EndMacro

/*doc
Checks to see if a matrix file is open in TransCAD.

Inputs
  * mtx_file
    * The matrix file to check.
*/

Macro "Is Matrix Open" (mtx_file)
  {handles, , } = GetMatrices()
  for h = 1 to handles.length do
    handle = handles[h]
    
    if CompareStrings(handle.Name, mtx_file, ) then return("true")
  end
EndMacro

/*doc
Checks a file path for spaces and other special characters that could cause
problems with certain programs.

Inputs
  * path
    * String
    * File path to check

Returns
True or False
*/

Macro "Path has Special Chars" (path)
  reserved = {" ", ".", ",", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")"}
  for reserve in reserved do
    if Position(path, reserve) <> 0 then return("true")
  end
EndMacro

/*doc
Takes a matrix (or array of matrices) and generates a CSV table of stats similar
to the table created by Matrix -> Statistics from the TC drop menu.

Inputs
  * matrices
    * String or array/vector of strings
    * Full paths to matrix files to be summarized.

Returns
  * Returns a gplyr data frame
*/

Macro "Matrix Stats" (matrices)
  
  if matrices = null then Throw("Matrix Statistics: 'matrices' not provided")
  if TypeOf(matrices) = "string" then matrices = {matrices}
  if TypeOf(matrices) = "vector" then matrices = V2A(matrices)
  if TypeOf(matrices) <> "array" then Throw(
    "Matrix Statistics: 'matrices' must be string, array, or vector"
  )
  
  // Create table of statistics
  for mtx_file in matrices do

    // get matrix core names and stats
    {drive, folder, name, ext} = SplitPath(mtx_file)
    mtx = OpenMatrix(mtx_file, )
    a_corenames = GetMatrixCoreNames(mtx)
    a_stats = MatrixStatistics(mtx, )

    // Set data frame rows to be the stats
    for corename in a_corenames do
      stats = a_stats.(corename)

      df_temp = CreateObject("df", stats)
      a_init_colnames = df_temp.colnames()
      df_temp.mutate("matrix", name)
      df_temp.mutate("core", corename)
      df_temp.select({"matrix", "core"} + a_init_colnames)

      if corename = a_corenames[1]
        then df = df_temp.copy()
        else df.bind_rows(df_temp)
    end

    // Attach to final table
    if mtx_file = matrices[1]
      then df_final = df.copy() 
      else df_final.bind_rows(df)

    mtx = null
  end

  // Write out csv
  return(df_final)
EndMacro

/*doc
TransCAD does not have a way to display a warning message while allowing the
code to continue running. This displays a message in a text file window.
*/

Macro "Show Warning" (message)
  temp_file = GetTempFileName(".txt")
  cmd = "cmd /c @echo " + message + " >> " + temp_file + 
    " && start " + temp_file
  RunProgram(cmd, )
EndMacro

/*
Converts anything passed in to an array.
*/

Macro "2A" (thing)
  if TypeOf(thing) = "array" then return(thing)
  thing = if TypeOf(thing) = "vector" then V2A(thing) else {thing}
  return(thing)
EndMacro

/*
Converts anything passed in to a string. If an array of things is passed in,
an array of strings is returned.
*/

Macro "2S" (thing)
  type = TypeOf(thing)
  if type = "string" then return(thing)
  if type = "vector" or type = "array" then do
    for i = 1 to thing.length do
      thing[i] = RunMacro("2S", thing[i])
    end
  end else thing = String(thing)
  return(thing)
EndMacro

/*doc
Simplification of the base TransposeMatrix() function. Transposes all cores
in a matrix file.

Inputs
  * `mtx_file`
    * String
    * Full path to matrix file to be transposed
  * `label`
    * Optional string
    * Label for the resuling, transposed matrix
    
Returns
  Nothing. The matrix file provided will have all cores transposed.
*/

Macro "Transpose Matrix" (mtx_file, label)
  if mtx_file = null then Throw("Transpose Matrix: `mtx_file` not provided")
  if GetFileInfo(mtx_file) = null then Throw(
    "Transpose Matrix: `mtx_file` not found\n" +
    "(" + mtx_file + ")"
  )

  {drive, folder, file, ext} = SplitPath(mtx_file)
  inv_matrix = drive + folder + file + "_inv" + ext
  mtx = OpenMatrix(mtx_file, )
  opts = null
  opts.[File Name] = inv_matrix
  opts.label = label
  TransposeMatrix(mtx, opts)
  mtx = null
  DeleteFile(mtx_file)
  RenameFile(inv_matrix, mtx_file)
EndMacro
