# Failover clustering Post script
param([bool]$UseQuickMigrationIfLiveFails, [string]$AntiAffintyAction)

$status = 1
$output = ""

try 
{
	$computerName = $($env:ComputerName)

	$antiaffinityEnforced = $( (Get-Cluster).ClusterEnforcedAntiAffinity -eq 1 )

	$clusterNode = Get-ClusterNode $computerName
	$clusterNode.NodeWeight = 1
	if ($clusterNode.State -eq "Paused")
	{
		$output += "Resuming cluster node `"$computerName``r`n"

		[void](Resume-ClusterNode $computerName -Failback NoFailback)
	}
	else
	{
		$output += "Cluster node `"$computerName`" not in `"Paused`" state`r`n" 
	}

	$listOfVMGroups = Get-ClusterGroup | ?{$_.GroupType -eq 'VirtualMachine' -and $_.State -eq 'Offline'}
	foreach($group in $listOfVMGroups)
	{
		$str = "Processing VM group `"$($group.Name)`"" 
		$output += "$str`r`n" 
		Write-Host $str

		if ($group.AntiAffinityClassNames.Count -gt 0 -and $antiaffinityEnforced)
		{
				$str = "Antiaffinity classes defined to `"$($group.Name)`" and cluster is enforce antiaffinity. VM is in saved state or powered off.." 
				$output += "$str`r`n" 
				Write-Host $str
				if ($group.OwnerNode -ne $computerName)
				{
					$str = "Move group back..." 
					$output += "$str`r`n" 
					Write-Host $str
					$result = $group | Move-ClusterGroup -Node $computerName -ErrorAction Continue -WarningAction SilentlyContinue
				}

				$str = "Starting `"$($group.Name)`"..." 
				$output += "$str`r`n" 
				Write-Host $str

				$result = Start-ClusterGroup $group -ErrorAction Continue -WarningAction SilentlyContinue
				if ($result -eq $null)
				{
					$str = "Unable to move back and start `"$($group.Name)`". Stoping action" 
					$output += "$str`r`n" 
					Write-Host $str
        
					throw ""
				}

				$vm = $group | Get-VM
			    $str = "Waitng vm `"$($vm.Name)`" to become available..." 
		    	$output += "$str`r`n" 
	    		Write-Host $str
    			$i = 0
				do 
			    {
		    		Start-Sleep -Seconds 10
	    			$i++
    			}
				until ((Get-VMIntegrationService $vm | ?{$_.name -eq "Heartbeat"}).PrimaryStatusDescription -eq "OK")

				$str = "VM `"$($vm.Name)`" become available in $($i*10) seconds" 
				$output += "$str`r`n" 
				Write-Host $str
		}
	}
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
