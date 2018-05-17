# SCOMAgent Post script
param($SCOMDBConnectionString)

$status = 1
$output = ""

try 
{
	$computerFQDN = "{0}.{1}" -f $($env:COMPUTERNAME), $((Get-WmiObject -Class Win32_ComputerSystem).Domain)
    
    $output += "Disabling maintance mode for '$computerFQDN'..."

	$strSQLquery = 'DECLARE @BaseManagedTypeID VARCHAR(50)
DECLARE @BaseManagedEntityId VARCHAR(50)
SELECT @BaseManagedTypeID = [BaseManagedTypeID] FROM [dbo].[ManagedType] WHERE [TypeName] = ''Microsoft.Windows.Server.Computer''
SELECT @BaseManagedEntityId = [BaseManagedEntityId] FROM [dbo].[BaseManagedEntity] WHERE [Name] = ''{0}'' AND [BaseManagedTypeID] = @BaseManagedTypeID
DECLARE @dt_end DateTime
SET @dt_end = GETUTCDATE()
EXEC p_MaintenanceModeStop
@BaseManagedEntityID = @BaseManagedEntityId,
@User = N''UpdateService'',
@Recursive = 1,
@EndTime = @dt_end' -f $computerFQDN

	$Connection = New-Object System.Data.SQLClient.SQLConnection
	$Connection.ConnectionString = $SCOMDBConnectionString
	$Connection.Open()

	$now = Get-Date
	$QueryCommand = New-Object System.Data.SQLClient.SQLCommand
	$QueryCommand.Connection = $Connection
	$QueryCommand.CommandText = $strSQLquery
	$res = $QueryCommand.ExecuteNonQuery()
	
	$QueryCommand.Dispose()
	$Connection.Dispose()
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