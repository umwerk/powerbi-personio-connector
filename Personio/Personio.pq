section Personio;

[DataSource.Kind="Personio", Publish="Personio.Publish"]
shared Personio.Contents = Value.ReplaceType(PersonioImpl, PersonioType);

shared endDate = type text meta [
        Documentation.FieldCaption = "End Date",
        Documentation.FieldDescription = "Date, until when you want the data to be fetched (If left empty, data until today's date will be fetched).",
        Documentation.SampleValues = {"yyyy-MM-dd"}
    ];


PersonioType = type function (
    #"Start Date" as (type text meta [
        Documentation.FieldCaption = "Start Date",
        Documentation.FieldDescription = "Date, since when you want the data to be fetched.",
        Documentation.SampleValues = {"yyyy-MM-dd"},
        DataSource.Path = false

    ]),
    optional #"End Date" as (endDate)
    )
    as table meta [
        Documentation.Name = "Enter Start and End date"
    ];

PersonioImpl = (sDate as text, optional endDate as text) as table =>
    let
        unpw = Extension.CurrentCredential(),
        token = fAuth(unpw),
        // IF INPUT FIELD FOR END DATE IS LEFT OPTIONAL, SET CURRENT DATE
        eDate = if endDate = null then Date.ToText(DateTime.Date(DateTime.LocalNow()), "yyyy-MM-dd") else endDate,          

        nav = NavTable({pagedAttendance(token, sDate, eDate), pagedEmployee(token), pagedTimeOffs(token, sDate, eDate), pagedAbsencePeriods(token), 
        requestTimeOffTypes(token), requestDocuments(token), requestProjects(token), requestCustomReports(token)})
    in
        nav;

// MAKING AUTHORIZATION REQUEST WITH ALL NEEDED PARAMETERS, RETURNS THE TOKEN
fAuth = (UNPW) => 
        let
            requestBody = Json.FromValue([
                    client_id = Text.From(UNPW[Username]), 
                    client_secret = Text.From(UNPW[Password])
                ]),
            
            requestHeaders = [
                #"Content-Type" = "application/json", 
                #"Accept" = "*/*", 
                #"X-Personio-Partner-ID"= "UMWERK", 
                #"X-Personio-App-ID"= "POWERBI"
            ],

            requestResponse = Json.Document(Web.Contents("https://api.personio.de/",
                [
                    IsRetry = false,
                    RelativePath = "v1/auth",
                    Headers = requestHeaders,
                    Content = requestBody
                ])
            ),

            responseToken = requestResponse[data],

            tokenText = Record.Field(responseToken, "token")
    in Text.From(tokenText);

// HELPER FUNCTION THAT CREATES A NAVIGATION TABLEIN POWER BI
EmptyTable = #table
    (
        type table 
        [
            Data = text
        ], 
        
        {}
    );

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table => let
        tableType = Value.Type(table),
        
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],

        navigationTable = Value.ReplaceType(table, newTableType)
    in navigationTable;

// NavTable - receives a list of tables, joins into Navigation Table
NavTable = (tables as list) as table =>
    let
        source = #table({"Name", "Data", "ItemKind", "ItemName", "IsLeaf"}, {
            { tables{0}[Name], tables{0}[Data], "Table", "Table", true },
            { tables{1}[Name], tables{1}[Data], "Table", "Table", true },
            { tables{2}[Name], tables{2}[Data], "Table", "Table", true },
            { tables{3}[Name], tables{3}[Data], "Table", "Table", true },
            { tables{4}[Name], tables{4}[Data], "Table", "Table", true },
            { tables{5}[Name], tables{5}[Data], "Table", "Table", true },
            { tables{6}[Name], tables{6}[Data], "Table", "Table", true },
            { tables{7}[Name], tables{7}[Data], "Table", "Table", true }
          
        }),
        navTable = Table.ToNavigationTable(source, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in navTable;

        fnColumns = (token) =>
    let
        requestHeaders = [
            #"Content-Type" = "application/json", 
            #"Accept" = "*/*", 
            #"X-Personio-Partner-ID"= "UMWERK", 
            #"X-Personio-App-ID"= "POWERBI",
            #"authorization"="Bearer "&token
        ],

        data = Web.Contents("https://api.personio.de/", 
        [
            RelativePath = "v1/company/employees/attributes",
            Headers = requestHeaders
        ]),

        requestResponse = Json.Document(data),
        attributesTable = Table.FromRecords(requestResponse[data]),
        result =  Table.InsertRows(attributesTable, 0, {Record.FromList({"id", "ID", "standard", "id"}, {"key", "label", "type", "universal_id"})})
    in
        result[label];

fnExpand = (tableToExpand as table, optional names) =>
    let
        columnIDs = Table.ColumnNames(Table.FromRecords(tableToExpand[attributes])),
        expanded = Table.ExpandRecordColumn(tableToExpand, "attributes", columnIDs, names),
        result = Table.RemoveColumns(expanded, {"ID"})
    in result;

ExpandAllEmployees = (TableToExpand as table, optional ColumnNumber as number) =>
     let
      // set to 0 when calling the function the first time
      ActualColumnNumber = if (ColumnNumber=null) then 0 else ColumnNumber,

      // get column name relating to the column number
      ColumnName = Table.ColumnNames(TableToExpand){ActualColumnNumber},

      // get a list with all of the fields in the column
      ColumnContents = Table.Column(TableToExpand, ColumnName),

      //ColumnFields = Table.ExpandRecordColumn(TableToExpand, ColumnName, {"value"}),

      // loop over each field in the column
      // if the value is a record, get a list of all of the columns in the record
      // get a unique list of all the column names
      ColumnsToExpand = List.Distinct(List.Combine(List.Transform(ColumnContents, 
                         each if _ is record then Record.FieldNames(_) else {}))),

      // are there more fields to expand in this column?
      CanExpandCurrentColumn = List.Count(ColumnsToExpand)>0,

      // if expandable, expand it
      ExpandedTable = if CanExpandCurrentColumn then 
                            if List.Contains(ColumnsToExpand, "first_name") then 
                                Table.ExpandRecordColumn(TableToExpand, Text.From(ColumnName), 
                                    {ColumnsToExpand{1}, ColumnsToExpand{2}, ColumnsToExpand{3}}, {"Supervisor first name", "Supervisor last name", "Supervisor email"})
                            else if ColumnName = "Cost center" then
                                Table.ExpandRecordColumn(
                                    Table.ExpandRecordColumn(
                                        Table.ExpandListColumn(
                                            Table.ExpandRecordColumn(TableToExpand, ColumnName, {ColumnsToExpand{1}})
                                        ,ColumnsToExpand{1})
                                    ,ColumnsToExpand{1}, {"attributes"})
                                 ,"attributes", {"name", "percentage"}, {"Cost Center Name", "Cost Center Percentage"})
                            else if ColumnName = "Absence entitlement" then 
                                Table.ExpandRecordColumn(
                                    Table.ExpandRecordColumn(
                                        Table.ExpandListColumn(
                                            Table.ExpandRecordColumn(TableToExpand, ColumnName, {ColumnsToExpand{1}})
                                        ,ColumnsToExpand{1})
                                    ,ColumnsToExpand{1}, {"attributes"})
                                ,"attributes", {"name", "entitlement"}, {"Absence type", "Entitlement"})
                            else
                                Table.ExpandRecordColumn(TableToExpand, Text.From(ColumnName), 
                                    {ColumnsToExpand{1}}, {ColumnName})
                      else
                          TableToExpand,

      // if expanded, keep the column number, otherwise +1
      NextColumnNumber = if CanExpandCurrentColumn then 
                            ActualColumnNumber 
                         else 
                            ActualColumnNumber + 1,

      // if the column number is now higher than the number of columns in the table
      // then return the table as is
      // otherwise call the function recursively with the expanded table
      OutputTable = if NextColumnNumber > (Table.ColumnCount(ExpandedTable) - 1) 
                         then 
                            ExpandedTable 
                         else
                            ExpandAllEmployees(ExpandedTable, NextColumnNumber)
     in
     OutputTable;

// REQUEST FOR A SINGLE PAGE OF EMPLOYEES LIMIT SET TO 200 (MAXIMUM) 
requestEmployee = (token, offset) =>
    let 
        request = Web.Contents("https://api.personio.de/",
            [
                RelativePath = "v1/company/employees",
                Query = [fields="all", offset=Number.ToText(offset), limit=Number.ToText(200)],
                Headers = [#"authorization"="Bearer "&token , #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"]
            ]),

        data = Json.Document(request),
        //data = Json.Document(request),
        elementNum = data[metadata][total_elements],
        table = Table.FromRecords(data[data]),
        
        //WITH THE RESULTS, FUNCTION ALSO RETURNS NEW TOKEN (ACCESSING IT AS result[Token])        
        record = Record.AddField([], "Data", table),
        result = Record.AddField(record, "numOfLines", elementNum)
    in result;
    
//PAGED EMPLOYEES WITH LIST.GENERATE()
pagedEmployee = (token) =>
    let
        source = "Employees",
        // REPEATING REQUESTS, EACH TIME INCREMENTING OFFSET BY 200 (LIMIT PER PAGE)
        list = List.Generate( () => [x = requestEmployee(token, 0), y = 0],
            each [y] < [x][numOfLines], 
            each [x = requestEmployee(token, y), y = [y] + 200],
            each [x]),
        table = if List.IsEmpty(list) then EmptyTable else Table.FromList(list, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        rawData = Table.ExpandRecordColumn(table, "Column1", {"Data"}),
        attributes = Table.ExpandTableColumn(rawData, "Data", {"attributes"}),
        renamed = fnExpand(attributes, fnColumns(token)),               //USING CUSTOM EXPANDING FUNCTION
        expanded = ExpandAllEmployees(renamed),

        // Add Table to new record and add a column with the name

        result = Record.AddField([], "Data", expanded),
        resultWithName = Record.AddField(result, "Name", source)
    in
        resultWithName;

// MAKING REQUEST FOR A SINGLE PAGE OF ATTENDANCE DATA
requestAttendances = (token, offset, sDate as text, eDate as text) => 
    let

        request = Web.Contents("https://api.personio.de/",
            [
                RelativePath = "v1/company/attendances",
                Query = [start_date = sDate, end_date = eDate, offset=Number.ToText(offset), limit=Number.ToText(200)],
                Headers = [#"authorization"="Bearer "&token, #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"]
            ]),
        data = Json.Document(request),
        elementNum = data[metadata][total_elements],
        headers = Value.Metadata(request),
        table = Table.FromRecords(data[data]),
        
        // RETURNING DATA AND NUMBER OF ELEMENTS IN ATTENDANCE WHICH WE USE FOR PAGING LATER       
        record = Record.AddField([], "Data", table),
        result = Record.AddField(record, "numOfLines", elementNum)

    in
        result;

pagedAttendance = (token, sDate as text, eDate as text) => 
    let
        source = "Attendances",
        // MULTIPLE REQUESTS FOR ATTENDANCE, EACH WITH OFFSET INCREMENTED BY 200 (LIMIT)
        list = List.Generate( () => [x = requestAttendances(token, 0, sDate, eDate), y = 0],
            each [y] < [x][numOfLines], 
            each [x = requestAttendances(token, y, sDate, eDate), y = [y] + 200],
            each [x]),
        table = if List.IsEmpty(list) then EmptyTable else Table.FromList(list, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        rawData = Table.ExpandRecordColumn(table, "Column1", {"Data"}),
        attributes = Table.ExpandTableColumn(rawData, "Data", {"attributes"}),
        // EXPANDING ALL THE COLUMNS
        data = Table.ExpandRecordColumn(attributes, "attributes", {"employee", "date", "start_time", "end_time", "break", "comment", "updated_at", "status", "project", "is_holiday", "is_on_time_off"},
                                                                    {"Employee", "Date", "Start Time", "End Time", "Break", "Comment", "Updated At", "Status", "Project", "Is Holiday", "Is On Time Off"}),
        expandProject = Table.ExpandRecordColumn(data, "Project", {"attributes"}, {"Attributes"}),
        expandProjectAtrributes = Table.ExpandRecordColumn(expandProject, "Attributes", {"name", "active"}, {"Project Name", "Is Active"}),


        result = Record.AddField([], "Data", expandProjectAtrributes),
        resultWithName = Record.AddField(result, "Name", source)

    in
        resultWithName;

//FUNCTION REQUESTING TimeOffTypes
requestTimeOffTypes = (token) => 
    let
        source = "Time Off Types",

        data = Web.Contents("https://api.personio.de/",
            [
                RelativePath = "v1/company/time-off-types",
                Query = [limit = Number.ToText(200), offset = Number.ToText(0)],
                Headers = [#"authorization"="Bearer "&token, #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"]
            ]),

        response = Json.Document(data),
        table = if Table.IsEmpty(Table.FromRecords(response[data])) then EmptyTable else Table.FromRecords(response[data]), 
        expandAttributes = Table.ExpandRecordColumn(table, "attributes", {"id", "name", "unit", "category", "half_day_request_enabled", "certification_required",
        "certification_submission_timeframe", "substitute_option", "approval_required"}, {"ID", "Name", "Unit", "Category", "Half Day Request Enabled", "Certficitaion Required", 
        "Certification Submission Timeframe", "Substitute Option", "Approval Required"}),

        //t1 = Table.RemoveColumns(expandAttributes, {"type"}),
        record = Record.AddField([], "Data", expandAttributes),

        resultWithName = Record.AddField(record, "Name", source)
    in resultWithName;

// REQUESTING A SINGLE PAGE OF TIMEOFFS, LIMIT SET TO 200 (MAX)
requestTimeOffs = (token, offset, sDate as text, eDate as text) => 
    let

        request = Web.Contents("https://api.personio.de/",
            [
                RelativePath = "v1/company/time-offs",
                Query = [start_date = sDate, end_date = eDate, offset=Number.ToText(offset), limit=Number.ToText(200)],
                Headers = [#"authorization"="Bearer "&token, #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"]
            ]),
        headers = Value.Metadata(request),

        data = Json.Document(request),
        table = Table.FromRecords(data[data]),

        totalPages = data[metadata][total_pages],
        record = Record.AddField([], "Data", table),
        result = Record.AddField(record, "numOfPages", totalPages)

    in result;

// PAGED TIMEOFFS
pagedTimeOffs = (token, sDate as text, eDate as text) => 
    let
        source = "Time Offs",
        // MULTIPLE CALLS FOR TIMEOFFS, EACH ONE HAS INCREASED OFFSET BY 1 (DIFFERENT TYPE OF PAGING THAN IN ATTENDANCES)
        list = List.Generate( () => [x = requestTimeOffs(token, 1, sDate, eDate), y = 1],
            each [y] < [x][numOfPages] + 1, 
            each [x = requestTimeOffs(token, y, sDate, eDate), y = [y] + 1],
            each [x]),
        table = if List.IsEmpty(list) then EmptyTable else Table.FromList(list, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        rawData = Table.ExpandRecordColumn(table, "Column1", {"Data"}),

        attributes = Table.ExpandTableColumn(rawData, "Data", {"attributes"}),
        

        expandAttributes = Table.ExpandRecordColumn(attributes, "attributes", {"employee", "id", "status", "comment", "start_date", "end_date", "days_count", "half_day_start", "half_day_end", "time_off_type"}, 
                                                                                {"Employee", "ID", "Status", "Comment", "Start Date", "End Date", "Days Count", "Half Day Start", "Half Day End", "Time Off Type"}),
        expandTOTAttributes = Table.ExpandRecordColumn(expandAttributes, "Time Off Type", {"attributes"}),
        expandedToT = Table.ExpandRecordColumn(expandTOTAttributes, "attributes", {"id", "name", "category"}, {"Time Off ID", "Name", "Category"}),
        expandEmployee = Table.ExpandRecordColumn(expandedToT, "Employee", {"attributes"}),
        expandAttr = Table.ExpandRecordColumn(expandEmployee, "attributes", {"first_name", "last_name", "email"}),
        expandFN = Table.ExpandRecordColumn(expandAttr, "first_name", {"value"}, {"First Name"}),

        expandLN = Table.ExpandRecordColumn(expandFN, "last_name", {"value"}, {"Last Name"}),

        allexpanded = Table.ExpandRecordColumn(expandLN, "email", {"value"}, {"Email"}),

        record = Record.AddField([], "Data", allexpanded),
        resultWithName = Record.AddField(record, "Name", source)

    in
        resultWithName;

// MAKING A SINGLE PAGE REQUEST FOR ABSENCE PERIOD, LIMIT SET TO 200 (MAX)
requestAbsencePeriods = (token, offset) => let
    request = Web.Contents("https://api.personio.de/",
                    [
                        RelativePath = "v1/company/absence-periods",
                        Query = [offset=Number.ToText(offset), limit=Number.ToText(200)],
                        Headers = [#"authorization"="Bearer "&token, #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"]
                    ]),
        headers = Value.Metadata(request),

        data = Json.Document(request),
        table = Table.FromRecords(data[data]),

        totalPages = data[metadata][total_pages],
        record = Record.AddField([], "Data", table),
        result = Record.AddField(record, "numOfPages", totalPages)

    in result;

// PAGED ABSENCE PERIODS
pagedAbsencePeriods = (token) =>
    let 
        source = "Absence Periods",
        // MAKING MULTIPLE CALLS TO ABSENCE PERIODS, EACH HAS INCREASED OFFSET BY 1
        list = List.Generate( () => [x = requestAbsencePeriods(token, 1), y = 1],
            each [y] < [x][numOfPages] + 1, 
            each [x = requestAbsencePeriods(token, y), y = [y] + 1],
            each [x]),
        // CONVERTING LIST WE CREATED TO A TABLE, SO THAT WE CAN MAKE ALL THE COLUMN EXPANSIONS
        table = if List.IsEmpty(list) then EmptyTable else Table.FromList(list, Splitter.SplitByNothing(), null, null, ExtraValues.Error),

        // EXPANDING OF ALL COLUMNS
        rawData = Table.ExpandRecordColumn(table, "Column1", {"Data"}),

        attributes = Table.ExpandTableColumn(rawData, "Data", {"attributes"}),
        
        
       
        expandAttributes = Table.ExpandRecordColumn(attributes, "attributes", {"employee", "id", "measurement_unit", "effective_duration"}, 
                                                                            {"Employee", "Absence ID", "Measurement Unit", "Effective Duration"}),
        
        expandEmployee = Table.ExpandRecordColumn(expandAttributes, "Employee", {"attributes"}),
        
        
        expandAttr = Table.ExpandRecordColumn(expandEmployee, "attributes", {"id", "first_name", "last_name", "email"}),
        expandId = Table.ExpandRecordColumn(expandAttr, "id", {"value"}, {"Employee ID"}),
        
        expandFN = Table.ExpandRecordColumn(expandId, "first_name", {"value"}, {"First Name"}),
        
        expandLN = Table.ExpandRecordColumn(expandFN, "last_name", {"value"}, {"Last Name"}),
        expandEmail = Table.ExpandRecordColumn(expandLN, "email", {"value"}, {"Email"}),

        result = Record.AddField([], "Data", expandEmail),
        resultWithName = Record.AddField(result, "Name", source)

    in resultWithName;

// FUNCTION REQUESTING DOCUMENTS
requestDocuments = (token) => 
    let
        source = "Document Categories",

        request = Web.Contents("https://api.personio.de/",
            [
                RelativePath = "v1/company/document-categories",
                Headers = [#"authorization"="Bearer "&token, #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"]
            ]),
        data = Json.Document(request),
        table = if Table.IsEmpty(Table.FromRecords(data[data])) then EmptyTable else Table.FromRecords(data[data]), 
        attributes = Table.ExpandRecordColumn(table, "attributes", {"name"}, {"Name"}),

        result = Record.AddField([], "Data", attributes),
        resultWithName = Record.AddField(result, "Name", source)
    in
        resultWithName;

// FUNCTION REQUESTING PROJECTS
requestProjects = (token) => 
    let
        source = "Projects",
        request = Web.Contents("https://api.personio.de/",
            [
                RelativePath = "v1/company/attendances/projects",
                Headers = [#"authorization"="Bearer "&token, #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"]
            ]),
        
        data = Json.Document(request),
        table = if Table.IsEmpty(Table.FromRecords(data[data])) then EmptyTable else ProjectsExpand(data, source),

        result = Record.AddField([], "Data", table),
        resultWithName = Record.AddField(result, "Name", source)
    in
        resultWithName;

ProjectsExpand = (data, source) =>
    let
        table = Table.FromRecords(data[data]),
        attributes = Table.ExpandRecordColumn(table, "attributes", {"name", "active", "created_at", "updated_at"}, {"Project Name", "Is Active", "Created At", "Updated At"}),

        final = Table.RenameColumns(attributes, {"id", "Project ID"}),
        result = Record.AddField([], "Data", final),
        resultWithName = Record.AddField(result, "Name", source)
    in
        resultWithName;


// FUNCTION REQUESTING CUSTOM REPORTS
requestCustomReports = (token) =>
    let
        source = "Custom Reports",
        request = Web.Contents("https://api.personio.de/",
            [
                RelativePath = "v1/company/custom-reports/reports",
                Headers = [#"authorization"="Bearer "&token, #"Content-Type"="application/json", #"X-Personio-Partner-ID"= "UMWERK", #"X-Personio-App-ID"= "POWERBI"],
                ManualStatusHandling = {403}
            ]),

        ResponseCode = Value.Metadata(request),

        response = if ResponseCode[Response.Status] <> 200 then EmptyTable else CustomReportsLogic(request, source),
        result = Record.AddField([], "Data", response),
        resultWithName = Record.AddField(result, "Name", source)
    in
        resultWithName;

CustomReportsLogic = (request, source) => 
    let
        data = Json.Document(request),
        table = if Table.IsEmpty(Table.FromRecords(data[data])) then EmptyTable else CustomReportsExpand(data, source)
    in
        table;

CustomReportsExpand = (data, source) =>
    let
        table = Table.FromRecords(data[data]),
        attributes = Table.ExpandRecordColumn(table, "attributes", {"name", "description", "author_first_name", "author_last_name", "type", "status", "start_date", "end_date", "created_at", "updated_at","data_refreshed_at"}, 
                                                                    {"Name", "Description", "Author's first name", "Author's last name", "Type", "Status", "Start date", "End date", "Created at", "Updated at", "Data refreshed at"}),
        result = Record.AddField([], "Data", attributes),
        resultWithName = Record.AddField(result, "Name", source)
    in
        resultWithName;

// Data Source Kind description
Personio = [
    // using UsernamePassword authentication, extracting using username as ID and password as Secret
    Authentication = [
        UsernamePassword = [
            UsernameLabel = "Client ID",
            PasswordLabel = "Client Secret",
            Label = "Client Credentials"
      ]
    ]//,
    //Label = "Hello World With Docs"
];

// Data Source UI publishing description
    Personio.Publish = [
        Beta = false,
        Category = "Other",
        ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
        LearnMoreUrl = "https://powerbi.microsoft.com/",
        SourceImage = Personio.Icons,
        SourceTypeImage = Personio.Icons
    ];

    Personio.Icons = [
        Icon16 = { Extension.Contents("Personio16.png"), Extension.Contents("Personio20.png"), Extension.Contents("Personio24.png"), Extension.Contents("Personio32.png") },
        Icon32 = { Extension.Contents("Personio32.png"), Extension.Contents("Personio40.png"), Extension.Contents("Personio48.png"), Extension.Contents("Personio64.png") }
    ];