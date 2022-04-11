<#
    .SYNOPSIS
        This is a tool that can be used to parse F files when
        attempting to troubleshoot NO_CLIENT_SITE errors found on 
        Active Directory Domain Controllers.
    .DESCRIPTION
        This is a tool that can be used to parse NETLOGON.log files when
        attempting to troubleshoot NO_CLIENT_SITE errors found on 
        Active Directory Domain Controllers.  This script will reach out
        to each DC, import the data from it's NETLOGON.log, then process
        that data to return a list of IPs in CSV format.

    .PARAMETER ExportPath
        [Mandatory] Specifies the path to export CSV file, which is validated
        upon entry.  Script will not create path if it doesn't exist.
    .PARAMETER Days
        [Mandatory] Specifies the number of days prior to check the log files. 
        (last modified date and date in log file). 
        Default value: 1
        Accepted values: 1-31
    .PARAMETER LogMaxLines
        Number of lines to load from NETLOGON.log files.
        Default value: -250
        The newest entries are appended to the bottom of the file,
        so the number must be negative to pull in most recent data.

    .EXAMPLE
        .\Get-ADClientSitesNetLogon.ps1 -ExportPath C:\temp -Days 7

        This example will query all Domain Controllers in Active Directory
        and get the last 250 lines of each NETLOGON.log file.  It will only
        process the last 7 days from entries.
    
    .NOTES
        NAME:   Get-ADClientSitesNetLogon.ps1
        AUTHOR: Michael Garrison
        DATE:   2022/04/11

        REQUIREMENTS:
        - Permission to read \\DCName\admin$ directory
        - Permission to write to local directory of choosing

        VERSION HISTORY:
        1.0 2022.04.11
            Initial version.
#>

[CmdletBinding()]
PARAM (
    [Parameter(Mandatory = $true, HelpMessage = "You must specify a path to export the CSV file to.")]
    [ValidateScript({ 
        if (($_ | Test-Path) -ne $true) { 
            throw "Directory does not exist."
        } 
        return $true
    })]
    [System.IO.FileInfo]$ExportPath,

    [Parameter(Mandatory = $false, HelpMessage = "You must specify the number of days you want to check.")]
    [ValidateScript({
        if (($_ -gt 31) -or ($_ -le 0)) {
            throw "Days must be greater than 0, but not higher than 31"
        }
        return $true
    })]
    [int]$Days = 1,

    [Parameter(Mandatory = $false, HelpMessage = "Specify number of lines to check. Negative (-) = newest, postive = oldest")]
    [int]$LogMaxLines = -250
)

BEGIN {
    try {
        # Get list of Domain Controllers from Active Directory
        $AllDCs = (Get-ADForest).Domains | ForEach-Object { Get-ADDomainController -Filter * -Server $_ }
        # Define empty array to hold client information
        $noClientSiteIP = @()
        # Set oldest modified date based off $Days
        $dateOldest = (Get-Date).AddDays($Days * -1)
    } catch {
        Throw $_
    }
}
PROCESS {
    try {
        # Loop through each Domain Controller and process NETLOGON.log
        foreach ($DC in $AllDCs) {
            # Find NETLOGON.log on DC
            $netLogon = "\\$($DC.HostName)\c$\windows\debug\NETLOGON.log"
            # If the log has been modified withing the last few days, start processing file
            if ((Get-ChildItem $netLogon).LastWriteTime -gt $dateOldest) {
                # Store file contents in array
                $logContent = Get-Content $netLogon -Tail $LogMaxLines
                # Find last index of array (number of objects - 1)
                $logLines = $logContent.Count - 1
                # Loop through log starting with last index
                for ($i = $logLines; $i -ge 0; $i--) {
                    # Split each line into sections
                    $logSplit = $logContent[$i].Split(" ")
                    # If the log line date is sooner than the modified date we set, add subnet to array
                    if ($logSplit[0] -ge $dateOldest) {
                    # Add Date, Client, User, IP, Domain, and Error to the array
                        $noClientSiteIP += [PSCustomObject]@{
                            Date = $logSplit[0];
                            Client = $logSplit[3];
                            User = $logSplit[6];
                            Domain = $logSplit[4];
                            Error = $logSplit[5];
                            IPAddress = $logSplit[7]
                        }
                    } else { 
                        # Once log is looped through to a date out of the range, break the loop
                        break 
                    }
                }
            }
        }
    } 
    catch {
        Throw $_
    } 
    finally {
        # Export results to a CSV file
        $noClientSiteIP | Sort-Object IPAddress -Unique | Export-Csv -Path "$ExportPath\NoClientSiteSubnets-$(Get-Date -Format "MMddyyy").csv" -NoTypeInformation
    }
}