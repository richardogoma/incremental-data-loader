#Requires -Modules @{ ModuleName="SqlServer"; RequiredVersion="21.1.18256" }
#Requires -PSEdition Core
<#
    This script stages and integrates data from a flat file into a SQL Server table based 
    on specified parameters, and logs the results in program and SQL DML log files.
#>

try {
    # Set the configuration parameters for the data integrator program
    $config = Get-Content "config/config.json" -Raw -ErrorAction Stop | ConvertFrom-Json
    $rawfilepath = "data/raw/{0}" -f $($config._dataset)
    $convertedfilepath = "data/processed/{0}" -f $($config._dataset)
    $InstanceName = $config.db_credentials.Instance
    $Database = $config.db_credentials.Database
    $Schema = $config.db_credentials.Schema
    $TableName = $config.db_credentials.Table

    # SQL server credential object
    $User = $config.db_credentials.User
    $PWord = ConvertTo-SecureString -String $($config.db_credentials.Password) -AsPlainText -Force
    $SqlCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

    # Invoke the data staging function to load data to staging table
    . .\src\utils\fxStageData.ps1
    $staging_response = StageData -InstanceName $InstanceName -Database $Database -Schema $Schema -rawfilepath $rawfilepath `
        -convertedfilepath $convertedfilepath -TableName $TableName -SqlCred $SqlCred # -Verbose
    
    # Invoke the data integration function to integrate new and changed data to the production table
    . .\src\utils\fxIntegrateStagedData.ps1
    $integration_response = IntegrateData -InstanceName $InstanceName -Database $Database -Schema $Schema `
        -TableName $TableName -SqlCred $SqlCred -DataColumns $staging_response['processed_data_headers']
    
    # Write to data integration output to the DML log file (updates & inserts)
    . .\src\utils\fxWriteLog.ps1
    WriteFunction -data $integration_response['log'] -header $integration_response['log_header'] -file ".\log\dml.log"

    # Write to Program log
    $programLogMessage = "Info: Program ran successfully"
    $programLogEntry = [PSCustomObject]@{
        "Timestamp" = Get-Date
        "Instance" = $InstanceName
        "Table" = "[$Database].[$Schema].[$TableName]"
        "LogMessage" = $programLogMessage
        "ScriptName" = $MyInvocation.MyCommand.Name
        "Line" = $MyInvocation.ScriptName
        "ScriptLineNumber" = $MyInvocation.ScriptLineNumber
        "Trace" = $MyInvocation.ScriptStackTrace
    }
    WriteFunction -data $programLogEntry -header @("Timestamp", "Instance", "Table", "LogMessage", "ScriptName", "Line", "ScriptLineNumber", "Trace") -file ".\log\program.log"
}
catch {
    $errorMessage = $($_.ToString().Trim())
    Write-Error "Error: $errorMessage"

    # Write to Program log
    . .\src\utils\fxWriteLog.ps1
    $errorLogEntry = [PSCustomObject]@{
        "Timestamp" = Get-Date
        "Instance" = $InstanceName
        "Table" = "[$Database].[$Schema].[$TableName]"
        "LogMessage" = "Error: $errorMessage"
        "ScriptName" = "$($_.InvocationInfo.ScriptName)"
        "Line" = "$($_.InvocationInfo.Line.Trim())"
        "ScriptLineNumber" = "$($_.InvocationInfo.ScriptLineNumber)"
        "Trace" = "$($_.ScriptStackTrace.Trim())"
    }
    WriteFunction -data $errorLogEntry -header @("Timestamp", "Instance", "Table", "LogMessage", "ScriptName", "Line", "ScriptLineNumber", "Trace") -file ".\log\program.log"
}
