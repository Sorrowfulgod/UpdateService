param([String]$VMMServer)

$status = 1
$output = ""


try
{
    # TEMP for scvmm - later to step!
    #if ($installedFeatures.Contains("VMMAgent"))
    #{
    #    Log -Message $("Check for VMM agent update for '{0}'" -f $serverName) -Color "White"

    #    $runasAccount = Get-SCRunAsAccount "Fabric Admin"
    #    $managedComp = Get-SCVMMManagedComputer | ? name -match $serverName
    ##    Update-SCVMMManagedComputer -VMMManagedComputer $managedComp -Credential $runasAccount
    #}

}
catch
{
	Write-Host "Exception: $_"
    $result = New-Object PSCustomObject -Property @{
				    Status = 0;
				    Details = "$output. Exception $_";
				    Data = $false
			    }
}

New-Object PSCustomObject -Property @{
    Status = $result.Status;
    Details = $result.Details;
    Data = $result.Data
}