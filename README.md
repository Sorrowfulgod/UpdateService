# UpdateService
Update windows servers without service downtime


# SYNTAX
Update-Servers.ps1 [[-ServerList] <String[]>] [[-ServerListFile] <String>] [[-SkipServers] <String[]>]
[[-SMTPServer] <String>] [[-SMTPFrom] <String>] [[-SMTPTo] <String>] [-NoPostStep] [-OnlyCheckReboot] 
[-OnlyPostStep] [-OnlyShowList] [-DontStopOnError]
    
  - ServerList - comma separated list of servers to update. Can be mask: for example exch-srv*
  - ServerListFile - file with servers list to update (one per line)
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

# Description will coming soon
