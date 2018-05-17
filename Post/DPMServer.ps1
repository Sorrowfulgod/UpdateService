$stepStatus = 1
$output = ""

function EnableAgent($server)
{
    [void](Enable-DPMProductionServer -ProductionServer $server)
    [void](Update-DPMProductionServer -ProductionServer $server)
}

try
{
    $installPath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft Data Protection Manager\Setup" "UIInstallPath").UIInstallPath
    $dpmModuleFullPath = $installPath + "Modules\DataProtectionManager\DataProtectionManager.psd1"
    Import-Module $dpmModuleFullPath

    $str = "Enable agents..."
   	$output += "$str`r`n"
    Write-Host $str

    $ProductionServers = Get-DPMProductionServer | ?{$_.Connectivity -match "Disabled"}
    foreach ($server in $ProductionServers)
    {
        $str = "Enabling agent on $($server.Name)"
   	    $output += "$str`r`n"
        Write-Host $str
        EnableAgent($server)
    } 
    
    $str = "Check datasources..."
   	$output += "$str`r`n"
    Write-Host $str
    $alerts = Get-DPMAlert | ?{$_.Severity -eq "Error" -and $_.TargetObjectType -eq "Datasource"}
    if ($alerts -ne $null)
    {
        foreach($alert in $alerts)
        {
            if ( $($alert.ErrorInfo.ShortProblem) -eq "Recovery point creation failed" -and $alert.Datasource -ne $null)
            {
                $str = "Create recovery point for `"$($alert.Datasource)`" failed! Perfrom creating..."
   	        $output += "$str`r`n"
                Write-Host $str
                #Start-DatasourceConsistencyCheck -Datasource $($alert.Datasource)
                [void](New-RecoveryPoint -Datasource $($alert.Datasource) -Disk -BackupType ExpressFull)
            }
            elseif ($($alert.ErrorInfo.ShortProblem) -eq "Replica is inconsistent" -and $alert.Datasource -ne $null)
            {
                $str = "Replica `"$($alert.Datasource)`" is inconsistent! Perfrom check..."
   	            $output += "$str`r`n"
                Write-Host $str
                [void](Start-DatasourceConsistencyCheck -Datasource $($alert.Datasource))
            }
        }
    }
    Write-Host "Done"
}
catch
{
    $stepStatus = 0;
    $output += $_;
}

@{
    Status = $stepStatus;
    Details = $output;
}