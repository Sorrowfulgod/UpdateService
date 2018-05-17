$status = 1
$output = ""

try 
{
    Get-WmiObject -Query "Select name,StartMode,state From Win32_Service Where startmode='Auto' and state = 'Stopped' and not name like '%clr_optimization%' and name != 'sppsvc' and name != 'ShellHWDetection' and name != 'RemoteRegistry'" | %{$str = "Starting `"$($_.Name)`""; $output += "$str`r`n"; Write-Host $str; [void](Start-service $_.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)}
} catch {
    $status = 0
    $output += $_
}			

New-Object PSCustomObject -Property @{
    Status = $status;
    Details = $output;
}
