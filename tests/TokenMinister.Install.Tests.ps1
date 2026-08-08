$ErrorActionPreference = 'Stop'

$installerPath = Join-Path $PSScriptRoot '..\install.ps1'
. $installerPath

Describe 'TokenMinister installer pinning' {
    It 'pins onWatch v2.13.3 Windows AMD64 with the approved SHA-256' {
        $spec = Get-TMOnWatchSpec

        $spec.Version | Should Be 'v2.13.3'
        $spec.Url | Should Be 'https://github.com/onllm-dev/onwatch/releases/download/v2.13.3/onwatch-windows-amd64.exe'
        $spec.Sha256 | Should Be 'EC5764CC98ED05CA887C9D541A521163F936C017B771A28BE7CAA710FD03EEC9'
    }

    It 'rejects a binary whose hash does not match' {
        $path = Join-Path $TestDrive 'wrong.exe'
        [IO.File]::WriteAllText($path, 'not-onwatch')

        (Test-TMDownloadedBinary -Path $path -ExpectedHash ('0' * 64)) | Should Be $false
    }
}

Describe 'TokenMinister install and uninstall' {
    It 'creates icon-bearing startup and desktop shortcuts without creating plaintext credentials' {
        $source = Join-Path $TestDrive 'fixture-onwatch.exe'
        [IO.File]::WriteAllText($source, 'test-only-binary')
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $installRoot = Join-Path $TestDrive 'TokenMinister'
        $startupRoot = Join-Path $TestDrive 'Startup'
        $desktopRoot = Join-Path $TestDrive 'Desktop'
        [void][IO.Directory]::CreateDirectory($startupRoot)
        [void][IO.Directory]::CreateDirectory($desktopRoot)

        Install-TokenMinister -InstallRoot $installRoot -StartupDirectory $startupRoot -DesktopDirectory $desktopRoot `
            -OnWatchSourcePath $source -ExpectedHash $hash

        (Test-Path -LiteralPath (Join-Path $installRoot 'TokenMinister.ps1')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $installRoot 'TokenMinister.Core.psm1')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $installRoot 'bin\onwatch-windows-amd64.exe')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $installRoot 'TokenMinister.ico')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $startupRoot 'TokenMinister.lnk')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $desktopRoot 'TokenMinister.lnk')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $installRoot 'credentials.dat')) | Should Be $false

        Uninstall-TokenMinister -InstallRoot $installRoot -StartupDirectory $startupRoot `
            -DesktopDirectory $desktopRoot -SkipBackendStop

        (Test-Path -LiteralPath $installRoot) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $startupRoot 'TokenMinister.lnk')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $desktopRoot 'TokenMinister.lnk')) | Should Be $false
    }
}
