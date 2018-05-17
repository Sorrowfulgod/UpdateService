# NagiosAgent Post script
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

	$output += "Removing all downtimes for host `"$hostname`" in Nagios server`r`n"

    $nagiosURL = "https://$nagiosAddr"
    $tokenRegex = New-Object System.Text.RegularExpressions.RegEx("user_token\s+=\s+'(?<Token>[\d\w]+)'")
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

    if ( ([String]::IsNullOrEmpty($token)) )
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
                   "cmd_typ" = "c5";
                   "cmd_mod" = "2";
                   "host" = $nagiosHostName;
                   "active_downtimes" = "1";
                   "future_downtimes" = "2";
                   "backend" = $nagiosHostBackend;
                   "backend.orig" = $nagiosHostBackend;
                   "btnSubmit" = "Commit";
        }
        $response = Invoke-WebRequest -Uri "$nagiosURL/thruk/cgi-bin/cmd.cgi" -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -WebSession $nagsess -Headers $headers -UseBasicParsing
    }
    else
    {
	    $output += "Host $hostname not found in nagios!`r`n"
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