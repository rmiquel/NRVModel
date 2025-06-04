/*doc
This is a simple text file parser that runs through every .rsc file in a
directory (and subdirectories) and pulls out macro names into a markdown file.
To create a sub-page with detailed macro documentation, use a comment block
above the macro like so:

```  
 /*doc  
 These are detailed comments. Markdown is supported  
```  

To not document a macro, use `/*dontdoc` to open the comment block like so:

```
 /*dontdoc  
 Some comments for an internal macro not meant to be called directly.  
```

In addition to creating the .md pages, it can also writes relative paths to all
rsc files to !gisdk_tools.lst in `dir`. This makes it easier to include
gisdk_tools by copy/pasting into a project .lst file.

Inputs
  * `dir`
    * Optional string
    * Full path of the directory to document. All .rsc files inside will be
      documented.
    * If null, will prompt user to select a folder.
  * `create_lst`
    * Optional true/false
    * Whether to create the list file (.lst).
    * If null, will prompt user to choose.
    
Returns
  * The path to the lst file if created.
*/

Macro "docstrings" (dir, create_lst)
  CreateProgressBar("", "false")
  UpdateProgressBar("Running docstrings", 0)


  // Argument checking
  if dir = null and create_lst = null then standalone = "true"
  if dir = null then do
    on escape do
      return()
    end
    dir = ChooseDirectory("Choose a Directory to Document", )
    on escape default
  end
  if create_lst = null then do
    opts = null
    opts.Caption = "Create LST?"
    opts.Buttons = "YesNo"
    opts.Default = 2
    create_lst = MessageBox("Do you want to create an LST file?", opts)
  end

  dir = RunMacro("Normalize Path", dir)
  parts = ParseString(dir, "\\")
  last_part = parts[parts.length]
  lst_file = dir + "/!" + last_part + ".lst"
  lst_file_temp = dir + "/!" + last_part + "_temp.lst"
  comp_file = OpenFile(lst_file_temp, "w")
  out_dir = dir + "/docstring_results"
  if GetDirectoryInfo(out_dir, "All") = null then CreateDirectory(out_dir)
  index_file_path = out_dir + "/All-Functions.md"
  index_file = OpenFile(index_file_path, "w")
  WriteLine(index_file, "*This file created by docstrings.rsc in GT*")

  a_files = RunMacro("Catalog Files", dir, "rsc")
  for i = 1 to a_files.length do
    f = a_files[i]
    UpdateProgressBar("Running docstrings", round(i / a_files.length * 100, 0))
    {drive, directory, name, ext} = SplitPath(f)

    // Write to the .lst file
    rel_path = Substitute(f, dir, "", )
    rel_path = Right(rel_path, StringLength(rel_path) - 1)
    WriteLine(comp_file, rel_path)

    // Write to All-Functions.md
    WriteLine(index_file, "")
    WriteLine(index_file, "## " + name + ext)

    file = OpenFile(f, "r")
    in_comment = "false"
    while not FileAtEOF(file) do
      line_orig = ReadLine(file)

      // Check for a common indentation (the indent of the opening comment mark)
      if !in_comment then do
        trimmed = Trim(line_orig)
        if Left(trimmed, 2) = "/*" then do
          indent = 0
          for c in line_orig do
            if c = " " then indent = indent + 1
            else break
          end
        end
      end  
      line = Right(line_orig, StringLength(line_orig) - indent)
      
      // The in_comment flag prevents example code in comments from being
      // documented as separate macros.
      if Trim(Left(line, 2)) = "/*" then in_comment = "true"
      if Trim(Left(line, 2)) = "*/" then in_comment = "false"
      if Trim(Right(line, 2)) = "*/" then in_comment = "false"

      if Trim(Lower(Left(line, 9))) = "/*dontdoc" then dont_doc = "true"
      if Trim(Lower(Left(line, 5))) = "/*doc" then do
        store_line = "true"
        continue
      end else if Trim(Lower(Left(line, 2))) = "*/" then do
        store_line = "false"
        continue
      end

      if store_line then do
        subpage = subpage + {line}
        continue
      end

      is_macro = Trim(Lower(Left(line, 7))) = "macro \"" and !in_comment
      is_dbox = Trim(Lower(Left(line, 6))) = "dbox \"" and !in_comment
      is_class = Trim(Lower(Left(line, 7))) = "class \"" and !in_comment

      if (is_macro or is_dbox or is_class) and !in_comment then do

        if dont_doc then do
          dont_doc = "false"
          continue
        end

        // Class macros will end with "do". Check and remove that.
        if Right(line, 3) = " do" then line = Left(line, StringLength(line) - 3)
        
        parts = ParseString(line, "\"")
        name = parts[2]
        if parts.length = 3
          then args = Trim(parts[3])
          else args = null  

        if subpage <> null then do
          sub_file_path = Substitute(index_file_path, ".md", "-" + name + ".md", )
          sub_file_path = Substitute(sub_file_path, " - ", "-", )
          sub_file_path = Substitute(sub_file_path, " ", "-", )
          {drive, folder, sub_file_name, ext} = SplitPath(sub_file_path)

          sub_file = OpenFile(sub_file_path, "w")

          WriteLine(sub_file, "**[[Back to All Functions|All-Functions]]**")
          WriteLine(sub_file, "")
          WriteLine(sub_file, "### " + Trim(line))
          WriteLine(sub_file, "")
          for sub_line in subpage do
            WriteLine(sub_file, sub_line)
          end
          CloseFile(sub_file)

          out_line = "  * [[" + name + "|" + sub_file_name + "]]  "
        end else out_line = "  * " + name + "  "

        if is_dbox 
          then out_line = Left(out_line, StringLength(out_line) - 1) + "(GUI)  "
        WriteLine(index_file, out_line)
        subpage = null
      end
    end
    CloseFile(file)
  end
  CloseFile(comp_file)
  CloseFile(index_file)
  
  // if macro completes successfully, copy the temp lst file to the
  // final lst file. This prevents partial overwriting.
  if create_lst then CopyFile(lst_file_temp, lst_file)
  DeleteFile(lst_file_temp)
  DestroyProgressBar()
  if standalone then ShowMessage("Done") 
  if create_lst then return(lst_file)
EndMacro

/*doc
Creates a stand-alone compiled UI of GT ready for client delivery or integration
into their model using `SetLibrary()`. Also runs docstrings to document all
functions and update the .lst file. The markdown docstrings files should be
moved to the wiki repository.

**Note:** Call this using the "Compile" and "Test" buttons on the GISDK
Developer's Toolbar.

Inputs
  * `gt_dir`
    * Optional string
    * Path the gisdk_tools folder
    * If missing, user is prompted to pick a directory
  * `ui`
    * Optional string
    * Path where the compiled UI will be written.
    * If missing, user is prompted to pick a location and file name

Returns
  * Nothing. Creates gisdk_tools.dbd in the gisdk_tools folder.
*/

Macro "Compile GT" (gt_dir, ui)
  
  if gt_dir = null then do
    on escape do
      return()
    end
    gt_dir = ChooseDirectory("Choose the gisdk_tools folder to compile", )
    on escape default
  end
  if ui = null then do
    on escape do
      return()
    end
    opts = null
    opts.[Initial Directory] = gt_dir
    opts.[Suggested Name] = "gisdk_tools"
    ui = ChooseFileName({{"UI", "*.dbd"}}, "Save compiled UI", opts)
    ui = ui_dir + "/gisdk_tools.dbd"
    on escape default
  end
  
  lst_file = RunMacro("docstrings", gt_dir, "true")
  {drive, folder, name, ext} = SplitPath(lst_file)
  ui = drive + folder + "gisdk_tools"
  
  RunMacro("Compile LST to UI", lst_file, ui)
EndMacro

/*doc
Generic function to compile a list file (.lst) to a UI database.

Inputs
  * `lst`
    * String
    * Path to the list (.lst) file (e.g. "C:\compile.lst")
  * `ui`
    * String
    * Path where `lst` will be compiled to (e.g. "C:\ui.dbd")
    
Returns
  * Nothing.
*/

Macro "Compile LST to UI" (lst, ui)
  
  // Remove extension from UI path
  {drive, folder, name, ext} = SplitPath(ui)
  ui = drive + folder + name
  
  cmd = 'rscc -c -u "' + ui + '" ' + '@"' + lst + '"'
  RunProgram(cmd, )
EndMacro
