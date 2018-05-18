#Exchange post script
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
		$output += "Reactivating all server components...`r`n"

		Set-ServerComponentState $computerName -Component ServerWideOffline -State Active -Requester Maintenance 

		if ($exchangeServer.IsHubTransportServer)
		{
			$dagName = $null
			$mbxServer = Get-MailboxServer $computerName -ErrorAction:SilentlyContinue
			if ($mbxServer -and $mbxServer.DatabaseAvailabilityGroup)
			{
				$dagName = $mbxServer.DatabaseAvailabilityGroup.Name
			}
			else
			{
				throw "Server $computerName is not DAG member!"
			}

			$output += "Resuming databases copies...`r`n"

			$databases = @()
			$databasesList = Get-MailboxDatabase -Server $computerName
			foreach($db in $databasesList)
			{
				if ($db.ReplicationType -eq 'Remote')
				{
					$databases += $db
				}
			}
			if ($databases.Count -gt 0)
			{
				$isLaggedCopy = $false
				foreach ($database in $databases)
				{
					if ($database.ReplayLagTimes -ne $null)
					{
						foreach($lagTime in $database.ReplayLagTimes)
						{
							if ($lagTime.Key -eq $computerName -and $lagTime.Value.CompareTo([System.TimeSpan]::Zero) -ne 0)
							{
								$output += "Database $($database.Name) on $computerName is lagged copy. Resuming in ReplicationOnly mode`r`n"

								$isLaggedCopy = $true
								break
							}
						}
					}
			
					if ($isLaggedCopy)
					{
						Resume-MailboxDatabaseCopy "$($database.Name)\$computerName" -ReplicationOnly -Confirm:$false
					}
					else
					{
						Resume-MailboxDatabaseCopy "$($database.Name)\$computerName" -Confirm:$false
					}
				}
			}

			$output += "Setting database activation policy to Unrestricted...`r`n"

			Set-MailboxServer -Identity $computerName -DatabaseCopyAutoActivationPolicy:Unrestricted
	
			$output += "Waiting for databases init...`r`n"

			$i = 0
			do
			{
				$nonInitDb = @()
				$failedStats = @("Initializing", "Failed", "ServiceDown")
				$dbList = Get-MailboxDatabaseCopyStatus
				foreach($db in $dbList)
				{
					if ($failedStats -contains $db.Status)
					{
						$nonInitDb += $db
					}
				}
				[System.Threading.Thread]::Sleep(5000)
				$i++
		
				if ($i -eq 120)
				{
					throw "Database not become healthy after 600 sec."
				}
			} while ($nonInitDb.Count -gt 0)
	    
			$output += "Databases become healthy after $($i * 5) seconds`r`nResuming Transport Service...`r`n"

			Set-ServerComponentState –Identity $computerName -Component HubTransport -State Active -Requester Maintenance 
 
			$output += "Restarting the MSExchangeTransport Service...`r`n"

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

@{
    Status = $status
    Details = $output
}
