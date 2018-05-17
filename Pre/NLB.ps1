# NLB Pre script
$status = 1
$output = ""

try 
{
    Import-Module NetworkLoadBalancingClusters
    $computerName = $($env:ComputerName)

	$nlbNodes = Get-NlbCluster -ErrorAction SilentlyContinue
    if ($nlbNodes -eq $null) 
    {
        $str = "NLB feature is installed, but no NLB Cluster present"
	    $output += "$str`r`n"
        Write-Host $str
    }
    else {
        $str = "Stopping NLB node(s) for $computerName..."
	    $output += "$str`r`n"
        Write-Host $str

        $nlbNodes = gwmi -Class MicrosoftNLB_Node -Namespace "root\MicrosoftNLB" -Filter "ComputerName like '%$computerName%'"
	    foreach ($node in $nlbNodes)
	    {
            $InterfaceName = (Get-NetIPAddress -IPAddress $($node.DedicatedIPAddress)).InterfaceAlias

		    $nodeInfo = Get-NlbClusterDriverInfo -InterfaceName $InterfaceName
		    if ($nodeInfo.CurrentHostState.ToString() -eq "Started")
		    {
                $str = "Stopping NLB node..."
			    $output += "$str`r`n"
                Write-Host $str

			    [void](Stop-NlbClusterNode -HostName $computerName) #  -Drain

                $str = "Setting properties for $computerName (initial state 'Stopped' and retain suspended)..."
			    $output += "$str`r`n"
                Write-Host $str

			    [void](Set-NlbClusterNode -InterfaceName $InterfaceName -InitialHostState Stopped -RetainSuspended $true -Force)
		    }
		    else
		    {
                $str = "NLB node not in started state!"
			    $output += $str
                Write-Host $str
		    }
	    }
    }
}
catch
{
    Write-Host $_
    $status = 0
	$output += $_
}

New-Object PSCustomObject -Property @{
    Status = $status;
    Details = $output;
}
