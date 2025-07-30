
// visualize menu items
Class "Visualize.Menu.Items"

    init do 
        self.runtimeObj = CreateObject("Model.Runtime")
    enditem 

    Macro "GetMenus" do
        Menus = {
              { ID: "PPMenu",  Title: "Persons Pivot" , Macro: "Menu_PP_Pivot" }
             ,{ ID: "HHMenu",  Title: "Household Pivot" , Macro: "Menu_HH_Pivot" }
             ,{ ID: "FlowMap", Title: "FlowMap" , Macro: "Menu_FlowMap" }
             ,{ ID: "PTFlows", Title: "PTFlowMap" , Macro: "Menu_PTFlowMap" }
             ,{ ID: "PTOn", Title: "Boarding Heatmap" , Macro: "Menu_PTOn" }
             ,{ ID: "PTOff", Title: "Alighting Heatmap" , Macro: "Menu_PTOff" }
             ,{ ID: "ConvChart", Title: "Convergence Chart" , Macro: "Menu_ConvergenceChart" }
             ,{ ID: "HeatMenu", Title: "Heatmap" , Macro: "Menu_HH_Heatmap" }
             ,{ ID: "ChordMenu", Title: "Chord Diagram" , Macro: "Menu_Chord_Diagram" }
            }
        
        Return(Menus)
    enditem 

    Macro "Menu_Chord_Diagram" do 
        tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        paramName = self.runtimeObj.GetSelectedParamInfo().Name
        TAZGeoFile = self.runtimeObj.GetValue("WorkTAZ")
        self.runtimeObj.RunCode("ChordMap", tableArg, TAZGeoFile, paramName)
    enditem 

    Macro "Menu_HH_Pivot" do 
        tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        self.runtimeObj.RunCode("HH_Pivot", tableArg)
    enditem 
   
    Macro "Menu_PP_Pivot" do 
        tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        self.runtimeObj.RunCode("PP_Pivot", tableArg, opts)
    enditem 

    Macro "Menu_ConvergenceChart" do 
        opts.tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        opts.ChartTitle = self.runtimeObj.GetSelectedParamInfo().Description
        self.runtimeObj.RunCode("ConvergenceChart", opts)
        enditem 

    macro "Menu_Chord" do 
        mName = self.runtimeObj.GetSelectedParamInfo().Value
        TAZGeoFile = self.runtimeObj.GetValue("TG_ZonalTable")
        self.runtimeObj.RunCode("CreateWebDiagram", {MatrixName: mName, TAZDB: TAZGeoFile, DiagramType: "Chord"})
    enditem         

    macro "Menu_Sankey" do 
        mName = self.runtimeObj.GetSelectedParamInfo().Value
        TAZGeoFile = self.runtimeObj.GetValue("TG_ZonalTable")
        self.runtimeObj.RunCode("CreateWebDiagram", {MatrixName: mName, TAZDB: TAZGeoFile, DiagramType: "Sankey"})
    enditem         

    macro "Menu_HH_Heatmap" do 
        tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        self.runtimeObj.RunCode("CreateHeatmap", {TableName: tableArg})
    enditem

    Macro "Menu_FlowMap" do 
        opts.tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        opts.MapTitle = self.runtimeObj.GetSelectedParamInfo().Description
        opts.FlowFields = {"AB_Flow_PCE","BA_Flow_PCE"}
        opts.vocFields = {"AB_VOC","BA_VOC"}
        opts.LineLayer = self.runtimeObj.GetValue("WorkRoadDBD")
        opts.FlowsOnly = false
        opts.vocStyleFile = self.runtimeObj.GetValues().FlowMapStyles

        self.runtimeObj.RunCode("CreateFlowThemes", opts)
    enditem 
    
    Macro "Menu_PTFlowMap" do 
        opts.tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        opts.MapTitle = self.runtimeObj.GetSelectedParamInfo().Description
        opts.FlowFields = {"AB_TransitFlow","BA_TransitFlow"}
        opts.LineLayer = self.runtimeObj.GetValue("WorkRoadDBD")
        opts.FlowsOnly = true
        self.runtimeObj.RunCode("CreateFlowThemes", opts)
    enditem     

    // Boarding/Alighting heatmaps
    Macro "Menu_PTOn" do 
        opts.tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        opts.MapTitle = self.runtimeObj.GetSelectedParamInfo().Description + " - Boarding"
        opts.RS = self.runtimeObj.GetValue("WorkRS")        
        opts.Field = "On"
        self.runtimeObj.RunCode("OnOffHeatMap", opts)
    enditem     

    Macro "Menu_PTOff" do 
        opts.tableArg = self.runtimeObj.GetSelectedParamInfo().Value
        opts.MapTitle = self.runtimeObj.GetSelectedParamInfo().Description + " - Alighting"
        opts.RS = self.runtimeObj.GetValue("WorkRS")        
        opts.Field = "Off"
        self.runtimeObj.RunCode("OnOffHeatMap", opts)
    enditem     
EndClass


// visualize menu items
// Main toolbar menues
MenuItem "Model Menu Item" text: "NRV Model"
    menu "Model Menu"
 
Menu "Model Menu"
    init do
    enditem
 
    MenuItem "CreateScenario" text: "Create Scenario" do
        mr = CreateObject("Model.Runtime")
        Args = mr.GetValues()
        mr.RunCode("Create Scenario", Args)
    enditem

endMenu
