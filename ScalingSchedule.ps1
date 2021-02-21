<# This script came from: https://jorgklein.com/2017/10/11/azure-analysis-services-scheduled-autoscaling/

Can be used to automate scaling of resources and pausing/resuming on a schedule

#>

param(
[parameter(Mandatory=$false)]
[string] $environmentName = "AzureCloud",
 
[parameter(Mandatory=$true)]
[string] $resourceGroupName,
 
[parameter(Mandatory=$false)]
[string] $azureRunAsConnectionName = "AzureRunAsConnection",
 
[parameter(Mandatory=$true)]
[string] $serverName,
 
[parameter(Mandatory=$true)]
[string] $scalingSchedule,
 
[parameter(Mandatory=$false)]
[string] $scalingScheduleTimeZone = "W. Europe Standard Time"
)
 
filter timestamp {"[$(Get-Date -Format G)]: $_"}
 
Write-Output "Script started." | timestamp
 
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"
 
#Authenticate with Azure Automation Run As account (service principal)
$runAsConnectionProfile = Get-AutomationConnection -Name $azureRunAsConnectionName
$environment = Get-AzureRmEnvironment -Name $environmentName
Add-AzureRmAccount -Environment $environment -ServicePrincipal `
-TenantId $runAsConnectionProfile.TenantId `
-ApplicationId $runAsConnectionProfile.ApplicationId `
-CertificateThumbprint ` $runAsConnectionProfile.CertificateThumbprint | Out-Null
Write-Output "Authenticated with Automation Run As Account." | timestamp
 
#Get current date/time and convert to $scalingScheduleTimeZone
$stateConfig = $scalingSchedule | ConvertFrom-Json
$startTime = Get-Date
Write-Output "Azure Automation local time: $startTime." | timestamp
$toTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($scalingScheduleTimeZone)
Write-Output "Time zone to convert to: $toTimeZone." | timestamp
$newTime = [System.TimeZoneInfo]::ConvertTime($startTime, $toTimeZone)
Write-Output "Converted time: $newTime." | timestamp
$startTime = $newTime
 
#Get current day of week based on converted start time
$currentDayOfWeek = [Int]($startTime).DayOfWeek
Write-Output "Current day of week: $currentDayOfWeek." | timestamp
 
# Get the scaling schedule for the current day of week
$dayObjects = $stateConfig | Where-Object {$_.WeekDays -contains $currentDayOfWeek } `
|Select-Object Sku, `
@{Name="StartTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+”:”+$_.StartTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}}, `
@{Name="StopTime"; Expression = {[datetime]::ParseExact(($startTime.ToString("yyyy:MM:dd")+”:”+$_.StopTime),"yyyy:MM:dd:HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)}}
 
# Get the server object
$asSrv = Get-AzureRmAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName
Write-Output "AAS server name: $($asSrv.Name)" | timestamp
Write-Output "Current server status: $($asSrv.State), sku: $($asSrv.Sku.Name)" | timestamp
 
if($dayObjects -ne $null) { # Scaling schedule found for this day
    # Get the scaling schedule for the current time. If there is more than one available, pick the first
    $matchingObject = $dayObjects | Where-Object { ($startTime -ge $_.StartTime) -and ($startTime -lt $_.StopTime) } | Select-Object -First 1
    if($matchingObject -ne $null)
    {
        Write-Output "Scaling schedule found. Check if server is paused and if current sku is matching..." | timestamp
        if($asSrv.State -eq "Paused")
        {
            Write-Output "Server was paused. Resuming!" | timestamp
            $asSrv | Resume-AzureRmAnalysisServicesServer
            Write-Output "Server resumed." | timestamp
        }
        if($asSrv.Sku.Name -ne $matchingObject.Sku)
        {
            Write-Output "Server is not in the sku of the scaling schedule. Changing!" | timestamp
            $asSrv = Set-AzureRmAnalysisServicesServer -Name $asSrv.Name -ResourceGroupName $resourceGroupName -Sku $matchingObject.Sku
            Write-Output "Change to edition/tier as specified in scaling schedule initiated..." | timestamp
            $asSrv = Get-AzureRmAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName
            Write-Output "Current server state: $($asSrv.State), sku: $($asSrv.Sku.Name)" | timestamp
        }
        else
        {
            Write-Output "Current server sku matches the scaling schedule already. Exiting..." | timestamp
        }
    }
    else { # Scaling schedule not found for current time
        Write-Output "No matching scaling schedule time slot for this time found. Check if the server is paused..." | timestamp
        if($asSrv.State -ne "Paused")
        {
            Write-Output "Server not paused. Pausing!" | timestamp
            $asSrv | Suspend-AzureRmAnalysisServicesServer
            Write-Output "Server paused." | timestamp
            $asSrv = Get-AzureRmAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName
            Write-Output "Current server sate: $($asSrv.State), sku: $($asSrv.Sku.Name)" | timestamp
        }
        else
        {
            Write-Output "Server paused already. Exiting..." | timestamp
        }
    }
}
else # Scaling schedule not found for this day
{
    Write-Output "No matching scaling schedule for this day found.  Check if the server is paused..." | timestamp
    if($asSrv.State -ne "Paused")
    {
        Write-Output "Server not paused. Pausing!" | timestamp
        $asSrv | Suspend-AzureRmAnalysisServicesServer
        Write-Output "Server paused." | timestamp
        $asSrv = Get-AzureRmAnalysisServicesServer -ResourceGroupName $resourceGroupName -Name $serverName
        Write-Output "Current server state: $($asSrv.State), sku: $($asSrv.Sku.Name)" | timestamp
    }
    else
    {
        Write-Output "Server paused already. Exiting..." | timestamp
    }
}  
 
Write-Output "Script finished." | timestamp
