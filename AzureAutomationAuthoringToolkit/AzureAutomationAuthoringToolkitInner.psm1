<#
    Learn more here: http://aka.ms/azureautomationauthoringtoolkit
#>

$script:ConfigurationPath = "$PSScriptRoot\Config.json"
$script:StaticAssetsPath = "$PSScriptRoot\StaticAssets.json"

$global:AssetCache = @{}

<#
    .SYNOPSIS
        Get a local certificate based on its thumbprint, as part of the Azure Automation Authoring Toolkit.
        Not meant to be called directly.
#>
function Get-AzureAutomationAuthoringToolkitLocalCertificate {
    param(
        [Parameter(Mandatory=$True)]
        [string] $Name,
        
        [Parameter(Mandatory=$True)]
        [string] $Thumbprint
    )
    
    Write-Verbose "AzureAutomationAuthoringToolkit: Looking for local certificate with thumbprint '$Thumbprint'"
            
    try {
        $Certificate = Get-Item ("Cert:\CurrentUser\My\" + $Thumbprint) -ErrorAction Stop
        Write-Output $Certificate
    }
    catch {
        Write-Error "AzureAutomationAuthoringToolkit: Certificate asset '$Name' referenced certificate with thumbprint 
        '$Thumbprint' but no certificate with that thumbprint exist on the local system."
                
        throw $_
    }
}

<#
    .SYNOPSIS
        Get static assets defined for the Azure Automation Authoring Toolkit. Not meant to be called directly.
#>
function Get-AzureAutomationAuthoringToolkitStaticAsset {
    param(
        [Parameter(Mandatory=$True)]
        [ValidateSet('Variable', 'Certificate', 'PSCredential', 'Connection')]
        [string] $Type,

        [Parameter(Mandatory=$True)]
        [string]$Name
    )

    $Configuration = Get-AzureAutomationAuthoringToolkitConfiguration

    if($Configuration.StaticAssetsPath -eq "default") {
        Write-Verbose "Grabbing static assets from default location '$script:StaticAssetsPath'"
    }
    else {
        $script:StaticAssetsPath = $Configuration.StaticAssetsPath
        Write-Verbose "Grabbing static assets from user-specified location '$script:StaticAssetsPath'"
    }
    
    $StaticAssetsError = "AzureAutomationAuthoringToolkit: AzureAutomationAuthoringToolkit static assets defined in 
    '$script:StaticAssetsPath' is incorrect. Make sure the file exists, and it contains valid JSON."
    
    Write-Verbose "AzureAutomationAuthoringToolkit: Looking for static value for $Type asset '$Name.'"
      
    try {
        $StaticAssets = Get-Content $script:StaticAssetsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error $StaticAssetsError
        throw $_
    }

    $AssetValue = $StaticAssets.$Type.$Name

    if($AssetValue) {
        Write-Verbose "AzureAutomationAuthoringToolkit: Found static value for $Type asset '$Name.'"

        if($Type -eq "Certificate") {
            $AssetValue = Get-AzureAutomationAuthoringToolkitLocalCertificate -Name $Name -Thumbprint $AssetValue.Thumbprint
        }
    }
    else {
        Write-Verbose "AzureAutomationAuthoringToolkit: Static value for $Type asset '$Name' not found."
    }

    Write-Output $AssetValue
}

<#
    .SYNOPSIS
        Get the configuration for the Azure Automation Authoring Toolkit. Not meant to be called directly.
#>
function Get-AzureAutomationAuthoringToolkitConfiguration {       
    $ConfigurationError = "AzureAutomationAuthoringToolkit: AzureAutomationAuthoringToolkit configuration defined in 
    '$script:ConfigurationPath' is incorrect. Make sure the file exists, contains valid JSON, and contains 'AutomationAccountName,' 
    'StaticAssetsPath,' 'SecretsCacheTimeInMinutes', and 'AllowGrabSecrets' fields."

    Write-Verbose "AzureAutomationAuthoringToolkit: Grabbing AzureAutomationAuthoringToolkit configuration."

    try {
        $Configuration = Get-Content $script:ConfigurationPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Error $ConfigurationError
        throw $_
    }

    if(!($Configuration.AutomationAccountName -and $Configuration.StaticAssetsPath -and $Configuration.AllowGrabSecrets -ne $Null -and $Configuration.SecretsCacheTimeInMinutes -ne $Null)) {
        throw $ConfigurationError
    }

    Write-Output $Configuration
}

<#
    .SYNOPSIS
        Test if the Azure Automation Authoring Toolkit can talk to the proper Azure Automation account.
        Not meant to be called directly.
#>
function Test-AzureAutomationAuthoringToolkitAzureConnection {
    $Configuration = Get-AzureAutomationAuthoringToolkitConfiguration
    $AccountName = $Configuration.AutomationAccountName

    Write-Verbose "AzureAutomationAuthoringToolkit: Testing AzureAutomationAuthoringToolkit ability to connect to Azure."

    try {
        Get-AzureAutomationAccount -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "AzureAutomationAuthoringToolkit: AzureAutomationAuthoringToolkit could not connect to Azure.
        Make sure the Azure PowerShell module is installed and a connection from the Azure 
        PowerShell module to Azure has been set up with either Import-AzurePublishSettingsFile, 
        Set-AzureSubscription, or Add-AzureAccount. For more info see: http://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/#Connect"

        throw $_
    }
    
    try {
        Get-AzureAutomationAccount -Name $AccountName -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "AzureAutomationAuthoringToolkit: AzureAutomationAuthoringToolkit could not find the Azure 
        Automation account '$AccountName'. Make sure it exists in Azure Automation for the current subscription. If you 
        intended to use a different Azure Automation account, update the 'AutomationAccountName' field in $script:ConfigurationPath"

        throw $_
    }
    
    Write-Verbose "AzureAutomationAuthoringToolkit: AzureAutomationAuthoringToolkit was able to connect to Azure 
    and Automation account '$AccountName.'"  
}

<#
    .SYNOPSIS
        Get an asset from Azure Automation for the Azure Automation Authoring Toolkit. Not meant to be called directly.
#>
function Get-AzureAutomationAuthoringToolkitAsset {
    param(
        [Parameter(Mandatory=$True)]
        [ValidateSet('Variable', 'Certificate', 'PSCredential', 'Connection')]
        [string] $Type,

        [Parameter(Mandatory=$True)]
        [string]$Name
    )

    $MaxSecondsToWaitOnJobCompletion = 600
    $SleepTime = 5
    $DoneJobStatuses = @("Completed", "Failed", "Stopped", "Blocked", "Suspended")

    $Configuration = Get-AzureAutomationAuthoringToolkitConfiguration

    # Check if we already have looked up this asset and have it in the cache
    $CachedAsset = $global:AssetCache["$Type$Name"]
    $CachedValue = $Null

    if($CachedAsset) {
        Write-Verbose "AzureAutomationAuthoringToolkit: Found cached value of $Type asset '$Name'"
        
        $CachedUntil = Get-Date $CachedAsset.CachedUntil
        $Now = Get-Date

        if($Now -gt $CachedUntil) {
            Write-Verbose "AzureAutomationAuthoringToolkit: Cached value of $Type asset '$Name' expired at $CachedUntil. Ignoring cached value."
        }
        else {
            $CachedValue = $CachedAsset.Value
        }
    }


    if($CachedValue) {
        Write-Verbose "AzureAutomationAuthoringToolkit: Returning cached value of $Type asset '$Name'"
        Write-Output $CachedValue
    }
    else {
        $AccountName = $Configuration.AutomationAccountName

        # Call Get-AutomationAsset runbook in Azure Automation to get the asset value in serialized form
        $Params = @{
            "Type" = $Type;
            "Name" = $Name
        }

        Test-AzureAutomationAuthoringToolkitAzureConnection

        Write-Verbose "AzureAutomationAuthoringToolkit: Starting Get-AutomationAsset runbook in Automation Account '$AccountName' 
        to get value of $Type asset '$Name' for this Automation Account"

        $Job = Start-AzureAutomationRunbook -Name "Get-AutomationAsset" -Parameters $Params -AutomationAccountName $AccountName

        if(!$Job) {
            throw "AzureAutomationAuthoringToolkit: Unable to start the 'Get-AutomationAsset' runbook. Make sure it exists and is published in Azure Automation."
        }
        else {
            Write-Verbose "AzureAutomationAuthoringToolkit: Get-AutomationAsset job started. Job id: '$($Job.Id)'"

            # Wait for Get-AutomationAsset completion
            $TotalSeconds = 0
            $JobInfo = $Null

            do {
                Write-Verbose "AzureAutomationAuthoringToolkit: Waiting for Get-AutomationAsset job completion..."
            
                Start-Sleep -Seconds $SleepTime
                $TotalSeconds += $SleepTime

                $JobInfo = Get-AzureAutomationJob -Id $Job.Id -AutomationAccountName $AccountName
            } while((!$DoneJobStatuses.Contains($JobInfo.Status)) -and ($TotalSeconds -lt $MaxSecondsToWaitOnJobCompletion))

            if($TotalSeconds -ge $MaxSecondsToWaitOnJobCompletion) {
                throw "AzureAutomationAuthoringToolkit: Timeout exceeded. 'Get-AutomationAsset' job $($Job.Id) did not complete in $MaxSecondsToWaitOnJobCompletion seconds."
            }
            elseif($JobInfo.Exception) {
                throw "AzureAutomationAuthoringToolkit: 'Get-AutomationAsset' job $($Job.Id) threw exception: $($JobInfo.Exception)"
            }
            else {
                Write-Verbose "AzureAutomationAuthoringToolkit: Get-AutomationAsset job completed successfully. Deserializing output."
            
                $SerializedOutput = Get-AzureAutomationJobOutput -Id $Job.Id -Stream Output -AutomationAccountName $AccountName
            
                $Output = [System.Management.Automation.PSSerializer]::Deserialize($SerializedOutput.Text)  

                $CacheUntil = (Get-Date).AddMinutes($Configuration.SecretsCacheTimeInMinutes)

                Write-Verbose "AzureAutomationAuthoringToolkit: Caching value of $Type asset '$Name' until $CacheUntil."

                $global:AssetCache["$Type$Name"] = @{
                    "Value" = $Output
                    "CachedUntil" = $CacheUntil.Ticks
                }

                Write-Output $Output
            }
        }
    }
}

<#
    .SYNOPSIS
        Get a variable asset from Azure Automation.
        Part of the Azure Automation Authoring Toolkit to help author runbooks locally.
#>
function Get-AutomationVariable {
    [CmdletBinding(HelpUri='http://aka.ms/azureautomationauthoringtoolkit')]
    [OutputType([Object])]
    
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    Write-Verbose "AzureAutomationAuthoringToolkit: Looking for static variable asset with name '$Name'"

    $AssetValue = Get-AzureAutomationAuthoringToolkitStaticAsset -Type Variable -Name $Name
    
    if(!$AssetValue) {
        $Configuration = Get-AzureAutomationAuthoringToolkitConfiguration
        $AccountName = $Configuration.AutomationAccountName

        Write-Verbose "AzureAutomationAuthoringToolkit: Static variable asset named '$Name' not found, 
        attempting to use Azure Automation cmdlets to grab its value from '$AccountName' automation account."
        
        Test-AzureAutomationAuthoringToolkitAzureConnection

        $Variable = Get-AzureAutomationVariable -Name $Name -AutomationAccountName $AccountName

        if(!$Variable) {
            throw "AzureAutomationAuthoringToolkit: Variable asset named '$Name' does not exist in '$AccountName' automation account."
        }
        else {           
            if($Variable.Encrypted) {
                Write-Verbose "AzureAutomationAuthoringToolkit: Variable named '$Name' is encrypted, 
                attempting to use Get-AutomationAsset runbook to grab its value from '$AccountName' automation account."
    
                if($Configuration.AllowGrabSecrets) {
                    $AssetValue = Get-AzureAutomationAuthoringToolkitAsset -Type Variable -Name $Name
                }
                else {
                    throw "AzureAutomationAuthoringToolkit: Cannot grab value of encrypted variable asset '$Name.' $script:ConfigurationPath 
                    has AllowGrabSecrets set to false. If you want to allow AzureAutomationAuthoringToolkit to grab secrets from Automation 
                    Account '$AccountName,' set AllowGrabSecrets to true. Please note this will cause the value of the asset to be displayed 
                    in plain text in an Azure Automation job's output. For this reason, it is recommended to only set AllowGrabSecrets to true 
                    when working against a 'test' automation account that does not contain production secrets." 
                }
            }
            else {
                $AssetValue = $Variable.Value
            }
        }
    }

    Write-Output $AssetValue
}

<#
    .SYNOPSIS
        Get a connection asset from Azure Automation.
        Part of the Azure Automation Authoring Toolkit to help author runbooks locally.
#>
function Get-AutomationConnection {
    [CmdletBinding(HelpUri='http://aka.ms/azureautomationauthoringtoolkit')]
    [OutputType([Hashtable])]
    
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    Write-Verbose "AzureAutomationAuthoringToolkit: Looking for static connection asset with name '$Name'"

    $AssetValue = Get-AzureAutomationAuthoringToolkitStaticAsset -Type Connection -Name $Name
    
    if(!$AssetValue) {
        Write-Verbose "AzureAutomationAuthoringToolkit: Static connection asset named '$Name' not found, 
        attempting to use Get-AutomationAsset runbook to grab its value."

        if($Configuration.AllowGrabSecrets) {
            $AssetValue = Get-AzureAutomationAuthoringToolkitAsset -Type Connection -Name $Name
        }
        else {
            throw "AzureAutomationAuthoringToolkit: Cannot grab value of connection asset '$Name.' $script:ConfigurationPath 
            has AllowGrabSecrets set to false. If you want to allow AzureAutomationAuthoringToolkit to grab secrets from Automation 
            Account '$AccountName,' set AllowGrabSecrets to true. Please note this will cause the value of the asset to be displayed 
            in plain text in an Azure Automation job's output. For this reason, it is recommended to only set AllowGrabSecrets to true 
            when working against a 'test' automation account that does not contain production secrets." 
        }
    }
    else {
        # Convert PSCustomObject to Hashtable
        $AssetValue = $AssetValue.psobject.properties | foreach -begin {$h=@{}} -process {$h."$($_.Name)" = $_.Value} -end {$h}
    }

    Write-Output $AssetValue
}

<#
    .SYNOPSIS
        Set the value of a variable asset in Azure Automation.
        Part of the Azure Automation Authoring Toolkit to help author runbooks locally.
#>
function Set-AutomationVariable {
    [CmdletBinding(HelpUri='http://aka.ms/azureautomationauthoringtoolkit')]
    
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name,

        [Parameter(Mandatory=$true)]
        [object] $Value
    )

    Write-Verbose "AzureAutomationAuthoringToolkit: Looking for static variable asset with name '$Name'"

    $StaticAssetValue = Get-AzureAutomationAuthoringToolkitStaticAsset -Type Variable -Name $Name

    if($StaticAssetValue) {
        Write-Warning "AzureAutomationAuthoringToolkit: Warning - Variable asset '$Name' has a static value defined locally. 
        Since EmulatedAutomationActivities Get-AutomationVariable activity will return that static value, this call of the 
        Set-AutomationVariable activity will not attempt to update the real value in Azure Automation. If you truely wish to
        update the variable asset in Azure Automation, remove the '$Name' variable asset from '$script:StaticAssetsPath'. This 
        way, both AzureAutomationAuthoringToolkit Get-AutomationVariable and Set-AutomationVariable will use / affect the 
        value in Azure Automation."
    }
    else {
        $Configuration = Get-AzureAutomationAuthoringToolkitConfiguration
        $AccountName = $Configuration.AutomationAccountName

        Write-Verbose "AzureAutomationAuthoringToolkit: Static variable asset with name '$Name' not found, looking for real 
        asset in Azure Automation account '$AccountName.'"

        Test-AzureAutomationAuthoringToolkitAzureConnection
    
        $Variable = Get-AzureAutomationVariable -Name $Name -AutomationAccountName $AccountName

        if($Variable) {
            Write-Verbose "AzureAutomationAuthoringToolkit: Variable asset '$Name' found. Updating it."

            Set-AzureAutomationVariable -Name $Name -Value $Value -Encrypted $Variable.Encrypted -AutomationAccountName $AccountName | Out-Null
        }
        else {
            throw "AzureAutomationAuthoringToolkit: Cannot update variable asset '$Name.' It does not exist."  
        }
    }
}

<#
    .SYNOPSIS
        Get a certificate asset from Azure Automation.
        Part of the Azure Automation Authoring Toolkit to help author runbooks locally.
#>
function Get-AutomationCertificate {
    [CmdletBinding(HelpUri='http://aka.ms/azureautomationauthoringtoolkit')]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    
    param(
        [Parameter(Mandatory=$true)]
        [string] $Name
    )

    Write-Verbose "AzureAutomationAuthoringToolkit: Looking for static certificate asset with name '$Name'"

    $AssetValue = Get-AzureAutomationAuthoringToolkitStaticAsset -Type Certificate -Name $Name
    
    if(!$AssetValue) {
        $Configuration = Get-AzureAutomationAuthoringToolkitConfiguration
        $AccountName = $Configuration.AutomationAccountName

        Write-Verbose "AzureAutomationAuthoringToolkit: Static certificate asset named '$Name' not found, 
        attempting to use Azure Automation cmdlets to grab its thumbprint from '$AccountName' automation account."
        
        Test-AzureAutomationAuthoringToolkitAzureConnection

        $CertAsset = Get-AzureAutomationCertificate -Name $Name -AutomationAccountName $AccountName

        if(!$CertAsset) {
            throw "AzureAutomationAuthoringToolkit: Certificate asset named '$Name' does not exist in '$AccountName' automation account."
        }
        else {           
            try {
                $AssetValue = Get-AzureAutomationAuthoringToolkitLocalCertificate -Name $Name -Thumbprint $CertAsset.Thumbprint
            }
            catch {
                Write-Verbose "AzureAutomationAuthoringToolkit: Certificate asset '$Name' referenced certificate with 
                thumbprint '$($CertAsset.Thumbprint)' but no certificate with that thumbprint exist on the local system. 
                Attempting to use Get-AutomationAsset runbook to grab its value from '$AccountName' automation account."
                
                if($Configuration.AllowGrabSecrets) {
                    $AssetValue = Get-AzureAutomationAuthoringToolkitAsset -Type Certificate -Name $Name
                }
                else {
                    throw "AzureAutomationAuthoringToolkit: Cannot grab value of certificate asset '$Name.' $script:ConfigurationPath 
                    has AllowGrabSecrets set to false. If you want to allow AzureAutomationAuthoringToolkit to grab secrets from Automation 
                    Account '$AccountName,' set AllowGrabSecrets to true. Please note this will cause the value of the asset to be displayed 
                    in plain text in an Azure Automation job's output. For this reason, it is recommended to only set AllowGrabSecrets to true 
                    when working against a 'test' automation account that does not contain production secrets." 
                }
            }
        }
    }

    Write-Output $AssetValue
}