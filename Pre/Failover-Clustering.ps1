# Failover clustering Pre script
param([bool]$UseQuickMigrationIfLiveFails, [string]$AntiAffintyAction)

$status = 1
$output = ""

try 
{
	$activesNodesCount = (Get-ClusterNode | ? State -eq 'Up').Count
	$computerName = $($env:ComputerName)

	if ($activesNodesCount -gt 1)
	{
		$str = "Draining node `"$computerName`"" 
		$output += "$str`r`n" 
		Write-Host $str

		if ($UseQuickMigrationIfLiveFails)
		{
			$str = "Quick migration will be used if live fails" 
			$output += "$str`r`n" 
		}
		else
		{
			$str = "Quick migration will not be used if live fails" 
			$output += "$str`r`n" 
		}
		Write-Host $str

		$antiaffinityEnforced = $( (Get-Cluster).ClusterEnforcedAntiAffinity -eq 1 )

		$listOfNodeGroups = $clusterNode | Get-ClusterGroup # | ? State -eq 'Online'
		foreach($group in $listOfNodeGroups)
		{
			if ($group.GroupType -eq 'VirtualMachine')
			{
				if ($group.State -eq 'Online')
				{
					if ($group.AntiAffinityClassNames.Count -gt 0 -and $antiaffinityEnforced)
					{
						$str = "Antiaffinity classes defined to `"$($group.Name)`" and cluster is enforce antiaffinity. Try to evacuate vm..." 
						$output += "$str`r`n" 
						Write-Host $str

						$result = $group | Move-ClusterVirtualMachineRole -MigrationType Live -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
						if ($result -eq $null)
						{
                            $str = "Unable to live migrate VM. Perform migration using `"$AntiAffintyAction`" action..." 
							$output += "$str`r`n" 
							Write-Host $str
                            
                            $vm = $group | Get-VM
                            switch ($AntiAffintyAction)
                            {
                                "Off" 
                                    { 
                                        Stop-VM -VM $vm -Force
                                    }
                                "Save" 
                                    { 
							            Save-VM -VM $vm -ErrorAction Stop                                        
                                    }
                                "TurnOff" 
                                    {
                                        Stop-VM -VM $vm -TurnOff -Force
                                    }
                                Default { throw "Unknown action `"$AntiAffintyAction`"" } 
                            }

							$str = "Move virtual machine group `"$($group.Name)`" using quick migration..."
							$output += "$str`r`n" 
							Write-Host $str

							$result = $group | Move-ClusterGroup -ErrorAction Continue -WarningAction SilentlyContinue
						}
					}
					else
					{
                        $result = $null
						$str = "Try moving virtual machine group `"$($group.Name)`" to another node using live migration..." 
						$output += "$str`r`n" 
						Write-Host $str

						$result = $group | Move-ClusterVirtualMachineRole -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

						if ($result -eq $null)
						{
							$str = "Unable to move virtual machine group `"$($group.Name)`" using live migration" 
						    Write-Host $str
							if ($UseQuickMigrationIfLiveFails)
							{
								$str = "Try quick migration..." 
								$output += "$str`r`n" 
								Write-Host $str

								$result = $group | Move-ClusterGroup -ErrorAction Continue -WarningAction SilentlyContinue
								if ($result -eq $null)
								{
									$str = "Unable to move virtual machine group `"$($group.Name)`" using quick migration" 
									$output += "$str`r`n" 

									throw $str
								}
								$result = Start-ClusterGroup $group -ErrorAction Continue -WarningAction SilentlyContinue
							}
							else
							{
								throw $str
							}
						}

						if ($result.State -ne 'Online')
						{
							$str = "Virtual machine group `"$($group.Name)`" become offline after migration! Start back..." 
							$output += "$str`r`n" 
							Write-Host $str

							Start-ClusterGroup $result -ErrorAction Stop
						}
					}
				}
				else
				{
					$result = $true
				}
			}
			else
			{
				$str = "Moving group `"$($group.Name)`" to another node..." 
				$output += "$str`r`n" 
				Write-Host $str

				$result = $group | Move-ClusterGroup -ErrorAction Continue -WarningAction SilentlyContinue
			}

			if ($result -eq $null)
			{
				$str = "Unable to move group `"$($group.Name)`" to another node! Stopping action!" 
				$output += "$str`r`n" 

				throw $str
			}
		} # end of group move

		$clusterSharedVolumes = $clusterNode | Get-ClusterSharedVolume
		foreach($volume in $clusterSharedVolumes)
		{
			$str = "Move cluster shared volume `"$($volume.Name)`" to another node..."
			$output += "$str`r`n" 
			Write-Host $str

			$result = $volume | Move-ClusterSharedVolume -ErrorAction Continue -WarningAction SilentlyContinue
			if ($result -eq $null)
			{
				$str = "Unable to move cluster shared volume `"$($volume.Name)`" to another node! Stoping action" 
				$output += "$str`r`n" 

				throw $str
			}
		}
	}
	else
	{
		$str = "Active nodes count ($activesNodesCount) is too small to perfom cluster maintenance operation" 
		$output += "$str`r`n" 
		Write-Host $str
	}

	$clusterNode = Get-ClusterNode $computerName
	$clusterNode.NodeWeight = 0
	if ($clusterNode.State -ne "Paused") # may be already suspened by Exchange script or something else
	{
		$sqlClusterGroup = Get-ClusterGroup -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | ? GroupType -eq "Unknown"
		if ($sqlClusterGroup -eq $null) # unknown groups may be SQL or VMM or other services. dont suspend - update may fails!!
		{
			$str = "Suspending cluster node `"$computerName`"..." 
			$output += "$str`r`n" 
			Write-Host $str

			[void](Suspend-ClusterNode $computerName -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
		}
		else
		{
			$str = "Groups with type 'Unknown' present. Dont suspend node" 
			$output += "$str`r`n" 
			Write-Host $str
		}
	}
	else
	{
		$str = "Cluster node `"$computerName`" already in suspended state" 
		$output += "$str`r`n" 
		Write-Host $str
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
