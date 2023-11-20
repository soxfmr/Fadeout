Fadeout
===

<p align="left">
  <a href="https://skillicons.dev">
    <img src="https://skillicons.dev/icons?i=powershell" />
  </a>
</p>

A Simple PowerShell module to hide the idle mouse cursor automatically, it's binary free 🍻!

Table of Contents
-----------------

* [Installation](#installation)
    * [Using Fadeout Installer](#using-fadeout-installer)
    * [Using git](#using-git)
* [Run Fadeout](#run-fadeout)
* [Uninstall](#uninstall)
* [Todo List](#todo-list)

Installation
-----------------

Notice that **the installation procedure and cmdlets shown below are required to run as Administrator privileges.**

Since low integrity applications are unable to access processes with high integrity privileges, normally the cursor of a window owned by processes with high privileges context cannot be hidden when running Fadeout under a restricted user.

Users could start Fadeout by running a new PowerShell as Administrator to elevate the privileges everytime, but that's not an elegant choice.

Fadeout solves this problem by registering a new scheduled task to activate Fadeout that runs with Administrator privileges at logon automatically, thus Administrator privileges must be granted to Fadeout Installer in the installation procedure and the mangement cmdlets.

### Using Fadeout Installer

```powershell
$InstallPath = "C:\Fadeout" # change the install path
iex '$response = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/soxfmr/Fadeout/master/Fadeout/FadeoutInstaller.psm1"; $moduleBlock = [ScriptBlock]::Create($response.Content); New-Module -ScriptBlock $moduleBlock | Import-Module; Install-Fadeout -InstallPath $InstallPath -HttpProxy $Proxy'
```

If your internal network requires proxy to access the Internet, you could specify the proxy address argument being used during the installation:

```powershell
$InstallPath = "C:\Fadeout"          # change the install path
$Proxy = "http://127.0.0.1:1080"     # Only HTTP / HTTPS proxy is supported
iex '$response = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/soxfmr/Fadeout/master/Fadeout/FadeoutInstaller.psm1" -Proxy $Proxy; $moduleBlock = [ScriptBlock]::Create($response.Content); New-Module -ScriptBlock $moduleBlock | Import-Module; Install-Fadeout -InstallPath $InstallPath -HttpProxy $Proxy'
```

Or provide a proxy credential if authentication is needed:

```powershell
$InstallPath = "C:\Fadeout"          # change the install path
$Proxy = "http://127.0.0.1:1080"     # Only HTTP / HTTPS proxy is supported
$ProxyCred = New-Object System.Management.Automation.PSCredential -ArgumentList "proxy-user", (ConvertTo-SecureString "p@ssw0rd" -AsPlainText -Force)
IEX '$response = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/soxfmr/Fadeout/master/Fadeout/FadeoutInstaller.psm1" -Proxy $Proxy -ProxyCredential $ProxyCred; $moduleBlock = [ScriptBlock]::Create($response.Content); New-Module -ScriptBlock $moduleBlock | Import-Module; Install-Fadeout -InstallPath $InstallPath -HttpProxy -ProxyCredential $ProxyCred'
```

### Using git

```powershell
cd C:\
git clone https://github.com/soxfmr/Fadeout Fadeout
cd Fadeout

Import-Module .\Fadeout\Fadeout.psd1 -Force
Install-FadeoutLocal -InstallPath $PWD.Path
```

Run Fadeout
-----------------

Starting Fadeout to hide the idle cursor:

```powershell
Start-Fadeout
```

Stopping Fadeout:

```powershell
Stop-Fadeout
```

Uninstall
-----------------

```powershell
Uninstall-Fadeout -InstallPath C:\Fadeout
```

Remove Fadeout in non-interactive mode, keep in mind that the uninstallation procedure will check out `Fadeout.Lock` file inside the install path to avoid incautious removal of other system of user files. In case the lock file doesn't exist, A dialogue will still be shown up even `-Confirm` flag is presented:

```powershell
Uninstall-Fadeout -InstallPath C:\Fadeout -Confirm
```

Todo List
-----------------

### Fadeout Features

- [ ] Recover the cursor position before users stop Fadeout
- [ ] Compactible checks for ExecutionTimeLimit when registering the scheduled task

### Fadeout Periphery

- [ ] More fine-grained control of FadeoutManagement
- [ ] Hide the flash window while starting Fadeout
- [ ] Add a new flag to support full non-interactive mode in the uninstallation procedure
