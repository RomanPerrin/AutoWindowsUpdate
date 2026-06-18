# Author: Roman PERRIN
# Date: 2026/06/16
# Installs all windows update available, reboots as many times as necessary.

# Privilege elevation
if (!
    #current role
    (New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    #is admin?
    )).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
) {
    #elevate script and exit current non-elevated runtime
    Start-Process `
        -FilePath 'powershell' `
        -ArgumentList (
            #flatten to single array
            '-File', $MyInvocation.MyCommand.Source, $args `
            | %{ $_ }
        ) `
        -Verb RunAs
    exit
}

# Check for required module
Write-Output "Checking for required module"
if (!(Get-Module -Name PSWindowsUpdate -ListAvailable)) {
    try {
        Install-Module -Name PSWindowsUpdate -Force
        Write-Output "Module installed"
    } catch {
        Write-Error "Can't install required module"
        Exit 1
    }
} else {
    Write-Output "Module already installed"
}
Import-Module PSWindowsUpdate

Write-Output "Looking for updates..."
$updates = Get-WindowsUpdate -AcceptAll -Criteria "isinstalled=0 and deploymentaction=*"

if ($updates) {
    # Install update without rebooting
    Write-Output install updates: $updates
    Install-WindowsUpdate -AcceptAll -IgnoreReboot -Criteria "isinstalled=0 and deploymentaction=*"
} else {
    Write-Output "No updates available"
}

# If reboot necessary, add script to run on startup and reboot
$RequiresReboot = Get-WURebootStatus -Silent
$TaskExist = Get-ScheduledTask | Where-Object {$_.TaskName -match "AutoWU" }
if ($RequiresReboot) {
    if (!($TaskExist)) {
        Write-Output "Adding task to the scheduler"
        $ScriptLocation = $MyInvocation.MyCommand.Path
        $Trigger = New-ScheduledTaskTrigger -AtStartup
        $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $Action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $ScriptLocation
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -WakeToRun
        $Task = New-ScheduledTask -Action $Action -Principal $Principal -Trigger $Trigger -Settings $Settings
        Register-ScheduledTask -TaskName "AutoWU" -InputObject $Task
    } else {
        Write-Output "Task already added"
    }
    shutdown -r -t 10
} else {
    # remove task when no reboot necessary
    if ($TaskExist) {
        Write-Output "Removing task from the scheduler"
        Unregister-ScheduledTask -TaskName "AutoWU" -Confirm:$false
    }

    # Display end of updates
    msg.exe * "All updates have been installed!"
}