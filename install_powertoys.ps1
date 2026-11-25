# PowerToys' own installer (WixBundleName "PowerToys (Preview) x64") installs
# PER-USER by default, into %LocalAppData%\PowerToys - NOT C:\Program Files.
# That's the installer's real default and it has no switch to change it, so
# this script uses that path instead of fighting it.
$defaultPath = Join-Path $env:LOCALAPPDATA "PowerToys\PowerToys.exe"
$alreadyInstalled = Test-Path $defaultPath

Write-Host "Checking whether PowerToys is already installed..."

if ($alreadyInstalled) {
    Write-Host "PowerToys is already installed at $defaultPath - skipping the installer, but still checking for a saved settings file to apply."
}
else {
    try {
        # Bundled by the installer into this same folder (C:\Scripts), not downloaded.
        $installerPath = Join-Path $PSScriptRoot "PowerToysSetup-x64.exe"

        if (-not (Test-Path $installerPath)) {
            throw "Could not find $installerPath. Re-run BatmanPCControlSetup.exe on this PC so it gets copied into C:\Scripts, then try again."
        }

        # Clear any stale registration first so the installer doesn't pop its
        # "Modify Setup / Uninstall" repair dialog instead of installing quietly.
        Start-Process -FilePath $installerPath -ArgumentList @("/uninstall", "/quiet", "/norestart") -Wait -PassThru | Out-Null

        Write-Host "Installing PowerToys silently to $defaultPath - this can take a minute or two, please wait..."
        $logPath = Join-Path $env:TEMP "PowerToys-Install.log"
        $proc = Start-Process -FilePath $installerPath -ArgumentList @("/install", "/quiet", "/norestart", "/log", "`"$logPath`"") -Wait -PassThru

        if ($proc.ExitCode -ne 0) {
            throw "The PowerToys installer exited with code $($proc.ExitCode). Log: $logPath"
        }

        # The installer can report success before files are fully placed, so
        # poll for a while instead of checking once.
        $maxWaitSeconds = 60
        $waited = 0
        while (-not (Test-Path $defaultPath) -and $waited -lt $maxWaitSeconds) {
            Start-Sleep -Seconds 2
            $waited += 2
        }

        if (-not (Test-Path $defaultPath)) {
            throw "The installer reported success but PowerToys.exe still isn't at $defaultPath after waiting $maxWaitSeconds seconds. Check the log at $logPath for details."
        }

        Write-Host "PowerToys installed successfully."
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("Could not automatically install PowerToys.`n`nError: $($_.Exception.Message)`n`nYou can install it manually from https://aka.ms/installpowertoys and then just re-run the MQTT Setup icon to save this PC's settings again.", "PowerToys Install Failed", "OK", "Error")
        exit 1
    }
}

# --- Apply the saved PowerToys settings file (runs every time) -------------
$backupFile = Get-ChildItem -Path $PSScriptRoot -Filter "settings_*.ptb" -File | Sort-Object Name -Descending | Select-Object -First 1

if ($backupFile) {
    Write-Host "Applying saved PowerToys settings ($($backupFile.Name))..."
    try {
        # Copy where PowerToys' own Settings > General > Restore looks by default.
        $restoreFolder = Join-Path $env:USERPROFILE "Documents\PowerToys\Backup"
        if (-not (Test-Path $restoreFolder)) {
            New-Item -ItemType Directory -Path $restoreFolder -Force | Out-Null
        }
        Copy-Item -Path $backupFile.FullName -Destination $restoreFolder -Force

        # A .ptb is just a zip. Extract it into the folder PowerToys reads its
        # per-module settings from. manifest.json is bookkeeping, so skip it.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $settingsRoot = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys"
        if (-not (Test-Path $settingsRoot)) {
            New-Item -ItemType Directory -Path $settingsRoot -Force | Out-Null
        }
        $zip = [System.IO.Compression.ZipFile]::OpenRead($backupFile.FullName)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.Name -eq "" -or $entry.FullName -eq "manifest.json") { continue }
                $destPath = Join-Path $settingsRoot $entry.FullName
                $destDir = Split-Path $destPath -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
            }
        }
        finally {
            $zip.Dispose()
        }
        Write-Host "Saved settings applied."
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("Could not automatically apply the saved settings file.`n`nError: $($_.Exception.Message)`n`nA copy was placed in $restoreFolder - you can try applying it manually from PowerToys Settings > General > Restore.", "Settings Restore Failed", "OK", "Warning")
    }
}
else {
    Write-Host "No settings_*.ptb file found in $PSScriptRoot - PowerToys will keep its default settings."
}

# --- Make sure PowerToys is running with the (possibly just-updated) settings.
$running = Get-Process -Name "PowerToys.Runner" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Restarting PowerToys so it picks up the applied settings..."
    Get-Process -Name "PowerToys.Runner" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "PowerToys" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 1000
}
Start-Process -FilePath $defaultPath

Start-Sleep -Seconds 2
exit 0
