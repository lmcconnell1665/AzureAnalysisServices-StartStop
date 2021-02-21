<#
    .DESCRIPTION
        A powershell runbook to start an azure analysis services model

    .NOTES
        AUTHOR: Luke McConnell
        LASTEDIT: Feb 21, 2021
#>

$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Connect-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 

    "Getting analysis services models..."
    $mcconnellanalysisservices = Get-AzAnalysisServicesServer `
		-Name "mcconnell" `
        -ResourceGroupName "Analysis-Services"

    "Check to see if its paused, and resume if so"
    "if ($mcconnellanalysisservices.State -eq "Paused")
    {
        Write-Output "Starting Analysis Services model..."

        Resume-AzAnalysisServicesServer `
		    -Name "mcconnell" `
            -ResourceGroupName "Analysis-Services"
    }
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
