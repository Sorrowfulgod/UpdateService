Import-Module ActiveDirectory

$status = 1
$output = ""
try
{
    $computerName = $($env:ComputerName)
	$domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
	if ($domain.DomainControllers.Count -eq 1)
	{
        $str = "There is only one domain controller! Transfer of roles not possible!";
		$output += "$str`r`n"
        Write-Host $str
	}
	else
	{
		$shortRIDOwner = $domain.RIDRoleOwner.Name -replace "\..*$"
		$shortPDCOwner = $domain.PDCRoleOwner.Name -replace "\..*$"
		
		$ridRoleTransfered = $false;
		$pdcRoleTransfered = $false;
	
		$currDC = $domain.DomainControllers | Where {$_.Name -match $computerName};
		$otherDomainControllers = $domain.DomainControllers | Where {$_.Name -notmatch $computerName -and $_.SiteName -eq $($currDC.SiteName)};
		if ($otherDomainControllers -is [System.Array])
		{
			$transferTo = $otherDomainControllers[0].Name -replace "\..*$";
		}
		else
		{
			$transferTo = $otherDomainControllers.Name -replace "\..*$";
		}

		if ($domain.RIDRoleOwner.Name -match $computerName)
		{
            $str = "$computerName is RID role holder. Moving role to $transferTo"
			$output += "$str`r`n"
            Write-Host $str
			Move-ADDirectoryServerOperationMasterRole -Identity $transferTo -OperationMasterRole RIDMaster -Confirm:$false
		}

		if ($domain.PDCRoleOwner.Name -match $computerName)
		{
            $str = "$computerName is PDC role holder. Moving role to $transferTo"
			$output += "$str`r`n"
            Write-Host $str
			Move-ADDirectoryServerOperationMasterRole -Identity $transferTo -OperationMasterRole PDCEmulator -Confirm:$false
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
    Details = $output 
}
