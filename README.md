# UpdateService
Update windows servers without service downtime


# SYNTAX
Update-Servers.ps1 [[-ServerList] <String[]>] [[-ServerListFile] <String>] [[-SkipServers] <String[]>]
[[-SMTPServer] <String>] [[-SMTPFrom] <String>] [[-SMTPTo] <String>] [-NoPostStep] [-OnlyCheckReboot] 
[-OnlyPostStep] [-OnlyShowList] [-DontStopOnError]
    
  - ServerList - comma separated list of servers to update. Can be mask: for example exch-srv*
  - ServerListFile - file with servers list to update (one per line)<br/>
  *If ServerList parameter is defined this list will be added, if no of list parameters is defined, list will be getted from Active Directory*
  - SkipServers - comma separated list skipped servers. Can be mask: for example exch-srv*
  - SMTPServer - ip address or fqdn of smtp server, used to send reports. Currently supports only anonymous smtp
  - SMTPFrom - <from> field in report letters
  - SMTPTo - comma separated list of report letters resipients
  - NoPostStep - don't exit maintenance mode
  - OnlyPostStep - perform only post steps (exit maintenance mode)
  - OnlyCheckReboot - check for reboot pending and reboot server with enter/exit maintenance mode
  - OnlyShowList - only shows generated list of servers to update
  - DontStopOnError - don't stop execution if any error occured. By default script execution will stop

# Update process

Update process flow for one server shown in UpdateProcess.png

 - First, update script uses **Helpers\Get-InstalledFeatures.ps1** for get server roles. This script returns array of server roles names (feel free to add nedeed roles detection"
 - **Helpers\Install-Updates.ps1** script check for available updates for server (script can work in **COM mode, WMI mode (pre server 1709 editions, and past - WMI mechanism is changed!)**. Also have support to work in custom powershell sessions)
 - - if updates not available, go to next server processing
 - - if updates available
 - - - Enter maintenance mode, by execution scripts from **Pre** folder - scripts selected by names, contains in server roles list
 - - - Using script script **Pending-Reboot.ps1** check for server pending reboot. Reboot if necessary
 - - - Check and install updates. Check for pending reboot. Reboot if necessary. Loop until no updates is available
 - - - Exit maintenance mode, by execution scripts from **Post** folder - scripts selected by names, contains in server roles list
 - - - Run script **Helpers\Start-Services.ps1** on updated server to ensure all services with start mode **Automatic** is started
 
# Existing maintenace modules
- AD-Domain-Services.ps1: Pre script for Active Directory Domain Controllers - check current updated domain controller for holding RID or PDC fsmo roles. If so - moves fsmo to another domain controller
- DPMServer.ps1 - Pre/post scripts for DPM server. Enter maintenace mode: disable agents, wait for all jobs completion. Exit maintenace mode: enable agents, check protected sources consistency. If not conststent - run check
- Exchange.ps1 - Pre/post scripts for Exchange server. Works only on DAG members. Enter maintenace mode: move all active database copies to another DAG members, disable database activation, draining transport queue, disable all componets on server. Exit maintenace mode: enable database activation, enable all componets on server
- Failover-Clustering.ps1 - Pre/post scripts for Failover Clustering. Enter maintenace mode: if cluster contains only VM roles - suspend node without draining, in other case node not suspended because update may fail (SQL Cluster, SQL Always On, VMM), lower node weight to avoid quorum recalculation on reboot, move all owned roles to another cluster nodes. Exit maintenace mode: if node suspened - resume node, restore node weight.
- NagiosAgent.ps1 - Pre/post script for managing server downtime in Nagios
- NLB.ps1 - Pre/post scripts for NLB cluster nodes. Enter maintenace mode: stop NLB node, set node proterties to initial state 'Stopped' and retain suspended. Exit maintenace mode: start NLB node, set node properties to initial state 'Started' and not retain suspended
- SCOMAgent.ps1 - Pre/post script for managing server downtime in SCOM. When entering maintenance mode sleep 5 minutes for monitors unload (avoid unneeded alerts)
- StorageSpacesDirect.ps1 - Post script for Storage Spaces Direct nodes. Waites for end of array(s) rebuild. In other case update of other S2D nodes will fail

# Config format
 
coming soon
 
# Maintenance module description
 
**Dummy-Module.ps1** is example of maintenance module. Module must return PSObject with two properties: **Status (1 - success, 0 - fail)** and **Output (this will be writted to log)**. Feel free using of **Write-Host** to display module progress
 
# Coming soon
 
Script for creation update powershell session on servers. How to achieve security and manage access to update process.
