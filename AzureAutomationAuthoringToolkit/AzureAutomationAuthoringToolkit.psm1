<#
    Learn more here: http://aka.ms/azureautomationauthoringtoolkit
#>

<#
    .SYNOPSIS
        Get a credential asset from Azure Automation.
        Part of the Azure Automation Authoring Toolkit to help author runbooks locally.
#>
workflow Get-AutomationPSCredential {
   [CmdletBinding(HelpUri='http://aka.ms/azureautomationauthoringtoolkit')]
   [OutputType([PSCredential])]

    param(
        [Parameter(Mandatory=$True)]
        [string] $Name
    )

    Write-Verbose "AzureAutomationAuthoringToolkit: Looking for static credential asset with name '$Name'"

    $AssetValue = Get-AzureAutomationAuthoringToolkitStaticAsset -Type PSCredential -Name $Name
    
    if(!$AssetValue) {   
        Write-Verbose "AzureAutomationAuthoringToolkit: Static credential asset named '$Name' not found, 
        attempting to use Get-AutomationAsset runbook to grab its value."

        $Configuration = Get-AzureAutomationAuthoringToolkitConfiguration
        $AccountName = $Configuration.AutomationAccountName

        if($Configuration.AllowGrabSecrets) {
            $AssetValue = Get-AzureAutomationAuthoringToolkitAsset -Type PSCredential -Name $Name
        }
        else {
            throw "AzureAutomationAuthoringToolkit: Cannot grab value of credential asset '$Name.' Config.json 
            has AllowGrabSecrets set to false. If you want to allow AzureAutomationAuthoringToolkit to grab secrets from Automation 
            Account '$AccountName,' set AllowGrabSecrets to true. Please note this will cause the value of the asset to be displayed 
            in plain text in an Azure Automation job's output. For this reason, it is recommended to only set AllowGrabSecrets to true 
            when working against a 'test' automation account that does not contain production secrets." 
        }
    }

    if($AssetValue) {
        Write-Verbose "AzureAutomationAuthoringToolkit: Converting '$Name' asset value to a proper PSCredential"
        
        $SecurePassword = $AssetValue.Password | ConvertTo-SecureString -AsPlainText -Force
        $Cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AssetValue.Username, $SecurePassword

        Write-Output $Cred
    }
}