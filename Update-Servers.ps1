<#
.NOTES
    Copyright (c) Sergey Gruzdov. All rights reserved.
    
    Update servers without services downtime

    .SYNOPSIS
        Update servers without services downtime

    .DESCRIPTION
        Update servers without services downtime. If no of Server* parameters specified - get servers list from AD

    .PARAMETER ServerList
        Comma-delitited list of servers for update

    .PARAMETER SkipServers
        Comma-delitited list of skipped servers

    .PARAMETER ServerListFile
        File contained list of servers for update (one server per line)

    .PARAMETER DontStopOnError
        Don't stop update on errors
        
    .PARAMETER SMTPServer
        SMTP server for notifications

    .PARAMETER SMTPFrom
        From
    
    .PARAMETER SMTPTo
        To
        #>
param(
    [string[]]
    $ServerList,

    [string[]]
    $SkipServers,

    [string]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $(Resolve-Path $_) })]
    $ServerListFile,

    [string]
    $SMTPServer = $null,

    [string]
    $SMTPFrom = $null,

    [string]
    $SMTPTo = $null,

    [switch]
    $NoPostStep,

    [switch]
    $OnlyCheckReboot,

    [switch]
    $OnlyPostStep,

    [switch]
    $OnlyShowList,

    [switch]
    $DontStopOnError = $false
)

function Log($message, $color = "Gray", [switch]$OnlyFile = $false, $Server) 
{
    $strOutput = "$([DateTime]::now.Tostring("dd-MM-yyyy HH:mm:ss")): $message"
    if (!$onlyFile)
    {
        Write-Host $strOutput -ForegroundColor $([ConsoleColor]$color)
    }
    $strOutput | Out-File -FilePath $logFile -Append -Encoding ascii
    
    if ($server)
    {
        $strOutput | Out-File -FilePath $($logPattern -f $server) -Append -Encoding ascii
    }
}

function InvokeStep($serverName, $fileName, $arguments, $feature)
{
	$usePSSession = $false

	$psSessionParams = @{}
	if ($xmlConfig.Configuration.GlobalParams.PSSession)
	{
		$rolePSSession = $xmlConfig.Configuration.GlobalParams.PSSession
        $psSessionParams.Add("ComputerName", $serverName)
	}

	if ($feature -and $xmlConfig -ne $null)
    {
		$arguments = @()
		$argumentsNames = @()
		$rolesConfigration = $xmlConfig.Configuration.Role | ? rolename -eq $feature
		$roleActionParams = $roleConfig.Param
		if ($roleActionParams)
		{
			foreach($param in $roleActionParams)
			{
				$argumentsNames += $param.Name
                if ($param.Type -match "string")
                {
				    Invoke-Expression "`$arg = [$($param.Type)]`"$($param.Value)`""
                }
                else
                {
				    Invoke-Expression "`$arg = [$($param.Type)]::Parse(`"$($param.Value)`")"
                }

				$arguments += $arg
			}
		}

		if($arguments.Count -gt 0)
		{
			Write-Host "Adding arguments `"$argumentsNames`" for role $($roleConfig.roleName)"
		}

        if (!$rolePSSession)
        {
		    $rolePSSession = $roleConfig.PSSession
        }
	}
	else
	{
		if (!$arguments)
		{
			$arguments = @()
		}

		# check global parameters for invoked helpers
		if ($xmlConfig.Configuration.GlobalParams)
		{
			$fileParams = $xmlConfig.Configuration.GlobalParams.Param | ?{$fileName -match $_.Helper}
			foreach($fParam in $fileParams)
			{
				foreach($fparam in $fileParams)
				{
                    if ($fparam.Type -match "string")
                    {
				        Invoke-Expression "`$filearg = [$($fparam.Type)]`"$($fparam.Value)`""
                    }
                    else
                    {
				        Invoke-Expression "`$filearg = [$($fparam.Type)]::Parse(`"$($fparam.Value)`")"
                    }

					Write-Host "Adding argument `"$($fparam.Name)`" with value `"$filearg`" for helpers $fileName" -ForegroundColor Magenta
					$arguments += $filearg
				}
			}
		}
	}

	if ($rolePSSession)
	{
		$usePSSession = $true
		foreach($param in $rolePSSession.Param)
		{
			if ($param.variable)
			{
				$varName = $param.variable
				Invoke-Expression "`$paramValue = `$(`$param.value) -f $varName"
			}
			else
			{
				$paramValue = $param.value
			}

            if ( $($psSessionParams.ContainsKey("ComputerName") -and $param.Name -eq "ConnectionUri"))
            {
		        throw "ComputerName and ConnectionUri must not be specifed together!"
            }

            if ($($psSessionParams.ContainsKey("ConfigurationName") -and $param.Name -eq "ConfigurationName"))
            {
		        throw "Duplicate ConfigurationName parameter!"
            }

			$psSessionParams.Add($param.Name, $paramValue)
		}
	}

	$status = 0
	for($i = 1; $i -le $maxStepIterations -and $status -eq 0; $i++)
	{
		try
		{
			if ($i -gt 1) # 
			{
				Log -Message  "Waiting availability of '$serverName'..." -Color "Cyan"
				do
				{
					Start-Sleep -Seconds 5
				} while (!(Test-WSMan -ComputerName $serverName -ErrorAction SilentlyContinue))
				Log -Message "'$serverName' is available" -Color "Cyan"
			}

			$invokeCommandParams = @{
                FilePath = $fileName;
                ErrorAction = "Stop"
            }

            if ($usePSSession)
            {
                $session = New-PSSession @psSessionParams -Authentication Negotiate
                $invokeCommandParams.Add("Session", $session)
                $arguments += $usePSSession # always last parameter!!!!!!!!!!!!!
            }
            else
            {
                $invokeCommandParams.Add("ComputerName", $serverName)
            }

            $invokeCommandParams.Add("ArgumentList", $arguments)

	        $stepResult = Invoke-Command @invokeCommandParams
            if ($stepResult -and $stepResult.Status -eq 0)
            {
				Log -Message $("Error `"{0}`" during step invoke on try $i of $maxStepIterations. Sleep 30 seconds" -f $($stepResult.Details)) -Color "Yellow"
				Start-Sleep -Seconds 30
            }
		}
		catch
		{
			Log -Message "Exception `"$_`" during step invoke on try $i of $maxStepIterations. Sleep 30 seconds" -Color "Red"
			Start-Sleep -Seconds 30
			$stepResult = New-Object PSCustomObject -Property @{
				Status = 0;
				Details = $_;
			}
		}
        finally
        {
            if ($session -ne $null)
            {
                Remove-PSSession $session
            }
        }

        if ($stepResult)
        {
            $status = $stepResult.Status
        }
	}
            
    if (!([String]::IsNullOrEmpty($stepResult.Details)) -and  !([String]::IsNullOrWhiteSpace($stepResult.Details)))
    {
        Log -Message $($stepResult.Details) -Server $serverName
    }

    if ($stepResult.Status -ne 1) 
    {
        Log -Message $("Step failed! Status `"{1}`", Details: {0}" -f $($stepResult.Details), $stepResult.Status) -Color "Red" -Server $serverName
        if ($DontStopOnError) 
        {
            Log -Message "DontStopOnError switch defined. Continuing exectuion" -Color "Yellow"
            $stepResult.Status = 1
        }
    }
    
    return $stepResult
}

function CheckFeaturesActions($featuresList, $prefix, $ServerName) 
{
	$computerName = $ServerName
    foreach($feature in $featuresList) 
    {
        $scriptFileName = "$invokePath\$prefix\{0}.ps1" -f $feature

        if (Test-Path $scriptFileName)
        {
			$roleConfig = $xmlConfig.Configuration.Role | ? roleName -eq $feature
			if ($roleConfig -ne $null -and $roleConfig.local -eq "true")
			{
				$computerName = "."
			}
            Log -Message $("Found $prefix-update script for feature '{0}'. Invoking on '$computerName'..." -f $feature) -Color "Yellow"
            $actionsResult = InvokeStep -serverName $computerName -fileName $scriptFileName -feature $feature
            if ($actionsResult -eq $null -or $actionsResult.Status -eq 0) 
            {
                Log -message "InvokeStep for feature $feature failed! Details: $($actionsResult.Details)"
                return $false
            }
        }
    }

    return $true
}

function CheckPendingReboot
{
	param($server,  $features = $null)
	
    Log -Message "Check pending reboot for '$server'" -Color "Cyan"
    $result = $(InvokeStep -serverName $server -fileName $pendingRebootStep)
    if ($result.Status -eq 0) 
    {
        return $false
    }
    if ($result.Data) 
    {
        Log -Message "Reboot pending on '$server'. Rebooting..." -Color "Cyan"

	    if ($features)
	    {
                Log -Message "Features list defined for '$server'. Invoking 'pre' steps..." -Color "Yellow"
		    if (!$(CheckFeaturesActions -featuresList $installedFeatures -prefix "pre" -ServerName $serverName))
		    {
			    throw $("CheckPendingReboot: pre steps failed!")
		    }
	    }

	    $rebootStart = Get-Date	

        try
        {
            Restart-Computer -ComputerName $server -Force -Wait -For Powershell -ErrorAction Stop
        }
        catch
        {
            Log -Message "'Restart-Computer' failed on '$server'. Invoke 'shutdown.exe'..." -Color "Cyan"
            Invoke-Command -ComputerName $serverName -ScriptBlock { shutdown -r -t 0 }

            Log -Message  "Waiting for '$server' to shutdown..." -Color "Cyan"
            while ($(Test-WSMan -ComputerName $server -ErrorAction SilentlyContinue)) {}
        }
    
        Log -Message  "Waiting '$server' to startup and remoting is UP..." -Color "Cyan"
        do 
	    {
            Start-Sleep -Seconds 5
        } while (!(Test-WSMan -ComputerName $server -ErrorAction SilentlyContinue))

	    $rebootEnd = Get-Date	
	    $rebootDiff = $rebootEnd - $rebootStart
        Log -Message "'$server' is back after $([Math]::Round($rebootDiff.TotalSeconds)) sec" -Color "Cyan"
    
        Log -Message "Starting services on '$serverName'" -Color "White"
        $result = $(InvokeStep -serverName $serverName -fileName $startServicesStep) # Ignore results

	    if ($features)
	    {
            Log -Message "Features list defined for '$server'. Invoking 'post' steps..." -Color "Yellow"
		    if (!$(CheckFeaturesActions -featuresList $installedFeatures -prefix "post" -ServerName $serverName))
		    {
			    throw ""
		    }
	    }
	}
    else 
    {
        Log("Reboot not pending on '{0}'" -f $server) -Color "Cyan"
    }

    return $true
}

function SendReport
{
	param([String]$Message = "...", [String]$Subject)

	if ( !([String]::IsNullOrEmpty($SMTPServer)) -and !([String]::IsNullOrEmpty($SMTPFrom)) -and !([String]::IsNullOrEmpty($SMTPTo)))
	{
	    $messageParameters = @{
		    Subject = $Subject
		    Body = $Message
		    From = $SMTPFrom
		    To = $SMTPTo
		    SmtpServer = $SMTPServer
	    }
	    Send-MailMessage @messageParameters
    }
}

function Get-ADComputerViaADSI
{
    param($name, $spn)

    if (!([String]::IsNullOrEmpty($name)))
    {
        $nameParam = "(|(name=$name)(dnsHostName=$name))"
    }

    if (!([String]::IsNullOrEmpty($spn)))
    {
        $spnParam = "(ServicePrincipalName=$spn*)"
    }

    $domainDN = ([adsi]"LDAP://RootDSE").Properties["defaultNamingContext"]
    $compSearcher = New-Object System.DirectoryServices.DirectorySearcher($domainDN)
    $compSearcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
    $compSearcher.Filter = "(&(objectCategory=Computer)(!(userAccountControl:1.2.840.113556.1.4.803:=2)){0}{1})" -f $nameParam, $spnParam
    [void]($compSearcher.PropertiesToLoad.Add("DNSHostName"))
    $sortOption = New-Object System.DirectoryServices.SortOption("DNSHostName", [System.DirectoryServices.SortDirection]::Ascending);
    $compSearcher.Sort = $sortOption
    $resultComputers = $compSearcher.FindAll()
    $resultComputers | %{ $_.Properties["DNSHostName"] }
}

#
# Main Body
#
try 
{
    $updateProcessSuccess = $true
    $localNetbios = $($env:ComputerName)
    $localFQDN = "{0}.{1}" -f $($env:ComputerName), $((Get-WmiObject -Class Win32_ComputerSystem).Domain)

    $invokePath = $(Split-Path $MyInvocation.MyCommand.Path)
	$invokeDateTime = [DateTime]::now.Tostring("dd-MM-yyyy-HH-mm-ss")
	if (! (Get-Item "$invokePath\Logs" -ErrorAction SilentlyContinue) )
	{
		[void](New-Item -ItemType Directory "$invokePath\Logs" -ErrorAction SilentlyContinue)
	}
    $logPattern = "$invokePath\Logs\{0}_$invokeDateTime.log"
    $logFile = $logPattern -f "update"
    $skippedLogFile = $logPattern -f "skipped"

    $xmlConfigPath = "$invokePath\config.xml"
    [xml]$xmlConfig = Get-Content $xmlConfigPath -ErrorAction SilentlyContinue

    $usePSSession = $($xmlConfig.Configuration.GlobalParams.PSSession -ne $null)

    $installedFeaturesStep = "$invokePath\Helpers\Get-InstalledFeatures.ps1"
    $pendingRebootStep = "$invokePath\Helpers\Pending-Reboot.ps1"
    $installUpdatesStep = "$invokePath\Helpers\Install-Updates.ps1"
    $startServicesStep = "$invokePath\Helpers\Start-Services.ps1"

    $maxUpdateIterations = 6
	$maxStepIterations = 5

    if ($ServerList -ne $null) 
    {
        $ServersForUpdate = @()
        foreach($srv in $ServerList)
        {
            if ( !$($srv.Contains("*")) )
            {
                $ServersForUpdate += $srv
            }
            else
            {
                $maskedServersList = Get-ADComputerViaADSI -name $srv
                foreach($maskSrv in $maskedServersList)
                {
                    $ServersForUpdate += $maskSrv
                }
            }
        }
    } 
    elseif($ServerListFile) 
    {
        $ServersForUpdate = (gc $ServerListFile).Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries)
    }
    else
    {
        $ServersForUpdate = Get-ADComputerViaADSI
    }

    # send mail about start update process
	$str = "Update process started at $invokeDateTime"

    $message = "Updating servers: `r`n"	
	$message += $ServersForUpdate

	Log -message $str
	Log -message $($message | Out-String)
	SendReport -Subject $str -Message $($message | Out-String)

    if ($OnlyShowList)
    {
	    $str = "OnlyShowList parameter speficied. Exiting"
	    Log -message $str

        return
    }

    Log -message $("Invoked from '{0}'. Logging to '{1}'" -f $invokePath, $logFile)
    $updatedServers = @()
    
    $updatedCount = 0
    foreach ($serverName in $ServersForUpdate) 
    {
            
	    $updatedCount++
		$str = "Updating '{0}' ({1} of {2})" -f $serverName, $updatedCount, $ServersForUpdate.Count
        Log  -message $str -Color "Green"
		SendReport -Subject $str

        $skipped = $false
        if ($SkipServers -ne $null)
        {
            $SkipServers | %{ if ($serverName -match $_) {
                    $mesStr = "'{0}' is in skipped list" -f $serverName
                    Log -message $mesStr -Color "Yellow"
				    SendReport -Subject $mesStr
                    $mesStr | Out-File $skippedLogFile -Append -Encoding ascii

                    $skipped = $true
                }
            }
        }

        if (!$skipped)
        {
            if ($serverName -eq $localNetbios -or $serverName -eq $localFQDN -or $SMTPServer -match $serverName)
            {
                $mesStr = "'{0}' is script execution server or SMTP server. Skipped" -f $serverName
                Log -message $mesStr -Color "Yellow"
                $mesStr | Out-File $skippedLogFile -Append -Encoding ascii
				SendReport -Subject $mesStr
            }
            elseif ((Get-ADComputerViaADSI -name $serverName -spn "MSClusterVirtualServer").Count -gt 0)
            {
                $mesStr = "'{0}' is VCO or CNO. Skipped" -f $serverName
                Log -message $mesStr -Color "Yellow"
                $mesStr | Out-File $skippedLogFile -Append -Encoding ascii
				SendReport -Subject $mesStr
            }
            else
            {
                if (!$(Test-WSMan -ComputerName $serverName -ErrorAction SilentlyContinue))
                {
                    $mesStr = "'{0}' not responding. Skipped" -f $serverName
                    Log -message $mesStr -Color "Yellow"
                    $mesStr | Out-File $skippedLogFile -Append -Encoding ascii
					SendReport -Subject $mesStr
                }
                else 
                {
                    $errorInUpdate = $false
                    $hasUpdates = $false
                    try
                    {
                        # get installed features for server
                        Log -Message $("Get installed features on '{0}'" -f $serverName) -Color "White"
                        $result = $(InvokeStep -serverName $serverName -fileName $installedFeaturesStep)
                        if ($result.Status -ne 1) 
                        {
                            throw "Error invoke step `"$installedFeaturesStep`""
                        }
                        $installedFeatures = @($result.Data)
						Log -Message $("Installed features: $installedFeatures") -Color "White"

                        $updated = $false
                        # check skipped updates for roles
                        $skippedUpdates = @()
                        if ($xmlConfig -ne $null)
                        {
                            $rolesConfigrationList = $xmlConfig.Configuration.Role
                            if ($rolesConfigrationList -ne $null)
                            {
								foreach($roleConfig in $rolesConfigrationList)
								{
									if ($installedFeatures -contains $roleConfig.roleName)
									{
										if (!$([String]::IsNullOrEmpty($roleConfig.skipUpdates)))
										{
											$skippedUpdates += $roleConfig.skipUpdates.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries)
										}
									}
								}
                            }
                        }

                        if (!$OnlyPostStep -and !$OnlyCheckReboot)
                        {
                            # check for updates on server
                            Log -Message $("Check for updates on '{0}'" -f $serverName) -Color "White"
                            $result = $(InvokeStep -serverName $serverName -fileName $installUpdatesStep -Arguments @($skippedUpdates, $true, $usePSSession))
                            if ($result.Status -ne 1) 
                            {
                                throw $("Error check for updates on '{0}'" -f $serverName)
                            }

                            if ($result.Data)
                            {
                                $hasUpdates = $true

                                # check for pre-update step
                                if (!$(CheckFeaturesActions -featuresList $installedFeatures -prefix "pre" -ServerName $serverName))
                                {
                                    throw "Check pre actions failed!"
                                }
                                
                                #
                                # here update process
                                if (!$(CheckPendingReboot -server $serverName)) 
                                {
									throw "Check pending reboot failed!"
                                }
                    
                                $updateIterations = 0
                                while(!$updated -and $updateIterations -ne 5)
                                {
                                    # here check for reboot needed
                                    Log -Message $("Check and install updates on '{0}'" -f $serverName) -Color "White"
                                    $result = $(InvokeStep -serverName $serverName -fileName $installUpdatesStep -Arguments @($skippedUpdates, $false, $usePSSession))
                                    if ($result.Status -ne 1) 
                                    {
                                        if ($updateIterations -ne $maxUpdateIterations)
                                        {
                                            $updateIterations++
                                            Log -Message $("Trying again after 30 seconds. Iteration '$updateIterations' of $maxUpdateIterations..." -f $serverName) -Color "White"
                                            Start-Sleep -Seconds 30
                                        }
                                        else
                                        {
                                            throw "Maximum update iteration exceeded!"
                                        }
                                    }
                                    else
                                    {
                                        $updated = $result.Data
                                    }

                                    if (!$(CheckPendingReboot -server $serverName)) 
                                    {
										throw "Check pending reboot failed!"
                                    }
                                    $updateIterations++
                                }

                                if ($updateIterations -eq $maxUpdateIterations)
                                {
                                    $updated = $true
                                    Log -Message $("Update process exceed max iterations($maxUpdateIterations). Possible WinUpdate bug" -f $serverName) -Color "Yellow"
                                }
                                # end of update process
                                #

                                if (!$updated)
                                {
                                    throw "Not updated!"
                                }
                            }
                            else
                            {
								$noUpdatesMessage = $("No updates for '{0}'" -f $serverName)
                                Log -Message $noUpdatesMessage
								SendReport -Subject $noUpdatesMessage
                            }
                        }
                        else
                        {
							if (!$OnlyCheckReboot)
							{
								Log -Message "OnlyPostStep switch specified. Update skipped" -Color "Yellow"
							}
                        } # only post step

						if (!$OnlyCheckReboot)
						{
							if ($updated -or $OnlyPostStep)
							{
								# check for post-update step
								if (!$(CheckFeaturesActions -featuresList $installedFeatures -prefix "post" -ServerName $serverName)) 
								{
									throw ""
								}
							}
							elseif ($NoPostStep)
							{
								Log -Message "NoPostStep switch specified. Post step skipped" -Color "Yellow"
							}
						}
						else
						{
							Log -Message "OnlyCheckReboot switch specified" -Color "Yellow"
                            if (!$(CheckPendingReboot -server $serverName -features $installedFeatures)) 
                            {
								throw ""
							}
						}
                    }
                    catch
                    {
                        $errorInUpdate = $true
                        $updated = $false
                        Log -Message $("Exception in update script: '{0}'" -f $_) -Color "Red"
                    }
                    finally
                    {
						$serverUpdateReport = "..."
						$serverLogPath = $($logPattern -f $serverName)
						if ($(Test-Path $serverLogPath))
						{
							$serverUpdateReport = gc $serverLogPath -Raw
						}

                        if ($hasUpdates -and $updated)
                        {
                            $updatedServers += $serverName
							$updateStatus = "'{0}' updated successfully" -f $serverName
                            Log -Message $updateStatus -Color "White"
							SendReport -Subject $updateStatus -Message $serverUpdateReport
                        }
                        elseif ($hasUpdates -and (!$updated -or $errorInUpdate))
                        {
							$updateStatus = "'{0}' update failed" -f $serverName
                            Log -Message $updateStatus -Color "Red"
							SendReport -Subject $updateStatus -Message $serverUpdateReport
                            throw ""
                        }
                    }
                }
            } # update
        } # skipped
    }
}
catch 
{
    $updateProcessSuccess = $false
    Log -Message $("Exception in update script: '{0}'" -f $_) -Color "Red"
}

$str = "Update process finished at $([DateTime]::now.Tostring("dd-MM-yyyy-HH-mm-ss"))"
$updateReport = gc $logFile -Raw

if ($(Test-Path $skippedLogFile))
{
	$skippedServers = (gc $skippedLogFile -Raw) | Out-String
}

$updatedServersString = $updatedServers | Out-String
$updateDetails = "Updated servers: $updatedServers`r`n`r`nSkipped servers: $skippedServers`r`n---------------"
Log -message $updateDetails
Log -message $str
SendReport -Subject $str -Message "$updateDetails`r`nUpdate log: `r`n$updateReport"
