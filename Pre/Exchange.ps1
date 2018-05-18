#Exchange pre script
param([bool]$UsePSSession)

function Restart-ServiceA
{
    param($serviceName)
    
    if ($UsePSSession)
    {
        Restart-Service $serviceName
    }
    else
    {
        [System.Diagnostics.Process]::Start("cmd.exe", "/c net stop $serviceName && net start $serviceName")
    }
}

$computerName = $env:computerName
$status = 1
$output = ""

try
{
    if ($UsePSSession)
    {
        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010 -ErrorAction:Stop
    }

    $exchangeServer = Get-ExchangeServer -Identity $computerName -ErrorAction SilentlyContinue
	if ($exchangeServer)
	{
		if($exchangeServer.IsHubTransportServer -eq $True) # mailbox server
		{
			$output += "Server '$computerName' is mailbox server`r`n"

			$dagName = $null
			$mbxServer = Get-MailboxServer $computerName
			if ($mbxServer.DatabaseAvailabilityGroup)
			{
				$output += "Setting database activation policy to Blocked...`r`n"

    			Set-MailboxServer -Identity $computerName -DatabaseCopyAutoActivationPolicy:Blocked

				$dagName = $mbxServer.DatabaseAvailabilityGroup.Name
				$dag = Get-DatabaseAvailabilityGroup $mbxServer.DatabaseAvailabilityGroup -Status

				$output += "Server '$computerName' is DAG '$dagName' member`r`n"

				if ($computerName -eq $dag.PrimaryActiveManager.Name)
				{
					$output += "Move DAG primary active manager to another server...`r`n"
       				if (![Microsoft.Exchange.Cluster.Replay.DagTaskHelperPublic]::MovePrimaryActiveManagerRole($computerName))
					{
						throw "Unable to move DAG primary active manager to another server..."
					}
				}

				$output += "Move all active databases off the server...`r`n"

				$sourceServer = $exchangeServer
				$activedb = @()
				$activedbList = Get-MailboxDatabase -Server $sourceServer.Name -Status
				foreach($acDB in $activedbList)
				{
					if ( ($acDB.MountedOnServer -eq $sourceServer.Fqdn) -and ($acDB.ReplicationType -eq 'Remote') )
					{
						$activedb += $acDB
					}
				}
				if ($activedb.Count -gt 0)
				{
					foreach ($sourcedb in $activedb)
					{
						$targetdbs = @()
						$moveSuccessful = $false

						foreach ($Server in $sourcedb.Servers)
						{
							if ($Server.Name -ne $sourceServer.Name)
							{
								$dbCopyStatus = Get-MailboxDatabaseCopyStatus $sourcedb\$Server
								if ($dbCopyStatus.Status -eq 'Healthy')
								{
									$targetdbs += $dbCopyStatus
								}
							}
						}
						if ($targetdbs)
						{
							foreach ($targetdb in $targetdbs)
							{
								$output += "Move active copy of $sourcedb to $($targetdb.MailboxServer)...`r`n"

								[void](Move-ActiveMailboxDatabase -Identity $sourcedb -ActivateOnServer $targetdb.MailboxServer -SkipClientExperienceChecks -Confirm:$false -ErrorAction Stop)
							}
						}
						else
						{
							throw "No available servers to move database $sourcedb"
						}
					}
				}
				else
				{
					$output += "No active DAG databases on server`r`n"
				}
	
				$output += "Get all databases with multiple copies...`r`n"

				$databases = @()
				$databasesList = Get-MailboxDatabase -Server $computerName
				foreach($rdb in $databasesList)
				{
					if ($rdb.ReplicationType -eq 'Remote')
					{
						$databases += $rdb
					}
				}
				if ( $databases.Count -gt 0 )
				{
					$output += "Suspending databases copies...`r`n"

					foreach($base in $databases)
					{ 
						Suspend-MailboxDatabaseCopy "$($base.Name)\$computerName" -ActivationOnly -Confirm:$false -SuspendComment "Suspended ActivationOnly by UpdateServers script at $([DateTime]::Now)"
					}
				}
				else
				{
					$output += "No databases with multiple copies...`r`n"
				}
			}
			else
			{
				$output += "Server '$computerName' is not DAG member`r`n"
			}
    
			$output += "Suspending Transport Service. Draining remaining messages...`r`n"

			Set-ServerComponentState $computerName -Component HubTransport -State Draining -Requester Maintenance 
			$otherServer = $null
			$otherServerList = Get-ExchangeServer
			for ($i = 0; $i -lt $otherServerList.Count -and $otherServer -eq $null; $i++)
			{
				$os = $otherServerList[$i]
				if ($os.Identity -ne $computerName -and $os.IsHubTransportServer)
				{
					$otherServer = $os
				}
			}

			if ($otherServer -ne $null)
			{
				Redirect-Message -Server $computerName -Target $($otherServer.Fqdn) -Confirm:$false 
			}

			$output += "Wait for transport queues are empty`r`n"
			do
			{
				$messageCount = 0
				$queueList = Get-Queue -Server $computerName
				foreach($queue in $queueList)
				{
					if ($queue.Identity -notlike "*\Poison" -and $queue.Identity -notlike"*\Shadow\*")
					{
						$messageCount += $($queue.MessageCount)
					}
				}

				if ($messageCount -ne 0)
				{
					[System.Threading.Thread]::Sleep(3000)
				}
			} while($messageCount -ne 0)
		}

		$output += "Putting all components to offline...`r`n"

		Set-ServerComponentState $computerName -Component ServerWideOffline -State Inactive -Requester Maintenance

		if($exchangeServer.IsHubTransportServer)
		{
			$output += "Restarting MSExchangeTransport service...`r`n"

			[void](Restart-ServiceA MSExchangeTransport)
		}

		if($exchangeServer.IsFrontendTransportServer)
		{
			$output += "Restarting the MSExchangeFrontEndTransport Service...`r`n"

			[void](Restart-ServiceA MSExchangeFrontEndTransport)
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
