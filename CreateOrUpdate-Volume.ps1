<#
.DESCRIPTION
    This script creates/updates StorSimple volume
     
.PARAMS 

    SubscriptionId: Specifies the ID of the subscription.
    DeviceName: Specifies the name of the StorSimple device on which to create/update the volume.
    ResourceGroupName: Specifies the name of the resource group on which to create/update the volume.
    ManagerName: Specifies the name of the resource (StorSimple device manager) on which to create/update the volume.
    VolumeContainerName: Specifies the volume container name on which to create/update the volume.
    VolumeName: Specifies a name of the new/existing volume.
    VolumeType (Optional): Specifies whether to create/update a tiered, archival, locallypinned volume. Valid values are: Tiered or Archival or LocallyPinned. (Default is Tiered)
    VolumeSizeInBytes: Specifies the volume size in bytes. The volume size must be between 1GB to 64TB.
    ConnectedHostName (Optional): Specifies a access control record to associate with the volume. (Default is no ACR)
    EnableMonitoring (Optional): Specifies whether to enable monitoring for the volume. (Default is Disabled)
#>

Param
(
    [parameter(Mandatory = $true, HelpMessage = "Specifies the ID of the subscription.")]
    [String]
    $SubscriptionId,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource group on which to create/update the volume.")]
    [String]
    $ResourceGroupName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the resource (StorSimple device manager) on which to create/update the volume.")]
    [String]
    $ManagerName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the name of the StorSimple device on which to create/update the volume.")]
    [String]
    $DeviceName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the container name on which to create/update the volume.")]
    [String]
    $VolumeContainerName,

    [parameter(Mandatory = $true, HelpMessage = "Specifies a name for the new/existing volume.")]
    [String]
    $VolumeName,

    [parameter(Mandatory = $false, HelpMessage = "Specifies a type of volume. Valid values are: Tiered or LocallyPinned. Optional, default is Tiered")]
    [ValidateSet('Tiered', 'Archival', 'LocallyPinned')]
    [String]
    $VolumeType,

    [parameter(Mandatory = $true, HelpMessage = "Specifies the volume size in bytes. The volume size must be between 1GB to 64TB.")]
    [Int64]
    $VolumeSizeInBytes,

    [parameter(Mandatory = $false, HelpMessage = "Specifies a access control record (ACR) to associate with the volume. Optional, default is no ACR")]
    [String]
    $ConnectedHostName,

    [parameter(Mandatory = $false, HelpMessage = "Specifies whether to enable monitoring for the volume. Optional, default is false")]
    [ValidateSet("true", "false", "1", "0")]
    [string]
    $EnableMonitoring
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

#Valiate volume size
$MinimumVolumeSize = 1000000000 # 1GB
$MaximumVolumeSize = (1000000000000 * 64) # 64TB
if (!($VolumeSizeInBytes -ge $MinimumVolumeSize -and $VolumeSizeInBytes -le $MaximumVolumeSize)) {
    Write-Error "The volume size (in bytes) must be between 1GB to 64TB."
    break
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

# Get Access control record id
$AccessControlRecordIds = New-Object "System.Collections.Generic.List[String]"
if ($ConnectedHostName -ne $null -and $ConnectedHostName.Length -gt 0) {
    try {
        $acr = [Microsoft.Azure.Management.StorSimple8000Series.AccessControlRecordsOperationsExtensions]::Get($StorSimpleClient.AccessControlRecords, $ConnectedHostName, $ResourceGroupName, $ManagerName)

        if ($acr -eq $null) {
            Write-Error "Could not find an access control record with given name $($ConnectedHostName)."
            break
        }
    }
    catch {
        # Print error details
        Write-Error $_.Exception.Message
        break
    }

    $AccessControlRecordIds.Add($acr.Id)
}

# Set Monitoring status
$MonitoringStatus = [Microsoft.Azure.Management.StorSimple8000Series.Models.MonitoringStatus]::Disabled
if ([string]$EnableMonitoring -eq "true" -or $EnableMonitoring -eq 1) {
    $MonitoringStatus = [Microsoft.Azure.Management.StorSimple8000Series.Models.MonitoringStatus]::Enabled
}

# Set VolumeAppType
$VolumeAppType = $VolumeAppType = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeType]::Tiered
if ($VolumeType -eq "LocallyPinned") {
    $VolumeAppType = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeType]::LocallyPinned
} elseif ($VolumeType -eq "Archival") {
    $VolumeAppType = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeType]::Archival
}

# Set Volume properties
$VolumeProperties = New-Object Microsoft.Azure.Management.StorSimple8000Series.Models.Volume
$VolumeProperties.SizeInBytes = $VolumeSizeInBytes
$VolumeProperties.VolumeType = $VolumeAppType
$VolumeProperties.VolumeStatus = [Microsoft.Azure.Management.StorSimple8000Series.Models.VolumeStatus]::Online
$VolumeProperties.MonitoringStatus = $MonitoringStatus
$VolumeProperties.AccessControlRecordIds = $AccessControlRecordIds

try {
    $Volume = [Microsoft.Azure.Management.StorSimple8000Series.VolumesOperationsExtensions]::CreateOrUpdate($StorSimpleClient.Volumes, $DeviceName, $VolumeContainerName, $VolumeName, $VolumeProperties, $ResourceGroupName, $ManagerName)
}
catch {
    # Print error details
    Write-Error $_.Exception.Message
    break
}

# Print success message
PrettyWriter "Volume ($($VolumeName)) successfully created/updated.`n"
