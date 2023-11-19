$_defaultFadeoutTaskName = "Fadeout"
$_defaultFadeoutTaskActionExec = "powershell"
$_defaultFadeoutTaskActionArguments = '-WindowStyle Hidden -Command "Import-Module ./Fadeout/Fadeout.psd1; Mount-Fadeout'
$_defaultFadeoutLockFile = "Fadeout.Lock"
$_defaultFadeoutDownloadURLFileMappings = [ordered] @{
    "https://raw.githubusercontent.com/soxfmr/Fadeout/master/config.xml" = "config.xml"
    "https://raw.githubusercontent.com/soxfmr/Fadeout/master/Fadeout/Fadeout.psd1" = "Fadeout/Fadeout.psd1"
    "https://raw.githubusercontent.com/soxfmr/Fadeout/master/Fadeout/Fadeout.psm1" = "Fadeout/Fadeout.psm1"
    "https://raw.githubusercontent.com/soxfmr/Fadeout/master/Fadeout/FadeoutManagement.psm1" = "Fadeout/FadeoutManagement.psm1"
    "https://raw.githubusercontent.com/soxfmr/Fadeout/master/Fadeout/FadeoutInstaller.psm1" = "Fadeout/FadeoutInstaller.psm1"
}
$_proxyAddress = ""
$_proxyCredential = $null
[int]$_progressPercent = 60

enum LoggingLevel {
    Info
    Error
    Warning
    Success = 3
}

function Show-LoggingMessage {
    param(
        [Parameter(Mandatory = $true)]
        $message,

        [LoggingLevel] $level = [LoggingLevel]::Info,

        [bool] $noSymbolPrefix = $false
    )

    $date = Get-Date
    $levelStr = $level.ToString().ToUpper()
    $symbolPrefix = "[*]"

    switch ($levelStr.ToString()) {
        "Info" {
            [Console]::ForegroundColor = "white"
            $symbolPrefix = "[*]"
        }

        "Error" {
            [Console]::ForegroundColor = "red"
            $symbolPrefix = "[-]"
        }

        "Warning" {
            [Console]::ForegroundColor = "yellow"
            $symbolPrefix = "[~]"
        }
        
        "Success" {
            [Console]::ForegroundColor = "green"
            $symbolPrefix = "[+]"
        }
    }

    $levelStr = "{0,-9}" -f "[${levelStr}]"
    if (! $NoSymbolPrefix) {
        $timePrefixMessage = "${date} - ${levelStr} ${symbolPrefix} ${message}"
    } else {
        $timePrefixMessage = "${date} - ${levelStr} ${message}"
    }
    
    [Console]::WriteLine($timePrefixMessage);
    [Console]::ResetColor()
}

enum ScheduledTaskTestResult {
    None
    Created
    Unknown = 3
}

function Test-ScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        [string] $TaskName
    )

    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        return [ScheduledTaskTestResult]::Created
    } catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
        $errMsg = $_.Exception.ErrorRecord.CategoryInfo.GetMessage()
        if ($errMsg.StartsWith("ObjectNotFound")) {
            return [ScheduledTaskTestResult]::None 
        }
    } catch {
    }

    return [ScheduledTaskTestResult]::Unknown
}

function Update-FadeoutInstallProgress {
    param(
        [string] $status,

        [string] $operation,
        
        [switch] $completed
    )

    if ($completed) {
        $_progressPercent = 100
        Write-Progress -Activity "Install Fadeout in Progress" -PercentComplete $_progressPercent -Completed
    } else {
        Write-Progress -Activity "Install Fadeout in Progress" -Status $status -CurrentOperation $operation -PercentComplete (++$_progressPercent)
    }
}

function Add-FadeoutScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        [string] $taskName,

        [Parameter(Mandatory = $true)]
        [string] $taskActionExec,
        
        [Parameter(Mandatory = $true)]
        [string] $taskActionArguments,

        [Parameter(Mandatory = $true)]
        [string] $workDirectory,
        
        [int] $maxRetries = 10,
        [int] $retryInterval = 1
    )

    $testResult = Test-ScheduledTask -TaskName $taskName
    if ($testResult -eq [ScheduledTaskTestResult]::Unknown) {
        throw "Cannot check the Fadeout task status, please check-out the permissions of the current session"
    }

    if ($testResult -eq [ScheduledTaskTestResult]::Created) {
        Show-LoggingMessage -Message "The scheduled task has already been created." -Level Warning
        return
    }

    Show-LoggingMessage -Message "Registering a new scheduled task..." -Level Info

    # TaskAction: what we want to execute
    #
    $taskAction = New-ScheduledTaskAction -Execute $taskActionExec -Argument $taskActionArguments -WorkingDirectory $workDirectory

    # TaskTrigger: when do we start this task
    # 
    $taskTrigger = New-ScheduledTaskTrigger -AtStartup

    # TaskPrincipal: which user or group that this task running under with
    $taskPrincipal = New-ScheduledTaskPrincipal -GroupId "BUILTIN\Administrators" -RunLevel Highest

    # TaskSettingsSet: the most complex settings that I don't want to explain 
    # 
    # The current value of ExecutionTimeLimit is only avaialable after Windows Server 2016 / Windows 10.
    # Compactible fixes are needed in the feature.
    #
    $retryTimeSpan = New-TimeSpan -Minutes $retryInterval
    $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -Hidden -RestartCount $maxRetries -RestartInterval $retryTimeSpan -ExecutionTimeLimit '00:00:00'
    
    # Register the scheduled task 
    #
    $task = Register-ScheduledTask -TaskName $taskName -Action $taskAction -Settings $taskSettings -Trigger $taskTrigger -Principal $taskPrincipal -ErrorAction Stop

    Show-LoggingMessage -Message "Registering a new scheduled task...OK." -Level Success
}

function Remove-FadeoutScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        [string] $taskName
    )
    
    $testResult = Test-ScheduledTask -TaskName $taskName
    if ($testResult -eq [ScheduledTaskTestResult]::Unknown) {
        throw "Cannot check the Fadeout task status, please check-out the permissions of the current session"
    }

    if ($testResult -eq [ScheduledTaskTestResult]::Created) {
        Show-LoggingMessage -Message "Unregistering the scheduled task..." -Level Info

        $task = Unregister-ScheduledTask -TaskName $taskName -PassThru -Confirm:$false -ErrorAction Stop

        Show-LoggingMessage -Message "Unregistering the scheduled task...OK." -Level Success
    }
}

function Add-FadeoutModulePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $installPath
    )

    $PSModulePath = $env:PSModulePath
    if ($PSModulePath -eq $null) {
        $PSModulePath = ""
    }

    if (-not ($PSModulePathxi -Contains $installPath)) {
        $PSModulePath += ";{0}" -f $installPath
        Set-Item -Path env:\PSModulePath -Value $PSModulePath | Out-Null 
        [System.Environment]::SetEnvironmentVariable("PSModulePath", $PSModulePath, [System.EnvironmentVariableTarget]::Machine)
    }
 
    Show-LoggingMessage -Message "Added the installed path {$installPath} to `$PSModulePath variable." -Level Success
}

function Remove-FadeoutModulePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $installPath
    )

    $PSModulePath = $env:PSModulePath
    if (($PSModulePath -ne $null) -and ($PSModulePath -Contains $installPath)) {
        $PSModulePath = $PSModulePath.Replace($installPath, '')
        Set-Item -Path env:\PSModulePath -Value $PSModulePath | Out-Null 
        [System.Environment]::SetEnvironmentVariable("PSModulePath", $PSModulePath, [System.EnvironmentVariableTarget]::Machine)
    }
 
    Show-LoggingMessage -Message "The path {$installPath} has been deleted from `$PSModulePath variable." -Level Success
}

<#
    .Synopsis
    This is not a malicious backdoor downloader ;)
#>
function Start-FadeoutDownloader {
    
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $URLFileMappings,
        
        [Parameter(Mandatory = $true)]
        [string] $outputDir
    )
    
    $useProxy = $false
    if ($_proxyAddress.Length -gt 0) {
        $useProxy = $true
    }

    if (! $useProxy) {
        $prologue = "Downloading all necessary files..."
    } else {
        $prologue = "Downloading all necessary files through the proxy ${_proxyAddress}..."
    }
    Show-LoggingMessage -Message $prologue -Level Info


    $url = $null
    try {
        foreach ($item in $URLFileMappings.GetEnumerator()) {
            # Compose the full path of the current file
            $url = $item.Name
            $fileName = Join-Path $outputDir -ChildPath $item.Value
            
            # Get the stored directory of the current file        
            $fileDir = Split-Path $fileName
            New-Item -Path $fileDir -ItemType Directory -Force | Out-Null
            
            Update-FadeoutInstallProgress -Activity "Install Fadeout in Progress" -Status "Start-FadeoutDownloader ->" -CurrentOperation "Downloading file ${url}" -PercentComplete (++$_progressPercent)

            if ($useProxy) {
                $res = Invoke-WebRequest -Uri $url -OutFile $fileName -Proxy $_proxyAddress -ProxyCredential $_proxyCredential -PassThru
            } else {
                $res = Invoke-WebRequest -Uri $url -OutFile $fileName -PassThru
            }

            Show-LoggingMessage -Message "The download file is written to {$fileName}." -Level Success
        }
    } catch {
        $exception = $_.Exception.Message;
        throw "Failed to download the file ${url}, exception: ${exception}"
    }

    Show-LoggingMessage -Message "Downloading all necessary files...OK." -Level Success
}

function Confirm-FadeoutInstalledFiles {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $URLFileMappings,
        
        [Parameter(Mandatory = $true)]
        [string] $installPath
    )

    foreach($item in $URLFileMappings.GetEnumerator()) {
        $fileName = Join-Path $installPath -ChildPath $item.Value

        Show-LoggingMessage -Message "Verifing the downloaded file {$fileName}..." -Level Info
        if (-not (Test-Path $fileName -PathType Leaf)) {
            throw "Failed to verify the downloaded file {$fileName}"
        }

        Show-LoggingMessage -Message "File {$fileName} is OK." -Level Success
    }
}

function Remove-FadeoutInstalledFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string] $installPath
    )

    Show-LoggingMessage -Message "Removing the Fadeout installed files..." -Level Info

    try {
        Remove-Item $installPath -Recurse -Force -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
    }

    Show-LoggingMessage -Message "Removing the Fadeout installed files...OK." -Level Success 
}

function Protect-FadeoutInstalledFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string] $installPath
    )

    Show-LoggingMessage -Message "Checking the access control list of the installed files..." -Level Info

    $untrustedUsers = @("${env:USERDOMAIN}\${env:USERNAME}", "BUILDIN\Users")
    $installPathAcl = Get-ACL -Path $installPath
    foreach ($access in $installPathAcl.Access) {
        $accessUsername = $access.IdentityReference.Value
        if (-not ($untrustedUsers -Contains $accessUsername)) {
            continue
        }
        
        $fileSystemRights = 'ReadAndExecute, Synchronize' 
        $inheritanceFlags = 'ObjectInherit, ContainerInherit'
        $propagationFlags = 'None'
        $type             = 'Allow'
        $accessRuleArgumentList = $accessUsername, $fileSystemRights, $inheritanceFlags, $propagationFlags, $type
        $accessRule = New-Object -TypeName System.Security.AccessContrddol.FileSystemAccessRule -ArgumentList $accessRuleArgumentList

        $installPathAcl.SetAccessRule($accessRule)

        Show-LoggingMessage -Message "Revoked the unsafe file permissions of user {$accessUsername}" -Level Success 
    }

    Set-ACL -Path $installPath -AclObject $installPathAcl

    Show-LoggingMessage -Message "Checking the access control list of the installed files...OK." -Level Success 
}

<#
    .Synopsis
    Fadeout deployment script.

    .Description
    Depoly Fadeout into a specific directory

    .Parameter InstallPath
    The target directory that Fadeout is settle to.

    .Example
    Start-Fadeout

    .Example
    Start-FadeoutInstaller -InstallPath "C:\\Fadeout"
#>
function Install-Fadeout {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InstallPath,

        [string] $HttpProxy,
        
        [System.Management.Automation.PSCredential] $ProxyCredential
    )

    $_proxyAddress = $HttpProxy
    $_proxyCredential = $ProxyCredential

    if (Test-Path -Path $InstallPath -PathType Leaf) {
        throw "The install file path is already exist, please remove the existing file."
    }

    Show-LoggingMessage -Message "Fadeout will be installed into ${InstallPath}." -Level Info

    # Download Fadeout files
    Start-FadeoutDownloader -URLFileMappings $_defaultFadeoutDownloadURLFileMappings -OutputDir $InstallPath

    # Check out the file's intergraty
    Update-FadeoutInstallProgress -Status "Confirm-FadeoutInstalledFiles ->" -Operation "Verifing downloaded files"
    Confirm-FadeoutInstalledFiles -URLFileMappings $_defaultFadeoutDownloadURLFileMappings -InstallPath $InstallPath

    Update-FadeoutInstallProgress -Status "Protect-FadeoutInstalledFiles ->" -Operation "Checking the file permissions"
    Protect-FadeoutInstalledFiles -InstallPath $InstallPath

    Update-FadeoutInstallProgress -Status "Add-FadeoutScheduledTask ->" -Operation "Register the scheduled task"
    Add-FadeoutScheduledTask -TaskName $_defaultFadeoutTaskName -TaskActionExec $_defaultFadeoutTaskActionExec -TaskActionArguments $_defaultFadeoutTaskActionArguments -WorkDirectory $InstallPath

    Add-FadeoutModulePath -InstallPath $InstallPath

    $lockFilePath = Join-Path $InstallPath -ChildPath $_defaultFadeoutLockFile
    echo $null > $lockFilePath

    Update-FadeoutInstallProgress -Completed

    Show-LoggingMessage -Message "All done, please enjoying. :)" -Level Success
    Show-LoggingMessage -Message "You can right now manage Fadeout by using Start-Fadeout / Stop-Fadeout ." -Level Success
}

function Uninstall-Fadeout {
    param(
        [Parameter(Mandatory = $true)]
        [string] $InstallPath,

        [bool] $Confirm = $false
    )

    if (-not (Test-Path -Path $InstallPath -PathType Container)) {
       Write-Error -Message "The target path {$InstallPath} doesn't exist."
       return
    }

    # Check out the existence of the lock file to ensure the install path belongs to Fadeout
    $testPath = Join-Path $InstallPath -ChildPath $_defaultFadeoutLockFile
    if (-not (Test-Path -Path $testPath -PathType Leaf)) {
        Get-ChildItem $InstallPath
        Write-Warning "Cannot detect Fadeout lock file in {$InstallPath}, Do you want to continue the removal procedure ?" -WarningAction Inquire
    }

    if (-not $Confirm) {
        Write-Warning "Fadeout will be removed completely from the current computer, installed path: {$InstallPath}." -WarningAction Inquire
    }

    Remove-FadeoutScheduledTask -TaskName $_defaultFadeoutTaskName
    Remove-FadeoutInstalledFiles -InstallPath $InstallPath
    Remove-FadeoutModulePath -InstallPath $InstallPath

    Show-LoggingMessage -Message "All done, see you next time. 2>" -Level Success
}

Export-ModuleMember -Function Install-Fadeout, Uninstall-Fadeout 

