# NagiosAgent Pre script
param($nagiosAddr, $nagiosHost, $user, $pass)

$status = 1
$output = ""

try 
{
    Add-Type -AssemblyName System.Net.Http
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type)
    {
        Add-Type @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy {
                public bool CheckValidationResult(
                    ServicePoint srvPoint, X509Certificate certificate,
                    WebRequest request, int certificateProblem) {
                    return true;
                }
            }
"@
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    
    $hostname = $($env:ComputerName)

    if ($([String]::IsNullOrEmpty($nagiosHost)))
    {
        $nagiosHost = $nagiosAddr
    }
    
	$str = "Setting downtime for host `"$hostname`" in Nagios server" 
	$output += "$str`r`n"
	Write-Host $str

    $nagiosURL = "https://$nagiosAddr"
    $tokenRegex = New-Object System.Text.RegularExpressions.RegEx("user_token\s+=\s+'(?<Token>[\d\w]+)'")
    $now = Get-Date
    $startDate = $now.ToString("yyyy-MM-dd HH:mm:00")
    $endDate = $now.AddHours(8).ToString("yyyy-MM-dd HH:mm:00")
    $authHeader = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($user):$pass")))"

    $headers = @{Host = $nagiosHost; Authorization = $authHeader; UserAgent ="Mozilla/5.0 (Windows NT 10.0; WOW64; Trident/7.0; rv:11.0) like Gecko"}
    $response = Invoke-WebRequest -Uri "$nagiosURL/thruk/side.html" -SessionVariable nagsess -Headers $headers -UseBasicParsing

    $token = $null
    $body = $response.Content
    $tokenMatch = $tokenRegex.Match($body)
    if ($tokenMatch.Success)
    {
        $token = $tokenMatch.Groups["Token"].Value
    }
    else
    {
        throw "Unable to get auth token!"
    }

    $hostParseRegEx = New-Object System.Text.RegularExpressions.RegEx($("<a href='extinfo.cgi\?type=1&amp;host=(?<HostName>{0})&amp;backend=(?<BackEnd>[\w\d]+)'" -f $hostname), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $hostSearchURI = "$nagiosURL/thruk/cgi-bin/status.cgi?hidesearch=2&hidetop=&dfl_s0_hoststatustypes=15&dfl_s0_servicestatustypes=31&dfl_s0_hostprops=0&dfl_s0_serviceprops=0&style=hostdetail&dfl_s0_type=host&dfl_s0_val_pre=&dfl_s0_op=%7E&dfl_s0_value=$hostname&dfl_s0_value_sel=5"
    $response = Invoke-WebRequest -Uri $hostSearchURI -WebSession $nagsess -Headers $headers -UseBasicParsing
    $hostMatch = $hostParseRegEx.Match($response.Content)
    if ($hostMatch.Success)
    {
        $nagiosHostName = $hostMatch.Groups["HostName"].Value
        $nagiosHostBackend = $hostMatch.Groups["BackEnd"].Value

        $body = @{ "token" = $token;
                   "cmd_typ" = "55";
                   "cmd_mod" = "2";
                   "host" = $nagiosHostName;
                   "com_data" = "Set on maintance by update script";
                   "trigger" = "0";
                   "start_time" = $startDate;
                   "end_time" = $endDate;
                   "fixed" = "1";
                   "hours" = "2";
                   "minutes" = "0";
                   "com_author" = $user;
                   "childoptions" = "0";
                   "backend" = $nagiosHostBackend;
                   "backend.orig" = $nagiosHostBackend;
                   "btnSubmit" = "Commit";
        }
        $response = Invoke-WebRequest -Uri "$nagiosURL/thruk/cgi-bin/cmd.cgi" -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -WebSession $nagsess -Headers $headers -UseBasicParsing
    }
    else
    {
        $str = "Host $hostname not found in nagios!"
	    $output += "$str`r`n"
	    Write-Host $str
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