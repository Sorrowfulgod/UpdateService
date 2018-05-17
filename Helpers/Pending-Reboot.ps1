$status = 1
$output = ""

try 
{
    $CompPendRen,$PendFileRename,$Pending,$SCCM = $false,$false,$false,$false

    $CBSRebootPend = $null
						
    $WMI_OS = Get-WmiObject -Class Win32_OperatingSystem -Property BuildNumber, CSName -ErrorAction Stop

    $HKLM = [UInt32] "0x80000002"
    $WMI_Reg = [WMIClass] "\\.\root\default:StdRegProv"
						
    if ([Int32]$WMI_OS.BuildNumber -ge 6001) {
        $RegSubKeysCBS = $WMI_Reg.EnumKey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\")
        $CBSRebootPend = $RegSubKeysCBS.sNames -contains "RebootPending"		
    }
							
	$RegWUAURebootReq = $WMI_Reg.EnumKey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\")
	$WUAURebootReq = $RegWUAURebootReq.sNames -contains "RebootRequired"
						
	$RegSubKeySM = $WMI_Reg.GetMultiStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\Session Manager\","PendingFileRenameOperations")
	$RegValuePFRO = $RegSubKeySM.sValue

	$Netlogon = $WMI_Reg.EnumKey($HKLM,"SYSTEM\CurrentControlSet\Services\Netlogon").sNames
	$PendDomJoin = ($Netlogon -contains 'JoinDomain') -or ($Netlogon -contains 'AvoidSpnSet')

	$ActCompNm = $WMI_Reg.GetStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName\","ComputerName")            
	$CompNm = $WMI_Reg.GetStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\","ComputerName")

	if (($ActCompNm -ne $CompNm) -or $PendDomJoin) {
	    $CompPendRen = $true
	}
						
	if ($RegValuePFRO) {
		$PendFileRename = $true
	}

	$CCMClientSDK = $null
	$CCMSplat = @{
	    NameSpace='ROOT\ccm\ClientSDK'
	    Class='CCM_ClientUtilities'
	    Name='DetermineIfRebootPending'
	    ComputerName='.'
	    ErrorAction='Stop'
	}
	## Try CCMClientSDK
	try {
	    $CCMClientSDK = Invoke-WmiMethod @CCMSplat
	} catch [System.UnauthorizedAccessException] {
	    $CcmStatus = Get-Service -Name CcmExec -ErrorAction SilentlyContinue
	    if ($CcmStatus.Status -ne 'Running') {
	        $output += "Error - CcmExec service is not running.`r`n"
	        $CCMClientSDK = $null
	    }
	} catch {
	    $CCMClientSDK = $null
	}

	if ($CCMClientSDK) {
	    if ($CCMClientSDK.ReturnValue -ne 0) {
		    $output += "Error: DetermineIfRebootPending returned error code $($CCMClientSDK.ReturnValue)`r`n"
		}
		if ($CCMClientSDK.IsHardRebootPending -or $CCMClientSDK.RebootPending) {
		    $SCCM = $true
		}
	}
	else {
	    $SCCM = $null
	}

	$RebootPending = ($CompPendRen -or $CBSRebootPend -or $WUAURebootReq -or $SCCM -or $PendFileRename)
} catch {
    $status = 0
    $output += $_
}			

New-Object PSCustomObject -Property @{
    Status = $status;
    Details = $output;
    Data = $RebootPending
}
