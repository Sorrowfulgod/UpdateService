param([String[]]$SkipedUpdates, [bool]$OnlyCheck, [bool]$UsePSSession, [bool]$UseWMI)

try
{
    Import-Module PSScheduledJob -ErrorAction Stop

    #$ccmClient = ((Get-WmiObject -namespace root -class __NAMESPACE -filter "name='ccm'") -ne $null)
    $ccmUpdatesCount = -1
    if ($ccmClient)
    {
	    $status = 1
	    $output = ""
	    $updated = $false

	    $str = "Configuration manager client installed. Check for deployed updates..."
	    $output += "$str`r`n"
	    Write-Host $str

	    $updates = [Array](Get-WmiObject -Namespace root\ccm\clientsdk -Class CCM_SoftwareUpdate | ?{$_.EvaluationState -match "0" -or $_.EvaluationState -match "1"})
	    $ccmUpdatesCount = $updates.Count
	    if ($ccmUpdatesCount -eq 0)
	    {
		    $str = "No updates"
		    $output += $str
		    Write-Host $str
	    }
	    else
	    {
		    $str = "Available updates: $($($updates.FullName) | Out-String)"
		    $output += "$str"
		    Write-Host $str
	
		    if ($OnlyCheck)
		    {
			    $updated = $ccmUpdatesCount -gt 0
		    }
		    else
		    {
			    $updated = $false
			    $res = 0
			    for($i = 0; $i -le $updates.Count -and $res -eq 0; $i++)
			    {
				    $update = $updates[$i]
				    $str = "Installing $($update.FullName)..."
				    $output += "$str`r`n"
				    Write-Host $str

				    $toInstall = @($update)
				    $res = Invoke-WmiMethod -Class CCM_SoftwareUpdatesManager -Name InstallUpdates -ArgumentList (,$toInstall) -Namespace root\ccm\clientsdk
				    if ($res -ne 0)
				    {
					    $str = "Failed to install $($update.FullName)! Error $res"
					    $output += "$str`r`n"
					    throw $str
				    }
			    }
			    $updated = $true
		    }
	    }

	    $result =  New-Object PSCustomObject -Property @{
			    Status = $status;
			    Details = $output;
			    Data = $updated
	    }
    }

    if ($ccmUpdatesCount -le 0)
    {
	    $winVer = [int](((Get-WmiObject win32_operatingsystem).Version.Split("."))[0])

	    if ($winVer -ge 10 -and $UseWMI)
	    {
		    $status = 1
		    $output = ""
		    $updated = $true

		    $str = "Check for updates"
		    if ($SkipedUpdates -ne $null -and $SkipedUpdates.Count -gt 0)
		    {
			    $str += ". Skip $SkipedUpdates"
		    }
		    $output += "$str`r`n"
		    Write-Host $str

		    $noUpdates = $true

            $criteria = @{SearchCriteria="IsInstalled=0"}

            $newCIMClass = $false
            if (!$(Get-CimClass -Namespace root/Microsoft/Windows/WindowsUpdate -ClassName MSFT_WUOperationsSession  -ErrorAction SilentlyContinue))
            {
                $ci = New-CimInstance -Namespace root/Microsoft/Windows/WindowsUpdate -ClassName MSFT_WUOperations -Local
                $newCIMClass = $true
            }
            else
            {
		        $ci = New-CimInstance -Namespace root/Microsoft/Windows/WindowsUpdate -ClassName MSFT_WUOperationsSession 
                $criteria.Add("OnlineScan", $true)
            }

		    $installationResult = $ci | Invoke-CimMethod -MethodName ScanForUpdates -Arguments $criteria
		    if ($installationResult.ReturnValue -eq 0)
		    {
			    if ($installationResult.Updates.Count -gt 0)
			    {
				    $updatesToInstall = @()
				    foreach($result in $installationResult.Updates)
				    {
					    $skiped = $false
					    if ($SkipedUpdates -ne $null) { $SkipedUpdates | %{ if ($result.KBArticleIDs -match $_ -or $result.Title -match $_) { $skiped = $true } } }
					    if (!$skiped)
					    {
						    $updatesToInstall += $result
					    }
				    }

				    if ($updatesToInstall.Count -gt 0)
				    {
					    $noUpdates = $false

					    $str = "Available updates: $($($updatesToInstall.Title) | Out-String)"
					    $output += "$str"
					    Write-Host $str

					    if (-not $OnlyCheck)
					    {
						    $str = "Downloading ($($updatesToInstall.Count)) updates..."
						    $output += "$str`r`n"
						    Write-Host $str

						    #$installationResult = $ci | Invoke-CimMethod -MethodName DownloadUpdates -Arguments @{Updates=([CimInstance[]]$updatesToInstall)}
						    #if ($installationResult.ReturnValue -eq 0)
						    #{
							    $str = "Installing($($updatesToInstall.Count)) updates..."
							    $output += "$str`r`n"
							    Write-Host $str
	            
							    $success = $false
							    for ($i = 0; $i -lt $updatesToInstall.Count -and $installationResult.ReturnValue -eq 0; $i++)
							    {
								    $updateToInstall = @($updatesToInstall[$i])
							
								    $str = "Installing $($updateToInstall.Title) ($($i + 1) of $($updatesToInstall.Count))..."
								    $output += "$str`r`n"
								    Write-Host $str

								    $installationResult = $ci | Invoke-CimMethod -MethodName InstallUpdates -Arguments @{Updates=([CimInstance[]]$updateToInstall)}
							    }
						    #}

						    if ($installationResult.ReturnValue -ne 0 -and $installationResult.ReturnValue -ne 0)
						    {
							    $str = $("Failed! Result code: 0x{0:X}" -f $($installationResult.ReturnValue))
	    					    $output += "$str`r`n"
							    Write-Host $str
			        
							    $status = 0
						    }
						    else
						    {
							    $updated = $false
						    }
					    }
					    else
					    {
						    $updated = $updatesToInstall.Count -gt 0
					    }
				    }
			    }
		
			    if ($noUpdates)
			    {
				    if ($OnlyCheck)
				    {
					    $updated = $false
				    }
				    $str = "No updates"
				    $output += $str
				    Write-Host $str
			    }
		    }
		    else
		    {
			    $str = $("Failed! Result code: 0x{0:X}" -f $($installationResult.ReturnValue))
			    $output += "$str`r`n"
			    Write-Host $str
			        
			    $status = 0
		    }

		    $result =  New-Object PSCustomObject -Property @{
			    Status = $status;
			    Details = $output;
			    Data = $updated
		    }
	    }
	    else
	    {
		    if ($winVer -ge 10 -and !$UseWMI)
		    {
			    Write-Host "Possible use of WMI classes of winupdate, but config disallowed it. Using COM" -ForegroundColor Yellow
		    }

            if ($UsePSSession)
            {
			    Write-Host "Using PSSession mechanism in update"
            }
		    $str = "Start update job"
		    if ($SkipedUpdates -ne $null -and $SkipedUpdates.Count -gt 0)
		    {
			    $str += ". Skip $SkipedUpdates"
		    }
		    Write-Host $str

		    $jobScriptBlock = {
			    param([String[]]$SkipedUpdates, [bool]$OnlyCheck)

			    try 
			    {
				    $status = 1
				    $output = ""

				    $updated = $true

				    $objInstaller = New-Object -ComObject Microsoft.Update.Installer
				    if($objInstaller.IsBusy -eq -1)
				    {
					    $str = "Installer service is busy. Waitng for available..."
					    $output += "$str`r`n"
                        Write-Host $str

					    while($objInstaller.IsBusy)
					    {
						    Start-Sleep -Seconds 5
					    }
				    }

				    $str = "Check for updates..."
				    $output += "$str`r`n"
                    Write-Host $str
        
				    $updatesAvailable = @()

				    $updateSession = New-Object -ComObject Microsoft.Update.Session
				    $updateSearcher = $updateSession.CreateUpdateSearcher()
				    $searchCriteria = "IsInstalled=0 and Type='Software'"
				    $searchResult = $updateSearcher.Search($searchCriteria).Updates
				    $needUpdates = $searchResult.Count
				    foreach($result in $searchResult)
				    {
					    $skipped = $false
					    if ($SkipedUpdates -ne $null) 
					    { 
						    $SkipedUpdates | %{ if ($result.KBArticleIDs -match $_ -or $result.Title -match $_) 
								    { 
									    $needUpdates-- 
									    $skipped = $true
								    }
					
						    } 
					    }

					    if (!$skipped)
					    {
						    $updatesAvailable += "$($result.Title),$($result.KBArticleIDs)"
					    }
				    }

				    $str = "Available updates: $needUpdates`r`n"
				    $str += ($updatesAvailable | Out-String)
				    $output += "$str`r`n"
                    Write-Host $str

				    if ($needUpdates -gt 0)
				    {
					    if (-not $OnlyCheck)
					    {
						    $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl;
						    foreach($result in $searchResult)
						    {
							    if (-not $result.IsDownloaded)
							    {
								    $skiped = $false
								    if ($SkipedUpdates -ne $null) { $SkipedUpdates | %{ if ($result.KBArticleIDs -match $_ -or $result.Title -match $_) { $skiped = $true } } }

								    if ($skiped -or $result.InstallationBehavior.CanRequestUserInput)
								    {
									    $str = "Update $($result.Title) is skipped from downloading"
									    $output += "$str`r`n"
									    Write-Host $str
								    }
								    else
								    {
									    if ($result.EulaAccepted -eq 0) 
									    {
										    [void]($result.AcceptEula())
									    }
									    [void]($updatesToDownload.Add($result))
								    }
							    }
						    }
	
						    if ($updatesToDownload.Count -gt 0)
						    {
							    $str = "Downloading updates($($updatesToDownload.Count))..."
							    $output += "$str`r`n"
							    Write-Host $str

							    $updatesDownloader = $updateSession.CreateUpdateDownloader()
							    $updatesDownloader.Updates = $updatesToDownload
							    $downLoadResult = $updatesDownloader.Download()
	            
							    $str = "Download complete"
							    $output += "$str`r`n"
							    Write-Host $str
						    }
	
						    $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
						    foreach($result in $searchResult)
						    {
							    if ($result.IsDownloaded)
							    {
								    $skiped = $false
								    if ($SkipedUpdates -ne $null) { $SkipedUpdates | %{ if ($result.KBArticleIDs -match $_ -or $result.Title -match $_) { $skiped = $true } } }

								    if ($skiped -or $result.InstallationBehavior.CanRequestUserInput)
								    {
									    $str = "Update $($result.Title) is skipped from installing"
									    $output += "$str`r`n"
                                        Write-Host $str
								    }
								    else
								    {
	        						    if (-not [String]::IsNullOrEmpty($($result.EulaText)))
	        						    {
	            						    [void]($result.AcceptEula())
	        						    }
									    [void]($updatesToInstall.Add($result))
								    }
							    }
						    }
	
						    if ($updatesToInstall.Count -gt 0)
						    {
							    $str = "Installing($($updatesToInstall.Count)) updates..."
							    $output += "$str`r`n"
							    Write-Host $str
	            
							    $updateInstaller = $updateSession.CreateUpdateInstaller()
							    $updateInstaller.AllowSourcePrompts = 0
							    $updateInstaller.ForceQuiet = -1
							    $updateInstaller.Updates = $updatesToInstall
							    $installationResult = $updateInstaller.Install()

							    for($i = 0; $i -lt $updatesToInstall.Count; $i++) 
							    {
								    $updateItem = $updatesToInstall.Item($i);

								    $str = "$($updateItem.Title),$($updateItem.KBArticleIDs),$($installationResult.GetUpdateResult($i).ResultCode)"
								    $output += "$str`r`n"
								    Write-Host $str
							    }
		
							    if ($installationResult.ResultCode -ne 2 -and $installationResult.ResultCode -ne 3)
							    {
								    $str = $("Update failed! Result code: 0x{0:X}") -f $($installationResult.HResult)
	    						    $output += "$str`r`n"
								    Write-Host $str
			        
								    $status = 0
							    }
							    else
							    {
								    $updated = $false
							    }
						    }
						    else
						    {
							    $str = "Nothing to install"
							    $output += $str
							    Write-Host $str
						    }
					    }
					    else
					    {
						    $updated = $needUpdates -gt 0
					    }
				    }
				    else
				    {
					    if ($OnlyCheck)
					    {
						    $updated = $false
					    }
					    $str = "No updates"
					    $output += $str
					    Write-Host $str
				    }
			    }
			    catch {
				    $status = 0
				    $output += $_
			    }	

			    New-Object PSCustomObject -Property @{
				    Status = $status;
				    Details = $output;
				    Data = $updated
			    }
		    }
            if ($UsePSSession)
            {
                $result = $jobScriptBlock.Invoke(@($SkipedUpdates, $OnlyCheck))
            }
            else
            {
		        $jobParams = @{
			        Name = $("InstallUpdates $([Guid]::NewGuid())")
			        RunNow = $true
			        ScriptBlock = $jobScriptBlock
		        }
		        $jobParams.Add("ArgumentList", @($SkipedUpdates, $OnlyCheck))

		        $job = Register-ScheduledJob @jobParams
                $job.StartJob()

		        $task = $job
		        $currentLine = 0
		        $jobName = $($job.Name)
		        do
		        {
			        try
			        {
				        $job = Get-Job -Name $jobName -ErrorAction SilentlyContinue
				        Start-Sleep -Seconds 2
			        } catch {}

		        } while($job -eq $null)

		        Write-Host "Wait update job to complete..."

		        do
		        {
			        $job = Get-Job -Name $jobName
			        [void](Wait-Job -Job $job -Timeout 2)
		        } while ($job.State -eq 'Running')

		        $jobOutput = Receive-Job $job

		        $result = $jobOutput[$($jobOutput.Count)-1]

		        $job | Remove-Job
		        $task | Unregister-ScheduledJob -Force
            }
	    }
    }
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
