<#
.DESCRIPTION
    This scipt reads all expected backup schedules and verifies with available backup catalogs, then displays all missed backup list.
     
.PARAMS 

    SubscriptionId: Specifies the ID of the subscription.
    TenantId: Tenant Id for the subscription. Available from the Get-AzureRMSubscription PowerShell cmdlet.
    DeviceName: Specifies the name of the StorSimple device on which to create/update the volume.
    ResourceGroupName: Specifies the name of the resource group on which to create/update the volume.
    ManagerName: Specifies the name of the resource (StorSimple device manager) on which to create/update the volume.

#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Specifies the ID of the subscription.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the StorSimple device on which to read backup schedules and backup catalogs.")]
    [String]
    $DeviceName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource group on which to read backup schedules and backup catalogs.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource (StorSimple device manager) on which to read backup schedules and backup catalogs.")]
    [String]
    $ManagerName
)

#Load all required assemblies
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\packages\Microsoft.IdentityModel.Clients.ActiveDirectory.2.28.3\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Microsoft.Rest.ClientRuntime.Azure.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Microsoft.Rest.ClientRuntime.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Newtonsoft.Json.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\packages\Microsoft.Rest.ClientRuntime.Azure.Authentication.2.2.9-preview\lib\net45\Microsoft.Rest.ClientRuntime.Azure.Authentication.dll")
$Assembly = [System.Reflection.Assembly]::LoadFrom("E:\WorkFolders\StorSimple\AzureRM\AzureRM.StorSimpleCmdlets\AzureRM.StorSimpleCmdlets\Dependencies\Microsoft.Azure.Management.Storsimple8000series.dll")

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

try {
    $policies = [Microsoft.Azure.Management.StorSimple8000Series.BackupPoliciesOperationsExtensions]::ListByDevice($StorSimpleClient.BackupPolicies, $DeviceName, $ResourceGroupName, $ManagerName)
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

# Remove disabled scheduled backup policies
$BackupPolicies = $policies | Where-Object { $_.ScheduledBackupStatus -eq 'Enabled'}

if ($policies -eq $null) {
    #Write-Error "Could not find active backup policies."
    Write-Error "Backup policy is either disabled or not configured."
    break
}elseIf ($BackupPolicies -eq $null) {
    Write-Error "Backup schedule is either disabled or not configured."
    break
}


$Schedules = @()
$ExpectedBackups = @()
try {
    $BackupPolicies | ForEach-Object {
        # Policy Info
        $BackupPolicyName = $_.Name
        $BackupPolicyId = $_.Id
        $RetentionCount = $_.RetentionCount

        # Call Schedule Info by Policy name
        $sch = [Microsoft.Azure.Management.StorSimple8000Series.BackupSchedulesOperationsExtensions]::ListByBackupPolicy($StorSimpleClient.BackupSchedules, $DeviceName, $BackupPolicyName, $ResourceGroupName, $ManagerName)
        
        # Filter disabled schedules & no successful run (backups)
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
                    $BackupsExpectedObj = New-Object psobject -Property @{
                        Id = [guid]::NewGuid()
                        BackupPolicyName = $BackupPolicyName
                        BackupPolicyId = $BackupPolicyId
                        RecurrenceType = $_.RecurrenceType
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
                        $BackupsExpectedObj.BufferTimeInMinutes = 1440
                        $BackupsExpectedObj.SearchOrder = 4
                    } elseIf ($_.RecurrenceType -eq "Daily") {
                        # Set previous schedule time by RecurrenceValue
                        $ExpectedScheduleTime = $ExpectedScheduleTime.AddDays(-$RecurrenceValue)

                        # Set Buffer time & search order
                        $BackupsExpectedObj.BufferTimeInMinutes = 1440
                        $BackupsExpectedObj.SearchOrder = 3
                    } elseIf ($_.RecurrenceType -eq "Hourly") {
                        # Set previous schedule time by RecurrenceValue
                        $ExpectedScheduleTime = $ExpectedScheduleTime.AddHours(-$RecurrenceValue)

                        # Set Buffer time & search order
                        $BackupsExpectedObj.BufferTimeInMinutes = 120
                        $BackupsExpectedObj.SearchOrder = 2
                    } elseIf($_.RecurrenceType -eq "Minutes") {
                        # Set previous schedule time by RecurrenceValue
                        $ExpectedScheduleTime = $ExpectedScheduleTime.AddMinutes(-$RecurrenceValue)

                        # Set Buffer time & search order
                        $BackupsExpectedObj.BufferTimeInMinutes = 60
                        $BackupsExpectedObj.SearchOrder = 1
                    }

                    # Add expected schedule info
                    $ExpectedBackups += $BackupsExpectedObj
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

try {
    # Read all Backups info
    $ActualBackups = [Microsoft.Azure.Management.StorSimple8000Series.BackupsOperationsExtensions]::ListByDevice($StorSimpleClient.Backups, $DeviceName, $ResourceGroupName, $ManagerName)
    
    $SnapshotType = 'BySchedule'
    $MinimumDate = ($ExpectedBackups | sort ScheduleTime)[0].ScheduleTime
    $MaximumDate = ($ExpectedBackups | sort ScheduleTime -Descending)[0].ScheduleTime
    
    # Filter data by BackupJobCreationType option
    $ActualBackups = $ActualBackups | Where-Object { $_.BackupJobCreationType -eq $SnapshotType -and $_.CreatedOn -gt $MinimumDate -and $_.CreatedOn -lt $MaximumDate} 
    
    # Add IsTracked member
    $ActualBackups | ForEach-Object { $_ | Add-Member –MemberType NoteProperty –Name IsTagged –Value $false }
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

for ($LoopIndex=0; $LoopIndex -lt $ExpectedBackups.Length; $LoopIndex++) {
    $BackupExpectedObj = $ExpectedBackups[$LoopIndex]
    $Backup = ($ActualBackups | Where-Object {$_.IsTagged -eq $false -and $_.CreatedOn -gt $BackupExpectedObj.ScheduleTime -and $_.CreatedOn -lt $BackupExpectedObj.ScheduleTime.AddMinutes($BackupExpectedObj.BufferTimeInMinutes)} | sort CreatedOn)

    if ($Backup -ne $null -and $Backup.Length -gt 0) {
        # Set IsTrack property
        ($ActualBackups | Where-Object {$_.IsTagged -eq $false -and $_.CreatedOn -gt $BackupExpectedObj.ScheduleTime -and $_.CreatedOn -lt $BackupExpectedObj.ScheduleTime.AddMinutes($BackupExpectedObj.BufferTimeInMinutes)} | sort CreatedOn)[0].IsTagged = $true

        # Set BackupName & CreatedOn
        ($ExpectedBackups | where Id -eq $BackupExpectedObj.Id)| ForEach-Object { $_.BackupName = $Backup[0].Name; $_.ActualBackupTime = $Backup[0].CreatedOn }
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

## Useful at testing purpose
#PrettyWriter "`n`Expected backups:"
#($ExpectedBackups | Sort-Object ScheduleTime | Format-Table BackupPolicyName, RecurrenceType, ScheduleTime, ActualBackupTime, BackupName -GroupBy {ScheduleTime.ToString("yyyy-MM-dd")})

## Useful at testing purpose
#PrettyWriter "Actual backups:"
#$ActualBackups | group IsTagged -NoElement
#$ActualBackups | sort CreatedOn | Format-Table Name,CreatedOn,IsTagged #-GroupBy CreatedOn

PrettyWriter "`nSummary info:"
Write-Output "Total expected backups: $($ExpectedBackups.Length)"
Write-Output "Total available backups: $($AvailableBacksupsCount)"
Write-Output "Total missed backups: $($MissedBacksupsCount)`n"
