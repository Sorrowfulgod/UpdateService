$status = 1
$output = ""
try
{
	# make some work
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
