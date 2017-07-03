﻿<#
.DESCRIPTION
    This scipt reads all expected backup schedules and verifies with currently available backup catalogs, then lists (prints) all missed backup(s). 

.PARAMS 

    SubscriptionId: Specifies the ID of the subscription.
    DeviceName: Specifies the name of the StorSimple device on which to create/update the volume.
    ResourceGroupName: Specifies the name of the resource group on which to create/update the volume.
    ManagerName: Specifies the name of the resource (StorSimple device manager) on which to create/update the volume.

#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Specifies the ID of the subscription.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource group on which to read backup schedules and backup catalogs.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource (StorSimple device manager) on which to read backup schedules and backup catalogs.")]
    [String]
    $ManagerName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the StorSimple device on which to read backup schedules and backup catalogs.")]
    [String]
    $DeviceName
)

# Set Current directory path
$ScriptDirectory = (Get-Location).Path

#Set dll path
$ActiveDirectoryPath = Join-Path $ScriptDirectory "Dependencies\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
$ClientRuntimeAzurePath = Join-Path $ScriptDirectory "Dependencies\Microsoft.Rest.ClientRuntime.Azure.dll"
$ClientRuntimePath = Join-Path $ScriptDirectory "Dependencies\Microsoft.Rest.ClientRuntime.dll"
$NewtonsoftJsonPath = Join-Path $ScriptDirectory "Dependencies\Newtonsoft.Json.dll"
$AzureAuthenticationPath = Join-Path $ScriptDirectory "Dependencies\Microsoft.Rest.ClientRuntime.Azure.Authentication.dll"
$StorSimple8000SeresePath = Join-Path $ScriptDirectory "Dependencies\Microsoft.Azure.Management.Storsimple8000series.dll"

#Load all required assemblies
[System.Reflection.Assembly]::LoadFrom($ActiveDirectoryPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($ClientRuntimeAzurePath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($ClientRuntimePath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($NewtonsoftJsonPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($AzureAuthenticationPath) | Out-Null
[System.Reflection.Assembly]::LoadFrom($StorSimple8000SeresePath) | Out-Null

# Print methods
Function PrettyWriter($Content, $Color = "Yellow") { 
    Write-Host $Content -Foregroundcolor $Color 
}

# Define constant variables (DO NOT CHANGE BELOW VALUES)
$FrontdoorUrl = "urn:ietf:wg:oauth:2.0:oob"
$TokenUrl = "https://management.azure.com"
$TenantId = "1950a258-227b-4e31-a9cf-717495945fc2"
$DomainId = "72f988bf-86f1-41af-91ab-2d7cd011db47"

$FrontdoorUri = New-Object System.Uri -ArgumentList $FrontdoorUrl
$TokenUri = New-Object System.Uri -ArgumentList $TokenUrl

$AADClient = [Microsoft.Rest.Azure.Authentication.ActiveDirectoryClientSettings]::UsePromptOnly($TenantId, $FrontdoorUri)

# Set Synchronization context
$SyncContext = New-Object System.Threading.SynchronizationContext
[System.Threading.SynchronizationContext]::SetSynchronizationContext($SyncContext)

# Verify User Credentials
$Credentials = [Microsoft.Rest.Azure.Authentication.UserTokenProvider]::LoginWithPromptAsync($DomainId, $AADClient).GetAwaiter().GetResult()
$StorSimpleClient = New-Object Microsoft.Azure.Management.StorSimple8000Series.StorSimple8000SeriesManagementClient -ArgumentList $TokenUri, $Credentials

# Set SubscriptionId
$StorSimpleClient.SubscriptionId = $SubscriptionId

# Get all backup policies by Device
try {
    $policies = [Microsoft.Azure.Management.StorSimple8000Series.BackupPoliciesOperationsExtensions]::ListByDevice($StorSimpleClient.BackupPolicies, $DeviceName, $ResourceGroupName, $ManagerName)
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

# Filter enabled scheduled backup policies
$BackupPolicies = $policies | Where-Object { $_.ScheduledBackupStatus -eq 'Enabled'}

if ($policies -eq $null -or $policies.Count -eq 0) {
    Write-Error "No backup policy is configured."
    break
}elseIf ($BackupPolicies -eq $null) {
    Write-Error "Either all backup schedules are disabled or no backup schedule is configured."
    break
}

$Schedules = @()
$ExpectedBackups = @()
$WeeklyBufferTimeInMinutes = 1440
$DailyBufferTimeInMinutes = 1440
$HourlyBufferTimeInMinutes = 120
$MinutesBufferTimeInMinutes = 60

# Populate all expected backups set by current backup schedules
try {
    $BackupPolicies | ForEach-Object {
        # Policy Info
        $BackupPolicyName = $_.Name
        $BackupPolicyId = $_.Id
        $RetentionCount = $_.RetentionCount

        # Get all schedules in current Backup Policy
        $sch = [Microsoft.Azure.Management.StorSimple8000Series.BackupSchedulesOperationsExtensions]::ListByBackupPolicy($StorSimpleClient.BackupSchedules, $DeviceName, $BackupPolicyName, $ResourceGroupName, $ManagerName)
        
        # Filter disabled schedules & no last successful run (backups)
        $Schedules += $sch | Where-Object { $_.ScheduleStatus -eq 'Enabled' -and $_.LastSuccessfulRun -ne $null }
        
        $Schedules | ForEach-Object {
            $StartTime = $_.StartTime
            $RetentionCount = $_.RetentionCount
            $ExpectedScheduleTime = [datetime]$_.LastSuccessfulRun
            
            # Set Minutes/Seconds to Zero
            if ($ExpectedScheduleTime.Minute -gt 0) {
                $ExpectedScheduleTime = $ExpectedScheduleTime.AddMinutes(-$ExpectedScheduleTime.Minute)
            }
            if ($ExpectedScheduleTime.Second -gt 0) {
                $ExpectedScheduleTime = $ExpectedScheduleTime.AddSeconds(-$ExpectedScheduleTime.Second)
            }

            $_.ScheduleRecurrence | ForEach-Object {
                $RecurrenceType = $_.RecurrenceType
                $RecurrenceValue = $_.RecurrenceValue
                $WeeklyDaysList = $_.WeeklyDaysList
                $Index = 1

                while ($Index -le $RetentionCount -and $ExpectedScheduleTime -ge $StartTime) {
                    $ExpectedBackupObj = New-Object psobject -Property @{
                        Id = [guid]::NewGuid()
                        BackupPolicyName = $BackupPolicyName
                        BackupPolicyId = $BackupPolicyId
                        RecurrenceType = $RecurrenceType
                        ScheduleTime = $ExpectedScheduleTime
                        BufferTimeInMinutes = $null
                        BackupName = $null
                        ActualBackupTime = $null
                        SearchOrder = $null
                    }

                    # Read previous schedule(s)
                    if ($_.RecurrenceType -eq "Weekly") {
                        $WeekDayFound = $false
                        # Find previous backup by verifying WeekDaysList
                        do {
                            $ExpectedScheduleTime = $ExpectedScheduleTime.AddDays(-1)
                            $WeekDayFound = $WeeklyDaysList -contains $ExpectedScheduleTime.DayOfWeek
                        } while (!$WeekDayFound)

                        # Set Buffer time & search order
                        $ExpectedBackupObj.BufferTimeInMinutes = $WeeklyBufferTimeInMinutes
                        $ExpectedBackupObj.SearchOrder = 4
                    } elseIf ($_.RecurrenceType -eq "Daily") {
                        # Set previous schedule time by RecurrenceValue
                        $ExpectedScheduleTime = $ExpectedScheduleTime.AddDays(-$RecurrenceValue)

                        # Set Buffer time & search order
                        $ExpectedBackupObj.BufferTimeInMinutes = $DailyBufferTimeInMinutes
                        $ExpectedBackupObj.SearchOrder = 3
                    } elseIf ($_.RecurrenceType -eq "Hourly") {
                        # Set previous schedule time by RecurrenceValue
                        $ExpectedScheduleTime = $ExpectedScheduleTime.AddHours(-$RecurrenceValue)

                        # Set Buffer time & search order
                        $ExpectedBackupObj.BufferTimeInMinutes = $HourlyBufferTimeInMinutes
                        $ExpectedBackupObj.SearchOrder = 2
                    } elseIf($_.RecurrenceType -eq "Minutes") {
                        # Set previous schedule time by RecurrenceValue
                        $ExpectedScheduleTime = $ExpectedScheduleTime.AddMinutes(-$RecurrenceValue)

                        # Set Buffer time & search order
                        $ExpectedBackupObj.BufferTimeInMinutes = $MinutesBufferTimeInMinutes
                        $ExpectedBackupObj.SearchOrder = 1
                    }

                    # Add expected schedule info
                    $ExpectedBackups += $ExpectedBackupObj
                    $Index++
                }
            }
        }
    }
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

if ($ExpectedBackups -eq $null -or $ExpectedBackups.Length -eq 0) {
    Write-Error "No successfully backup(s) available for scheduled backup policy."
    break
}

# Get all currently available backup catalogs
try {
    $ActualBackups = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::ListByDevice($StorSimpleClient.Backups, $DeviceName, $ResourceGroupName, $ManagerName)
    
    $SnapshotType = 'BySchedule'
    $MinimumDate = ($ExpectedBackups | sort ScheduleTime)[0].ScheduleTime
    $MaximumDate = ($ExpectedBackups | sort ScheduleTime -Descending)[0].ScheduleTime
    
    # Filter data by BackupJobCreationType and date range
    $ActualBackups = $ActualBackups | Where-Object { $_.BackupJobCreationType -eq $SnapshotType -and $_.CreatedOn -gt $MinimumDate -and $_.CreatedOn -lt $MaximumDate} 
    
    # Add IsTagged member
    $ActualBackups | ForEach-Object { $_ | Add-Member –MemberType NoteProperty –Name IsTagged –Value $false }
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

# Compare Expected & Actual backups and Tag matched objects
for ($LoopIndex=0; $LoopIndex -lt $ExpectedBackups.Length; $LoopIndex++) {
    $ExpectedBackupObj = $ExpectedBackups[$LoopIndex]
    $Backup = ($ActualBackups | Where-Object {$_.IsTagged -eq $false -and $_.CreatedOn -gt $ExpectedBackupObj.ScheduleTime -and $_.CreatedOn -lt $ExpectedBackupObj.ScheduleTime.AddMinutes($ExpectedBackupObj.BufferTimeInMinutes)} | sort CreatedOn)

    if ($Backup -ne $null -and $Backup.Length -gt 0) {
        # Set IsTagged property
        ($ActualBackups | Where-Object {$_.IsTagged -eq $false -and $_.CreatedOn -gt $ExpectedBackupObj.ScheduleTime -and $_.CreatedOn -lt $ExpectedBackupObj.ScheduleTime.AddMinutes($ExpectedBackupObj.BufferTimeInMinutes)} | sort CreatedOn)[0].IsTagged = $true

        # Set Actual BackupName & CreatedOn
        ($ExpectedBackups | where Id -eq $ExpectedBackupObj.Id)| ForEach-Object { $_.BackupName = $Backup[0].Name; $_.ActualBackupTime = $Backup[0].CreatedOn }
    }
}

# Display summery info
$AvailableBacksupsCount = [int]([object[]]($ExpectedBackups | where BackupName -ne $null)).Length
$MissedBacksupsCount = [int]([object[]]($ExpectedBackups | where BackupName -eq $null)).Length

$AvailableBacksupsCount = @{$true=0;$false=$AvailableBacksupsCount}[$AvailableBacksupsCount -eq 0]
$MissedBacksupsCount = @{$true=0;$false=$MissedBacksupsCount}[$MissedBacksupsCount -eq 0]

if ($MissedBacksupsCount -gt 0) {
    PrettyWriter "`nMissed backups details by RecurrenceType"
    ($ExpectedBackups | where BackupName -eq $null | Sort RecurrenceType | Format-Table BackupPolicyName,RecurrenceType,ScheduleTime -GroupBy RecurrenceType)
}

## Uncomment during dubeg time
#PrettyWriter "`nExpected backups:"
#($ExpectedBackups | Sort-Object ScheduleTime | Format-Table BackupPolicyName, RecurrenceType, ScheduleTime, ActualBackupTime, BackupName -GroupBy {ScheduleTime.ToString("yyyy-MM-dd")})

## Uncomment during dubeg time
#PrettyWriter "`nActual backups:"
#$ActualBackups | group IsTagged -NoElement
#$ActualBackups | sort CreatedOn | Format-Table Name,CreatedOn,IsTagged #-GroupBy CreatedOn

PrettyWriter "`nSummary info:"
Write-Output "Total expected backups: $($ExpectedBackups.Length)"
Write-Output "Total available backups: $($AvailableBacksupsCount)"
Write-Output "Total missed backups: $($MissedBacksupsCount)`n"


$BackupsCount = ([object[]]$ActualBackups).Count
$MaxBackupsCount = 100
if ($ActualBackups.NextPageLink -or $BackupsCount -eq $MaxBackupsCount) {
    PrettyWriter "`n`n Note:"
    Write-Output "Compared only latest $($MaxBackupsCount) actual backups. `nRequire to read all backups to accomplish the verification."
}