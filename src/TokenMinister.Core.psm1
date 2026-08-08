Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TMPropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $InputObject -or $InputObject.PSObject.Properties.Name -notcontains $Name) {
        return $DefaultValue
    }
    return $InputObject.$Name
}

function ConvertFrom-TMOnWatchSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,

        [ValidateRange(1, 86400)]
        [int]$StaleAfterSeconds = 600
    )

    try {
        $snapshot = $Json | ConvertFrom-Json
    }
    catch {
        throw 'Invalid onWatch snapshot JSON.'
    }
    $providers = @(Get-TMPropertyValue -InputObject $snapshot -Name 'providers' -DefaultValue @())
    $provider = @($providers | Where-Object {
        $_.id -eq 'opencode' -or $_.base_provider -eq 'opencode'
    }) | Select-Object -First 1
    if ($null -eq $provider) {
        throw 'OpenCode Go provider data is unavailable.'
    }

    $definitions = @(
        @{ Key = 'five_hour'; SourceKeys = @('five_hour', '5-hour'); Label = '5 hours' },
        @{ Key = 'weekly'; SourceKeys = @('weekly'); Label = 'Weekly' },
        @{ Key = 'monthly'; SourceKeys = @('monthly'); Label = 'Monthly' }
    )

    $quotas = @(Get-TMPropertyValue -InputObject $provider -Name 'quotas' -DefaultValue @())
    foreach ($definition in $definitions) {
        $quota = @($quotas | Where-Object { $definition.SourceKeys -contains $_.key }) | Select-Object -First 1
        $remaining = $null
        if ($null -ne $quota) {
            $rawPercent = Get-TMPropertyValue -InputObject $quota -Name 'percent'
            if ($null -ne $rawPercent) {
                $usedPercent = [double]$rawPercent
                $usedPercent = [Math]::Min([double]100.0, [Math]::Max([double]0.0, $usedPercent))
                $remaining = [double](100 - $usedPercent)
            }
        }
        $ageSeconds = [int](Get-TMPropertyValue -InputObject $quota -Name 'age_seconds' -DefaultValue 0)
        $isStale = [bool](Get-TMPropertyValue -InputObject $quota -Name 'is_stale' -DefaultValue $false)
        if ($null -ne $quota -and $ageSeconds -gt $StaleAfterSeconds) {
            $isStale = $true
        }
        [PSCustomObject]@{
            PSTypeName       = 'TokenMinister.QuotaViewModel'
            Key              = $definition.Key
            Label            = $definition.Label
            RemainingPercent = $remaining
            TimeUntilReset   = Get-TMPropertyValue -InputObject $quota -Name 'time_until_reset'
            ResetAt          = Get-TMPropertyValue -InputObject $quota -Name 'reset_at'
            IsStale          = $isStale
        }
    }
}

function Save-TMSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$PlainText
    )

    Add-Type -AssemblyName System.Security
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    try {
        $protectedBytes = [Security.Cryptography.ProtectedData]::Protect(
            $plainBytes,
            $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $payload = 'dpapi1:' + [Convert]::ToBase64String($protectedBytes)
        [IO.File]::WriteAllText($Path, $payload, (New-Object Text.UTF8Encoding($false)))
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}

function Get-TMSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw 'TokenMinister secret was not found.'
    }
    Add-Type -AssemblyName System.Security
    $payload = [IO.File]::ReadAllText($Path)
    if (-not $payload.StartsWith('dpapi1:')) {
        throw 'TokenMinister secret has an unsupported format.'
    }
    $protectedBytes = [Convert]::FromBase64String($payload.Substring(7))
    $plainBytes = [Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes,
        $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    try {
        return [Text.Encoding]::UTF8.GetString($plainBytes)
    }
    finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
}

function Remove-TMSecret {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ((Test-Path -LiteralPath $Path) -and $PSCmdlet.ShouldProcess($Path, 'Remove encrypted secret')) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Get-TMQuotaSnapshot {
    [CmdletBinding()]
    param(
        [string]$Uri = 'http://127.0.0.1:9211/api/menubar/summary',
        [ValidateRange(1, 60)][int]$TimeoutSeconds = 5,
        [ValidateRange(1, 86400)][int]$StaleAfterSeconds = 600
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec $TimeoutSeconds
    }
    catch {
        throw ('Unable to read the onWatch summary: {0}' -f $_.Exception.Message)
    }
    return ConvertFrom-TMOnWatchSnapshot -Json $response.Content -StaleAfterSeconds $StaleAfterSeconds
}

function New-TMQuotaState {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Items         = @()
        LastSuccessAt = $null
        LastAttemptAt = $null
        ErrorMessage  = $null
    }
}

function Update-TMQuotaState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][scriptblock]$Fetcher
    )

    $attemptedAt = [DateTimeOffset]::Now
    try {
        $items = @(& $Fetcher)
        return [PSCustomObject]@{
            Items         = $items
            LastSuccessAt = $attemptedAt
            LastAttemptAt = $attemptedAt
            ErrorMessage  = $null
        }
    }
    catch {
        $staleItems = foreach ($item in @($State.Items)) {
            [PSCustomObject]@{
                PSTypeName       = 'TokenMinister.QuotaViewModel'
                Key              = $item.Key
                Label            = $item.Label
                RemainingPercent = $item.RemainingPercent
                TimeUntilReset   = $item.TimeUntilReset
                ResetAt          = $item.ResetAt
                IsStale          = $true
            }
        }
        return [PSCustomObject]@{
            Items         = @($staleItems)
            LastSuccessAt = $State.LastSuccessAt
            LastAttemptAt = $attemptedAt
            ErrorMessage  = $_.Exception.Message
        }
    }
}

function Get-TMFreshnessView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [DateTimeOffset]$Now = [DateTimeOffset]::Now,
        [ValidateRange(1, 86400)][int]$StaleAfterSeconds = 600
    )

    $lastSuccess = Get-TMPropertyValue -InputObject $State -Name 'LastSuccessAt'
    $errorMessage = [string](Get-TMPropertyValue -InputObject $State -Name 'ErrorMessage' -DefaultValue '')
    $items = @(Get-TMPropertyValue -InputObject $State -Name 'Items' -DefaultValue @())
    $justNowText = -join @([char]0x521A, [char]0x521A)
    $staleText = -join @([char]0x5DF2, [char]0x8FC7, [char]0x671F)
    $readingText = -join @([char]0x8BFB, [char]0x53D6, [char]0x4E2D)

    if ($null -eq $lastSuccess) {
        $kind = if ([string]::IsNullOrWhiteSpace($errorMessage)) { 'Waiting' } else { 'Stale' }
        $relativeText = if ($kind -eq 'Waiting') { $readingText } else { $staleText }
        $toolTip = if ($kind -eq 'Waiting') { $readingText } else { $errorMessage }
        return [PSCustomObject]@{
            Kind         = $kind
            RelativeText = $relativeText
            ToolTip      = $toolTip
        }
    }

    $lastSuccessAt = [DateTimeOffset]$lastSuccess
    $age = $Now - $lastSuccessAt
    if ($age.TotalSeconds -lt 0) {
        $age = [TimeSpan]::Zero
    }
    $hasStaleItem = @($items | Where-Object {
        [bool](Get-TMPropertyValue -InputObject $_ -Name 'IsStale' -DefaultValue $false)
    }).Count -gt 0
    $isStale = -not [string]::IsNullOrWhiteSpace($errorMessage) -or
        $hasStaleItem -or $age.TotalSeconds -gt $StaleAfterSeconds

    $toolTipLines = New-Object Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($errorMessage)) {
        $toolTipLines.Add(('Error: {0}' -f $errorMessage))
    }
    $toolTipLines.Add(('Last success: {0:yyyy-MM-dd HH:mm:ss}' -f $lastSuccessAt.LocalDateTime))

    if ($isStale) {
        return [PSCustomObject]@{
            Kind         = 'Stale'
            RelativeText = $staleText
            ToolTip      = ($toolTipLines -join [Environment]::NewLine)
        }
    }

    $relativeText = if ($age.TotalMinutes -lt 1) {
        $justNowText
    }
    else {
        ('{0}m' -f [Math]::Floor($age.TotalMinutes))
    }
    return [PSCustomObject]@{
        Kind         = 'Fresh'
        RelativeText = $relativeText
        ToolTip      = ($toolTipLines -join [Environment]::NewLine)
    }
}

function Save-TMSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Settings
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    $safeSettings = [ordered]@{
        WorkspaceId  = [string](Get-TMPropertyValue -InputObject $Settings -Name 'WorkspaceId' -DefaultValue '')
        WindowLeft   = Get-TMPropertyValue -InputObject $Settings -Name 'WindowLeft'
        WindowTop    = Get-TMPropertyValue -InputObject $Settings -Name 'WindowTop'
        WindowWidth  = Get-TMPropertyValue -InputObject $Settings -Name 'WindowWidth' -DefaultValue 251
        WindowHeight = Get-TMPropertyValue -InputObject $Settings -Name 'WindowHeight' -DefaultValue 166
        AlwaysOnTop  = [bool](Get-TMPropertyValue -InputObject $Settings -Name 'AlwaysOnTop' -DefaultValue $true)
    }
    $json = $safeSettings | ConvertTo-Json
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Read-TMSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{
            WorkspaceId  = ''
            WindowLeft   = $null
            WindowTop    = $null
            WindowWidth  = 251
            WindowHeight = 166
            AlwaysOnTop  = $true
        }
    }
    try {
        $settings = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    }
    catch {
        throw 'TokenMinister settings JSON is invalid.'
    }
    return [PSCustomObject]@{
        WorkspaceId  = [string](Get-TMPropertyValue -InputObject $settings -Name 'WorkspaceId' -DefaultValue '')
        WindowLeft   = Get-TMPropertyValue -InputObject $settings -Name 'WindowLeft'
        WindowTop    = Get-TMPropertyValue -InputObject $settings -Name 'WindowTop'
        WindowWidth  = Get-TMPropertyValue -InputObject $settings -Name 'WindowWidth' -DefaultValue 251
        WindowHeight = Get-TMPropertyValue -InputObject $settings -Name 'WindowHeight' -DefaultValue 166
        AlwaysOnTop  = [bool](Get-TMPropertyValue -InputObject $settings -Name 'AlwaysOnTop' -DefaultValue $true)
    }
}

function Resolve-TMWindowSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)]$WorkingArea,
        [ValidateRange(1, 10000)][double]$DefaultWidth = 251,
        [ValidateRange(1, 10000)][double]$DefaultHeight = 166,
        [ValidateRange(1, 10000)][double]$MinimumWidth = 192,
        [ValidateRange(1, 10000)][double]$MinimumHeight = 108
    )

    $width = $DefaultWidth
    $height = $DefaultHeight
    try {
        $candidateWidth = [double](Get-TMPropertyValue -InputObject $Settings -Name 'WindowWidth' -DefaultValue $DefaultWidth)
        if (-not [double]::IsNaN($candidateWidth) -and -not [double]::IsInfinity($candidateWidth)) {
            $width = $candidateWidth
        }
    }
    catch { }
    try {
        $candidateHeight = [double](Get-TMPropertyValue -InputObject $Settings -Name 'WindowHeight' -DefaultValue $DefaultHeight)
        if (-not [double]::IsNaN($candidateHeight) -and -not [double]::IsInfinity($candidateHeight)) {
            $height = $candidateHeight
        }
    }
    catch { }

    $maximumWidth = [Math]::Max($MinimumWidth, [double]$WorkingArea.Width)
    $maximumHeight = [Math]::Max($MinimumHeight, [double]$WorkingArea.Height)
    return [PSCustomObject]@{
        Width  = [Math]::Min($maximumWidth, [Math]::Max($MinimumWidth, $width))
        Height = [Math]::Min($maximumHeight, [Math]::Max($MinimumHeight, $height))
    }
}

function New-TMRandomPassword {
    param([int]$ByteCount = 24)

    $bytes = New-Object byte[] $ByteCount
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    }
    finally {
        $generator.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-TMDefaultProcessRunner {
    return {
        param($FilePath, $ArgumentList, $Wait)
        $parameters = @{
            FilePath    = $FilePath
            WindowStyle = 'Hidden'
            PassThru    = $true
        }
        if (@($ArgumentList).Count -gt 0) {
            $parameters.ArgumentList = @($ArgumentList)
        }
        if ($Wait) {
            $parameters.Wait = $true
        }
        return Start-Process @parameters
    }
}

function Start-TMOnWatchBackend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BinaryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$WorkspaceId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$AuthCookie,
        [ValidateRange(1, 65535)][int]$Port = 9211,
        [ValidateRange(30, 86400)][int]$PollIntervalSeconds = 120,
        [string]$DatabasePath,
        [scriptblock]$ProcessRunner = (Get-TMDefaultProcessRunner)
    )

    if (-not [string]::IsNullOrWhiteSpace($DatabasePath)) {
        $databaseDirectory = Split-Path -Parent $DatabasePath
        if ($databaseDirectory -and -not (Test-Path -LiteralPath $databaseDirectory)) {
            [void][IO.Directory]::CreateDirectory($databaseDirectory)
        }
    }

    $values = [ordered]@{
        OPENCODE_GO_WORKSPACE_ID  = $WorkspaceId.Trim()
        OPENCODE_GO_AUTH_COOKIE   = $AuthCookie
        ONWATCH_HOST              = '127.0.0.1'
        ONWATCH_PORT              = [string]$Port
        ONWATCH_POLL_INTERVAL     = [string]$PollIntervalSeconds
        ONWATCH_ADMIN_USER        = 'tokenminister'
        ONWATCH_ADMIN_PASS        = New-TMRandomPassword
    }
    if (-not [string]::IsNullOrWhiteSpace($DatabasePath)) {
        $values['ONWATCH_DB_PATH'] = $DatabasePath
    }

    $previous = @{}
    foreach ($name in $values.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$values[$name], 'Process')
    }
    try {
        return & $ProcessRunner $BinaryPath ([string[]]@()) $false
    }
    finally {
        foreach ($name in $values.Keys) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}

function Stop-TMOnWatchBackend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BinaryPath,
        [scriptblock]$ProcessRunner = (Get-TMDefaultProcessRunner)
    )

    return & $ProcessRunner $BinaryPath ([string[]]@('stop')) $true
}

function Restart-TMOnWatchBackend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BinaryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$WorkspaceId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$AuthCookie,
        [ValidateRange(1, 65535)][int]$Port = 9211,
        [ValidateRange(30, 86400)][int]$PollIntervalSeconds = 120,
        [string]$DatabasePath,
        [scriptblock]$ProcessRunner = (Get-TMDefaultProcessRunner)
    )

    Stop-TMOnWatchBackend -BinaryPath $BinaryPath -ProcessRunner $ProcessRunner | Out-Null
    return Start-TMOnWatchBackend -BinaryPath $BinaryPath -WorkspaceId $WorkspaceId `
        -AuthCookie $AuthCookie -Port $Port -PollIntervalSeconds $PollIntervalSeconds `
        -DatabasePath $DatabasePath -ProcessRunner $ProcessRunner
}

function New-TMSingleInstanceLock {
    [CmdletBinding()]
    param(
        [string]$Name = 'Local\TokenMinister.OpenCodeGoWidget'
    )

    $createdNew = $false
    $mutex = New-Object Threading.Mutex($true, $Name, [ref]$createdNew)
    return [PSCustomObject]@{
        Acquired = $createdNew
        Mutex    = $mutex
    }
}

function Close-TMSingleInstanceLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Lock
    )

    if ($null -eq $Lock.Mutex) {
        return
    }
    if ($Lock.Acquired) {
        try { $Lock.Mutex.ReleaseMutex() } catch { }
    }
    $Lock.Mutex.Dispose()
    $Lock.Mutex = $null
}

function Get-TMCenteredWindowPosition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$WorkingArea,
        [Parameter(Mandatory = $true)][ValidateRange(1, 10000)][double]$WindowWidth,
        [Parameter(Mandatory = $true)][ValidateRange(1, 10000)][double]$WindowHeight
    )

    return [PSCustomObject]@{
        Left = [double]$WorkingArea.Left + (($WorkingArea.Width - $WindowWidth) / 2)
        Top  = [double]$WorkingArea.Top + (($WorkingArea.Height - $WindowHeight) / 2)
    }
}

Export-ModuleMember -Function @(
    'ConvertFrom-TMOnWatchSnapshot',
    'Get-TMQuotaSnapshot',
    'New-TMQuotaState',
    'Update-TMQuotaState',
    'Get-TMFreshnessView',
    'Save-TMSettings',
    'Read-TMSettings',
    'Resolve-TMWindowSize',
    'Save-TMSecret',
    'Get-TMSecret',
    'Remove-TMSecret',
    'Start-TMOnWatchBackend',
    'Stop-TMOnWatchBackend',
    'Restart-TMOnWatchBackend',
    'New-TMSingleInstanceLock',
    'Close-TMSingleInstanceLock',
    'Get-TMCenteredWindowPosition'
)
