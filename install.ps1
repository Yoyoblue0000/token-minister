[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Uninstall,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'TokenMinister'),
    [string]$StartupDirectory = [Environment]::GetFolderPath('Startup'),
    [string]$DesktopDirectory = [Environment]::GetFolderPath('Desktop'),
    [string]$OnWatchSourcePath,
    [string]$ExpectedHash = 'EC5764CC98ED05CA887C9D541A521163F936C017B771A28BE7CAA710FD03EEC9',
    [switch]$StartNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TMOnWatchSpec {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Version  = 'v2.14.3'
        FileName = 'onwatch-windows-amd64.exe'
        Url      = 'https://github.com/onllm-dev/onwatch/releases/download/v2.14.3/onwatch-windows-amd64.exe'
        Sha256   = 'A8DA1F0D89689C0F5B2735C1EF7298AA9493A600222146EEF42FF527985EC9E1'
    }
}

function Test-TMWindowsAmd64 {
    [CmdletBinding()]
    param()

    if (-not [Environment]::Is64BitOperatingSystem) {
        return $false
    }
    $nativeArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    }
    else {
        $env:PROCESSOR_ARCHITECTURE
    }
    return $nativeArchitecture -eq 'AMD64'
}

function Test-TMDownloadedBinary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedHash
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return $actual.Equals($ExpectedHash, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-TMSafeInstallRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $rootPath = [IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    $profilePath = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($fullPath) -or $fullPath -eq $rootPath -or $fullPath -eq $profilePath) {
        throw 'Refusing to use a broad or unsafe install root.'
    }
    if (-not [IO.Path]::GetFileName($fullPath).Equals('TokenMinister', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The install root must end with a TokenMinister directory.'
    }
    return $fullPath
}

function New-TMAppShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$ShortcutPath
    )

    $shortcutDirectory = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $shortcutDirectory)) {
        [void][IO.Directory]::CreateDirectory($shortcutDirectory)
    }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = (Join-Path $PSHOME 'powershell.exe')
    $entryPath = Join-Path $InstallRoot 'TokenMinister.ps1'
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"' -f $entryPath
    $shortcut.WorkingDirectory = $InstallRoot
    $shortcut.WindowStyle = 7
    $shortcut.Description = 'OpenCode Go quota widget'
    $iconPath = Join-Path $InstallRoot 'TokenMinister.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $shortcut.IconLocation = $iconPath + ',0'
    }
    $shortcut.Save()
    return $shortcutPath
}

function New-TMStartupShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$StartupDirectory
    )

    return New-TMAppShortcut -InstallRoot $InstallRoot `
        -ShortcutPath (Join-Path $StartupDirectory 'TokenMinister.lnk')
}

function New-TMDesktopShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$DesktopDirectory
    )

    return New-TMAppShortcut -InstallRoot $InstallRoot `
        -ShortcutPath (Join-Path $DesktopDirectory 'TokenMinister.lnk')
}

function Install-TokenMinister {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'TokenMinister'),
        [string]$StartupDirectory = [Environment]::GetFolderPath('Startup'),
        [string]$DesktopDirectory = [Environment]::GetFolderPath('Desktop'),
        [string]$OnWatchSourcePath,
        [string]$ExpectedHash = (Get-TMOnWatchSpec).Sha256,
        [switch]$StartNow
    )

    if (-not (Test-TMWindowsAmd64)) {
        throw 'TokenMinister requires Windows AMD64 (x64).'
    }
    $InstallRoot = Assert-TMSafeInstallRoot -Path $InstallRoot
    $spec = Get-TMOnWatchSpec
    $downloadedFile = $null
    try {
        if ([string]::IsNullOrWhiteSpace($OnWatchSourcePath)) {
            $downloadedFile = [IO.Path]::GetTempFileName()
            Invoke-WebRequest -UseBasicParsing -Uri $spec.Url -OutFile $downloadedFile
            $binarySource = $downloadedFile
        }
        else {
            $binarySource = [IO.Path]::GetFullPath($OnWatchSourcePath)
        }
        if (-not (Test-TMDownloadedBinary -Path $binarySource -ExpectedHash $ExpectedHash)) {
            throw 'The onWatch binary SHA-256 does not match the pinned value.'
        }

        if ($PSCmdlet.ShouldProcess($InstallRoot, 'Install TokenMinister')) {
            [void][IO.Directory]::CreateDirectory($InstallRoot)
            $binDirectory = Join-Path $InstallRoot 'bin'
            [void][IO.Directory]::CreateDirectory($binDirectory)

            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\TokenMinister.ps1') `
                -Destination (Join-Path $InstallRoot 'TokenMinister.ps1') -Force
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\TokenMinister.Core.psm1') `
                -Destination (Join-Path $InstallRoot 'TokenMinister.Core.psm1') -Force
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'assets\TokenMinister.ico') `
                -Destination (Join-Path $InstallRoot 'TokenMinister.ico') -Force
            foreach ($document in @('README.md', 'THIRD_PARTY_NOTICES.md')) {
                $sourceDocument = Join-Path $PSScriptRoot $document
                if (Test-Path -LiteralPath $sourceDocument) {
                    Copy-Item -LiteralPath $sourceDocument -Destination (Join-Path $InstallRoot $document) -Force
                }
            }
            Copy-Item -LiteralPath $binarySource -Destination (Join-Path $binDirectory $spec.FileName) -Force
            [void](New-TMStartupShortcut -InstallRoot $InstallRoot -StartupDirectory $StartupDirectory)
            [void](New-TMDesktopShortcut -InstallRoot $InstallRoot -DesktopDirectory $DesktopDirectory)

            if ($StartNow) {
                $shortcut = Join-Path $StartupDirectory 'TokenMinister.lnk'
                Start-Process -FilePath $shortcut | Out-Null
            }
        }
        return [PSCustomObject]@{
            InstallRoot = $InstallRoot
            StartupLink = Join-Path $StartupDirectory 'TokenMinister.lnk'
            DesktopLink = Join-Path $DesktopDirectory 'TokenMinister.lnk'
            Version     = $spec.Version
        }
    }
    finally {
        if ($downloadedFile -and (Test-Path -LiteralPath $downloadedFile)) {
            Remove-Item -LiteralPath $downloadedFile -Force
        }
    }
}

function Uninstall-TokenMinister {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'TokenMinister'),
        [string]$StartupDirectory = [Environment]::GetFolderPath('Startup'),
        [string]$DesktopDirectory = [Environment]::GetFolderPath('Desktop'),
        [switch]$SkipBackendStop
    )

    $InstallRoot = Assert-TMSafeInstallRoot -Path $InstallRoot
    $shortcutPath = Join-Path $StartupDirectory 'TokenMinister.lnk'
    $desktopShortcutPath = Join-Path $DesktopDirectory 'TokenMinister.lnk'
    $binaryPath = Join-Path $InstallRoot 'bin\onwatch-windows-amd64.exe'
    if (-not $SkipBackendStop -and (Test-Path -LiteralPath $binaryPath)) {
        try {
            Start-Process -FilePath $binaryPath -ArgumentList @('stop') -WindowStyle Hidden -Wait | Out-Null
        }
        catch {
            Write-Warning ('Unable to stop onWatch before uninstall: {0}' -f $_.Exception.Message)
        }
    }

    if ((Test-Path -LiteralPath $shortcutPath) -and $PSCmdlet.ShouldProcess($shortcutPath, 'Remove startup shortcut')) {
        Remove-Item -LiteralPath $shortcutPath -Force
    }
    if ((Test-Path -LiteralPath $desktopShortcutPath) -and $PSCmdlet.ShouldProcess($desktopShortcutPath, 'Remove desktop shortcut')) {
        Remove-Item -LiteralPath $desktopShortcutPath -Force
    }
    if ((Test-Path -LiteralPath $InstallRoot) -and $PSCmdlet.ShouldProcess($InstallRoot, 'Remove TokenMinister files and DPAPI credentials')) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    }
    Write-Output 'TokenMinister was removed. onWatch history under the user profile was preserved.'
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($Uninstall) {
        Uninstall-TokenMinister -InstallRoot $InstallRoot -StartupDirectory $StartupDirectory `
            -DesktopDirectory $DesktopDirectory
    }
    else {
        Install-TokenMinister -InstallRoot $InstallRoot -StartupDirectory $StartupDirectory `
            -DesktopDirectory $DesktopDirectory `
            -OnWatchSourcePath $OnWatchSourcePath -ExpectedHash $ExpectedHash -StartNow:$StartNow
    }
}
