function DisableAgent($server)
{
    Write-Host "Disabling agent for $($server.Name)..."
    [void](Disable-DPMProductionServer -ProductionServer $server -Confirm:$false)
    [void](Update-DPMProductionServer -ProductionServer $server)
}

$status = 1
$output = ""
try
{
    $installPath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft Data Protection Manager\Setup" "UIInstallPath").UIInstallPath
    $dpmModuleFullPath = $installPath + "Modules\DataProtectionManager\DataProtectionManager.psd1"
    Import-Module $dpmModuleFullPath

    $str = "Disabling agents..."
    $output += "$str`r`n"
    Write-Host $str

    $ProductionServers = Get-DPMProductionServer | ?{($_.Connectivity -notmatch "Disabled")}
    $ProtectedServers = $ProductionServers | ?{$_.ServerProtectionState -eq 'HasDatasourcesProtected'}
    $ProtectedServersStandAlone = $ProtectedServers | ?{$_.ClusterName -eq ''}
            
    foreach ($server in $ProtectedServersStandAlone)
    {
        $str = "Disabling agent on standalone server $($server.Name)"
   	    $output += "$str`r`n"
        Write-Host $str
        DisableAgent($server)
    } 
    $ProtectedClusters = Get-DPMProductionCluster
    foreach($cluster in $ProtectedClusters)
    {
        $ProtectedServersClustered = $ProtectedServers | where {$_.ClusterName -eq $cluster.ClusterName} 
        $ClusteredResources = $ProtectedServersClustered | where {$_.PossibleOwners}
        $ClusterNodesDNSNames = @()
        $ClusteredResources | %{$ClusterNodesDNSNames += $_.PossibleOwners}
        $ClusterNodesDNSNames = $ClusterNodesDNSNames | Select-Object -Unique
        $ClusterNodesNames = @()
        $ClusterNodesDNSNames | %{$_ -match '(.+?)\..+' | Out-Null; $ClusterNodesNames += $Matches[1]}
        $ClusterNodes = @()
        foreach ($NodeName in $ClusterNodesNames) 
        {
            $ClusterNodes += $ProductionServers | ?{$_.ServerName -eq $NodeName -and $_.ClusterName -match $($cluster.ClusterName)}
        }

        foreach($clusterNode in $ClusterNodes)
        {
            $str = "Disabling agent on cluster node $($clusterNode.Name)"
   	        $output += "$str`r`n"
            Write-Host $str
            DisableAgent($clusterNode)
        }
    }           

    $str = "Checking if running job exists..."
   	$output += "$str`r`n"
    Write-Host $str
    $jobs = Get-DPMJob -Status InProgress
    if ($jobs -and $jobs.Count -ne 0)
    {
        $str = "Waiting all jobs to complete..."
   	    $output += "$str`r`n"
        Write-Host $str
        Write-Host "Waiting all jobs to complete..."
        do
        {
            $jobs = Get-DPMJob -Status InProgress
            Start-Sleep -Seconds 120
            Write-Host "." -NoNewline
        }
        while($jobs -ne $null) 
    }

    $str = " Done!"
    $output += "$str`r`n"
    Write-Host $str
}
catch
{
    $status = 0;
    $output += $_;
} 

New-Object PSCustomObject -Property @{
    Status = $status;
    Details = $output;
}