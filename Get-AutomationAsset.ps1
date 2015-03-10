<#
.SYNOPSIS 
    This runbook takes in an Automation asset name and type, and outputs the asset’s value in serialized form. It is meant
    to be used as part of the Azure Automation Authoring Toolkit (http://aka.ms/azureautomationauthoringtoolkit)
    
DESCRIPTION
    Internally, each of the Get-Automation* activities in the Azure Automation Authoring Toolkit can retrieve real asset
    values by kicking off the Get-AutomationAsset runbook. This runbook takes in an asset name and type, and outputs the asset’s
    value in serialized form. The Get-Automation* activities then read in this output and deserialize it back into a value,
    giving you access to the values of Azure Automation assets in your PowerShell ISE runbooks.

    WARNING: The fact that this runbook outputs the serialized values of Azure Automation assets, combined with the fact that this
    output is in plain text, means that when this runbook runs it is possible for someone with access to Azure Automation job output
    to see the values of “secret” Azure Automation assets, whether they be credentials, encrypted variables, or encrypted connection
    fields, in the output of Get-AutomationAsset’s jobs. For this reason, runbooks written that leverage the
    Azure Automation Authoring Toolkit to work in the PowerShell ISE should only be used to grab non-encrypted assets, or
    encrypted “test” Azure Automation assets (those that only provide access to “test” systems or contain “fake” secret information).

.PARAMETER Name
    The name of the asset to output the value of.

.PARAMETER Type
    The type of the asset to output the value of.

.EXAMPLE
    Get-AutomationAsset -Name "ServerName" -Type "Variable"

.NOTES
    AUTHOR: Joe Levy
    LASTEDIT: Feb 22, 2015 
#>
workflow Get-AutomationAsset {
    param(
        [Parameter(Mandatory=$True)]
        [ValidateSet('Variable','Certificate','PSCredential', 'Connection')]
        [string] $Type,

        [Parameter(Mandatory=$True)]
        [string] $Name
    )

    $Val = $Null

    # Get asset
    if($Type -eq "Variable") {
        $Val = Get-AutomationVariable -Name $Name
    }
    elseif($Type -eq "Certificate") {
        $Val = Get-AutomationCertificate -Name $Name
    }
    elseif($Type -eq "Connection") {
        $Val = Get-AutomationConnection -Name $Name
    }
    elseif($Type -eq "PSCredential") {
        $Temp = Get-AutomationPSCredential -Name $Name

        if($Temp) {
            $Val = @{
                "Username" = $Temp.Username;
                "Password" = $Temp.GetNetworkCredential().Password
            }
        }
    }

    if(!$Val) {
        throw "Automation asset '$Name' of type $Type does not exist in Azure Automation"
    }
    else {
        # Serialize asset value as xml and then return it
        $SerializedOutput = [System.Management.Automation.PSSerializer]::Serialize($Val)

        Write-Output $SerializedOutput
    }
}