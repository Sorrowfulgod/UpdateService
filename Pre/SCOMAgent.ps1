# SCOMAgent Pre script
param($SCOMDBConnectionString)

$status = 1
$output = ""

try 
{
	$computerFQDN = "{0}.{1}" -f $($env:COMPUTERNAME), $((Get-WmiObject -Class Win32_ComputerSystem).Domain)

    $str = "Enabling maintance mode for '$computerFQDN'..."
    $output += $str
    Write-Output $str

	$strSQLquery = 'DECLARE @BaseManagedTypeID VARCHAR(50)
DECLARE @BaseManagedEntityId VARCHAR(50)
SELECT @BaseManagedTypeID = [BaseManagedTypeID] FROM [dbo].[ManagedType] WHERE [TypeName] = ''Microsoft.Windows.Server.Computer''
SELECT @BaseManagedEntityId = [BaseManagedEntityId] FROM [dbo].[BaseManagedEntity] WHERE [Name] = ''{0}'' AND [BaseManagedTypeID] = @BaseManagedTypeID

DECLARE @dt_start DateTime, @dt_end DateTime
SET @dt_start = GETUTCDATE()
SELECT @dt_end = DATEADD(Hour, 8, @dt_start)

EXEC p_MaintenanceModeStart
@BaseManagedEntityID = @BaseManagedEntityId,
@ScheduledEndTime = @dt_end ,
@ReasonCode = 6,
@Comments = N''Update server'',
@User = N''UpdateService'',
@Recursive = 1,
@StartTime = @dt_start' -f $computerFQDN

	$Connection = New-Object System.Data.SQLClient.SQLConnection
	$Connection.ConnectionString = $SCOMDBConnectionString
	$Connection.Open()

	$QueryCommand = New-Object System.Data.SQLClient.SQLCommand
	$QueryCommand.Connection = $Connection
	$QueryCommand.CommandText = $strSQLquery
	$res = $QueryCommand.ExecuteNonQuery()
	
	$QueryCommand.Dispose()
	$Connection.Dispose()

	Write-Host "Sleeping 5 minutes (wait for monitors unload)..."
	Start-Sleep -Seconds 300
}
catch 
{
    $status = 0
    $output += $_
}			

New-Object PSCustomObject -Property @{
    Status = $status
    Details = $output
}
