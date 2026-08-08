[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module Pester -ErrorAction Stop

$testFiles = @(
    (Join-Path $PSScriptRoot 'TokenMinister.Core.Tests.ps1'),
    (Join-Path $PSScriptRoot 'TokenMinister.Integration.Tests.ps1'),
    (Join-Path $PSScriptRoot 'TokenMinister.Install.Tests.ps1'),
    (Join-Path $PSScriptRoot 'TokenMinister.Gui.Tests.ps1')
)
$result = Invoke-Pester -Script $testFiles -PassThru
if ($result.FailedCount -gt 0) {
    exit 1
}
