# NLB Post script
$status = 1
$output = ""

try 
{
    Import-Module NetworkLoadBalancingClusters
    $computerName = $($env:ComputerName)

	$nlbNodes = Get-NlbCluster -ErrorAction SilentlyContinue
    if ($nlbNodes -eq $null) 
    {
	    $output += "NLB feature is installed, but no NLB Cluster present`r`n"
    }
    else 
    {
	    $output += "Starting NLB node(s) for $computerName...`r`n"

        $nlbNodes = gwmi -Class MicrosoftNLB_Node -Namespace "root\MicrosoftNLB" -Filter "ComputerName like '%$computerName%'"
	    foreach ($node in $nlbNodes)
	    {
            $InterfaceName = (Get-NetIPAddress -IPAddress $($node.DedicatedIPAddress)).InterfaceAlias

		    $nodeInfo = Get-NlbClusterDriverInfo -InterfaceName $InterfaceName
		    if ($nodeInfo.CurrentHostState.ToString() -eq "Stopped")
		    {
		    	$output += "Setting properties for $computerName (initial state 'Started' and not retain suspended)...`r`n"

	    		[void](Set-NlbClusterNode -InterfaceName $InterfaceName -InitialHostState Started -RetainSuspended $false -Force)

			    $output += "Starting NLB node..."

    			[void](Start-NlbClusterNode -HostName $computerName)
		    }
		    else
		    {
			    $output += "NLB node not in stopped state!"
		    }
	    }
    }
}
catch
{
    $status = 0
	$output += $_
}

New-Object PSCustomObject -Property @{
    Status = $status;
    Details = $output;
}
