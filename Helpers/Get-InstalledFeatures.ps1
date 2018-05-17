$status = 1
$output = ""

function Remove-FeatureFromList
{
    param($featuresList, $featureToRemove)
    $newFeatures = @()

    foreach($f in $featuresList)
    {
        if ($f -notmatch $featureToRemove)
        {
            $newFeatures += $f
        }
    }

    return $newFeatures
}

try 
{
	$computerName = $($env:ComputerName)

    # Get installed feature for server
    [string[]] $features = Get-WindowsFeature | ? Installed | select -exp Name

    # additional check for S2D
    if ($features.Contains("Failover-Clustering")) 
    {
        $cluster = Get-Cluster -ErrorAction SilentlyContinue
        if ($cluster -ne $null)
        {
            if ($cluster.S2DEnabled -eq 1) # Storage spaces direct is enabled for cluster
            {
                $features += "StorageSpacesDirect"
            }
        }
        else # feature installed, but no cluster present
        {
            $features = Remove-FeatureFromList -featuresList $features -featureToRemove "Failover-Clustering"
        }
    }
    
	$features += "All"

    # Check for Azure Pack
    $uninstallKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $installedFeatures = gci $uninstallKey | %{ Get-ItemProperty "$uninstallKey\$($_.pschildname)" -Name "DisplayName" -ErrorAction SilentlyContinue | ? DisplayName -match "Windows Azure Pack" }
    if ($installedFeatures.Count -gt 0)
    {
		$features += "WindowsAzurePack"
    }

	# check for Nagios agent
	if ($(Get-Process nscp -ErrorAction SilentlyContinue))
	{
		$features += "NagiosAgent"
	}

	# check for SCOM agent - "Microsoft.Mom.Sdk.ServiceHost" is SDK service on SCOM server. Put SCOM server in maintenance mode is bad idea
	if ($(Get-Process MonitoringHost -ErrorAction SilentlyContinue) -and -not $(Get-Process "Microsoft.Mom.Sdk.ServiceHost" -ErrorAction SilentlyContinue))
	{
		$features += "SCOMAgent"
	}
    
	# check for VMM agent
	if ($(Get-Service SCVMMAgent -ErrorAction SilentlyContinue) -and !$(Get-Item "HKLM:\SOFTWARE\Microsoft\Microsoft System Center Virtual Machine Manager Server" -ErrorAction SilentlyContinue))
	{
		$features += "VMMAgent"
	}

    if ($features.Contains("NetworkController") -and !$features.Contains("SCOMAgent"))
    {
		$features += "SCOMAgent"
    }

    if ((Get-Item "HKLM:\SOFTWARE\Microsoft\ExchangeServer" -ErrorAction SilentlyContinue))
    {
		$features += "Exchange"
    }

    if ($(Get-Process msdpm -ErrorAction SilentlyContinue))
    {
		$features += "DPMServer"
    }
}
catch
{
    $status = 0
    $output = $_
}

New-Object PSCustomObject -Property @{
    Status = $status;
    Details = $output;
    Data = $features
}

