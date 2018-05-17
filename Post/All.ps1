$status = 1
$output = ""
try
{
	Write-Host "Dummy"
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
