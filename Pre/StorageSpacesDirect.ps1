$status = 1
$output = ""

try {
    $nodeName = $env:computername

    $str = "Enabling storage maintenance mode on $nodeName..."
    $output += "$str`r`n"
    Write-Host $str
    Get-StorageFaultDomain -type StorageScaleUnit -FriendlyName $nodeName | Enable-StorageMaintenanceMode

    Start-Sleep -Seconds 60    

    $startDate = [DateTime]::Now

    $str = "Check is S2D rebuild job in progress..."
    $output += "$str`r`n"
    Write-Host $str

    $remain = 1
    while($remain -and $remain -gt 0)
    {
        $remain = Get-StorageJob | ?{$_.BytesTotal -gt 0 -and $_.JobState -ne "Suspended"}  | %{ ($_.BytesTotal-$_.BytesProcessed) / 1gb}
        if ($remain)
        {
            $str = "Remained GB in rebuild: $remain"
            $output += "$str`r`n"
            Write-Host $str
            Start-Sleep -Seconds 60
        }
    }

    $str = "Job completed. Process duration: $([DateTime]::Now - $startDate)"
    $output += $str
    Write-Host $str
}
catch {
    $status = 0
    $output += $_
}

New-Object PSCustomObject -Property @{
    Status = $status;
    Details = $output;
}
