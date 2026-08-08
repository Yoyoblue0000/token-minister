$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\src\TokenMinister.Core.psm1'
Import-Module $modulePath -Force

Describe 'ConvertFrom-TMOnWatchSnapshot' {
    It 'converts OpenCode used percentages into three ordered remaining quota models' {
        $json = @'
{
  "generated_at": "2026-08-08T04:00:00Z",
  "providers": [
    {
      "id": "opencode",
      "base_provider": "opencode",
      "label": "OpenCode",
      "quotas": [
        {
          "key": "weekly",
          "label": "Weekly",
          "percent": 40.5,
          "reset_at": "2026-08-12T00:00:00Z",
          "time_until_reset": "3d 20h",
          "age_seconds": 45,
          "is_stale": false
        },
        {
          "key": "monthly",
          "label": "Monthly",
          "percent": 100,
          "reset_at": "2026-09-01T00:00:00Z",
          "time_until_reset": "23d 20h",
          "age_seconds": 45,
          "is_stale": false
        },
        {
          "key": "five_hour",
          "label": "5-Hour",
          "percent": 25,
          "reset_at": "2026-08-08T05:30:00Z",
          "time_until_reset": "1h 30m",
          "age_seconds": 45,
          "is_stale": false
        }
      ]
    }
  ]
}
'@

        $result = @(ConvertFrom-TMOnWatchSnapshot -Json $json)

        $result.Count | Should Be 3
        ($result.Key -join ',') | Should Be 'five_hour,weekly,monthly'
        ($result.Label -join ',') | Should Be '5 hours,Weekly,Monthly'
        $result[0].RemainingPercent | Should Be 75
        $result[1].RemainingPercent | Should Be 59.5
        $result[2].RemainingPercent | Should Be 0
        $result[0].TimeUntilReset | Should Be '1h 30m'
        $result[0].ResetAt | Should Be '2026-08-08T05:30:00Z'
        $result[0].IsStale | Should Be $false
    }

    It 'accepts the current onWatch five-hour quota key' {
        $json = @'
{
  "providers": [
    {
      "id": "opencode",
      "quotas": [
        {
          "key": "5-hour",
          "percent": 1,
          "reset_at": "2026-08-08T08:33:58Z",
          "time_until_reset": "2h 11m",
          "age_seconds": 63
        }
      ]
    }
  ]
}
'@

        $result = @(ConvertFrom-TMOnWatchSnapshot -Json $json)

        $result[0].RemainingPercent | Should Be 99
        $result[0].TimeUntilReset | Should Be '2h 11m'
        $result[0].ResetAt | Should Be '2026-08-08T08:33:58Z'
    }

    It 'represents a missing monthly window as unavailable instead of zero remaining' {
        $json = @'
{
  "providers": [
    {
      "id": "opencode",
      "quotas": [
        { "key": "five_hour", "percent": 10, "time_until_reset": "4h", "is_stale": false },
        { "key": "weekly", "percent": 20, "time_until_reset": "5d", "is_stale": false }
      ]
    }
  ]
}
'@

        $result = @(ConvertFrom-TMOnWatchSnapshot -Json $json)
        $monthly = $result | Where-Object { $_.Key -eq 'monthly' }

        $monthly.RemainingPercent | Should Be $null
        $monthly.TimeUntilReset | Should Be $null
        $monthly.ResetAt | Should Be $null
    }

    It 'clamps impossible provider percentages before displaying remaining quota' {
        $json = @'
{
  "providers": [
    {
      "id": "opencode",
      "quotas": [
        { "key": "five_hour", "percent": -5 },
        { "key": "weekly", "percent": 125 }
      ]
    }
  ]
}
'@

        $result = @(ConvertFrom-TMOnWatchSnapshot -Json $json)
        $result[0].RemainingPercent | Should Be 100
        $result[1].RemainingPercent | Should Be 0
    }

    It 'treats a meter without a percentage as unavailable instead of fully remaining' {
        $json = @'
{
  "providers": [
    {
      "id": "opencode",
      "quotas": [
        { "key": "five_hour", "time_until_reset": "2h" }
      ]
    }
  ]
}
'@

        $result = @(ConvertFrom-TMOnWatchSnapshot -Json $json)

        $result[0].RemainingPercent | Should Be $null
    }

    It 'rejects snapshots that do not contain OpenCode Go provider data' {
        { ConvertFrom-TMOnWatchSnapshot -Json '{ "providers": [] }' } |
            Should Throw 'OpenCode Go provider data is unavailable.'
    }

    It 'marks old quota data stale even when the backend stale flag is false' {
        $json = @'
{
  "providers": [
    {
      "id": "opencode",
      "quotas": [
        { "key": "five_hour", "percent": 10, "age_seconds": 601, "is_stale": false },
        { "key": "weekly", "percent": 20, "age_seconds": 599, "is_stale": true }
      ]
    }
  ]
}
'@

        $result = @(ConvertFrom-TMOnWatchSnapshot -Json $json -StaleAfterSeconds 600)

        $result[0].IsStale | Should Be $true
        $result[1].IsStale | Should Be $true
    }

    It 'rejects malformed JSON with a stable public error' {
        { ConvertFrom-TMOnWatchSnapshot -Json '{not-json' } |
            Should Throw 'Invalid onWatch snapshot JSON.'
    }
}

Describe 'TokenMinister secret storage' {
    It 'round-trips a secret without writing the plaintext to disk' {
        $path = Join-Path $TestDrive 'auth-cookie.dat'
        $secret = 'test-cookie-value==do-not-store-plain'

        Save-TMSecret -Path $path -PlainText $secret

        (Test-Path -LiteralPath $path) | Should Be $true
        (Get-Content -Raw -LiteralPath $path).Contains($secret) | Should Be $false
        (Get-TMSecret -Path $path) | Should Be $secret
    }

    It 'removes a saved secret' {
        $path = Join-Path $TestDrive 'remove-me.dat'
        Save-TMSecret -Path $path -PlainText 'temporary-secret'

        Remove-TMSecret -Path $path

        (Test-Path -LiteralPath $path) | Should Be $false
    }
}

Describe 'TokenMinister refresh state' {
    It 'keeps the last successful values and marks them stale after a fetch failure' {
        $state = New-TMQuotaState
        $workingFetcher = {
            @(
                [PSCustomObject]@{ Key = 'five_hour'; Label = '5 hours'; RemainingPercent = 80; TimeUntilReset = '4h'; ResetAt = '2026-08-08T08:00:00Z'; IsStale = $false },
                [PSCustomObject]@{ Key = 'weekly'; Label = 'Weekly'; RemainingPercent = 70; TimeUntilReset = '4d'; ResetAt = '2026-08-12T00:00:00Z'; IsStale = $false },
                [PSCustomObject]@{ Key = 'monthly'; Label = 'Monthly'; RemainingPercent = $null; TimeUntilReset = $null; ResetAt = $null; IsStale = $false }
            )
        }

        $state = Update-TMQuotaState -State $state -Fetcher $workingFetcher
        $successfulValues = @($state.Items.RemainingPercent)
        $state.ErrorMessage | Should Be $null

        $state = Update-TMQuotaState -State $state -Fetcher { throw 'backend offline' }

        (@($state.Items.RemainingPercent) -join ',') | Should Be ($successfulValues -join ',')
        @($state.Items | Where-Object { -not $_.IsStale }).Count | Should Be 0
        $state.ErrorMessage | Should Match 'backend offline'
    }
}

Describe 'TokenMinister freshness view' {
    BeforeEach {
        $script:now = [DateTimeOffset]::Parse('2026-08-08T12:10:00+08:00')
    }

    It 'shows just now for a recent successful refresh' {
        $state = [PSCustomObject]@{
            Items = @([PSCustomObject]@{ IsStale = $false })
            LastSuccessAt = $script:now.AddSeconds(-40)
            ErrorMessage = $null
        }

        $view = Get-TMFreshnessView -State $state -Now $script:now

        $view.Kind | Should Be 'Fresh'
        $view.RelativeText | Should Be ([string][char]0x521A + [char]0x521A)
    }

    It 'shows whole elapsed minutes while data is fresh' {
        foreach ($minutes in @(2, 8)) {
            $state = [PSCustomObject]@{
                Items = @([PSCustomObject]@{ IsStale = $false })
                LastSuccessAt = $script:now.AddMinutes(-$minutes).AddSeconds(-20)
                ErrorMessage = $null
            }

            $view = Get-TMFreshnessView -State $state -Now $script:now

            $view.Kind | Should Be 'Fresh'
            $view.RelativeText | Should Be ($minutes.ToString() + 'm')
        }
    }

    It 'marks data older than ten minutes stale and includes the last success in its tooltip' {
        $state = [PSCustomObject]@{
            Items = @([PSCustomObject]@{ IsStale = $false })
            LastSuccessAt = $script:now.AddMinutes(-11)
            ErrorMessage = $null
        }

        $view = Get-TMFreshnessView -State $state -Now $script:now

        $view.Kind | Should Be 'Stale'
        $view.RelativeText | Should Be (-join @([char]0x5DF2, [char]0x8FC7, [char]0x671F))
        $view.ToolTip | Should Match '2026-08-08 11:59:00'
    }

    It 'marks a read failure stale immediately without dropping the last success' {
        $state = [PSCustomObject]@{
            Items = @([PSCustomObject]@{ IsStale = $true })
            LastSuccessAt = $script:now.AddMinutes(-2)
            ErrorMessage = 'backend offline'
        }

        $view = Get-TMFreshnessView -State $state -Now $script:now

        $view.Kind | Should Be 'Stale'
        $view.ToolTip | Should Match 'backend offline'
        $view.ToolTip | Should Match '2026-08-08 12:08:00'
    }

    It 'uses a neutral waiting state before the first refresh' {
        $state = New-TMQuotaState

        $view = Get-TMFreshnessView -State $state -Now $script:now

        $view.Kind | Should Be 'Waiting'
    }
}

Describe 'TokenMinister settings' {
    It 'saves workspace, window geometry and topmost preference without accepting a cookie field' {
        $path = Join-Path $TestDrive 'settings.json'
        $settings = [PSCustomObject]@{
            WorkspaceId  = 'workspace-test-123'
            WindowLeft   = 42.5
            WindowTop    = 84.25
            WindowWidth  = 268
            WindowHeight = 176
            AlwaysOnTop  = $false
            AuthCookie   = 'must-never-be-written'
        }

        Save-TMSettings -Path $path -Settings $settings
        $loaded = Read-TMSettings -Path $path
        $raw = Get-Content -Raw -LiteralPath $path

        $loaded.WorkspaceId | Should Be 'workspace-test-123'
        $loaded.WindowLeft | Should Be 42.5
        $loaded.WindowTop | Should Be 84.25
        $loaded.WindowWidth | Should Be 268
        $loaded.WindowHeight | Should Be 176
        $loaded.AlwaysOnTop | Should Be $false
        $raw | Should Not Match '(?i)cookie|auth'
    }

    It 'uses compact defaults when loading a legacy settings file' {
        $path = Join-Path $TestDrive 'legacy-settings.json'
        [IO.File]::WriteAllText($path, '{"WorkspaceId":"legacy","WindowLeft":12,"WindowTop":34}')

        $loaded = Read-TMSettings -Path $path

        $loaded.WorkspaceId | Should Be 'legacy'
        $loaded.WindowLeft | Should Be 12
        $loaded.WindowTop | Should Be 34
        $loaded.WindowWidth | Should Be 208
        $loaded.WindowHeight | Should Be 118
        $loaded.AlwaysOnTop | Should Be $true
    }

    It 'uses compact defaults when no settings file exists' {
        $loaded = Read-TMSettings -Path (Join-Path $TestDrive 'missing-settings.json')

        $loaded.WindowWidth | Should Be 208
        $loaded.WindowHeight | Should Be 118
        $loaded.AlwaysOnTop | Should Be $true
    }
}

Describe 'TokenMinister window sizing' {
    It 'keeps a valid saved size within the current working area' {
        $area = [PSCustomObject]@{ Width = 1920; Height = 1040 }
        $settings = [PSCustomObject]@{ WindowWidth = 320; WindowHeight = 210 }

        $size = Resolve-TMWindowSize -Settings $settings -WorkingArea $area

        $size.Width | Should Be 320
        $size.Height | Should Be 210
    }

    It 'enforces the compact minimum size' {
        $area = [PSCustomObject]@{ Width = 1920; Height = 1040 }
        $settings = [PSCustomObject]@{ WindowWidth = 20; WindowHeight = 30 }

        $size = Resolve-TMWindowSize -Settings $settings -WorkingArea $area

        $size.Width | Should Be 192
        $size.Height | Should Be 108
    }

    It 'clamps an oversized saved size to the current working area' {
        $area = [PSCustomObject]@{ Width = 1280; Height = 984 }
        $settings = [PSCustomObject]@{ WindowWidth = 9000; WindowHeight = 8000 }

        $size = Resolve-TMWindowSize -Settings $settings -WorkingArea $area

        $size.Width | Should Be 1280
        $size.Height | Should Be 984
    }

    It 'replaces invalid saved sizes with compact defaults' {
        $area = [PSCustomObject]@{ Width = 1920; Height = 1040 }
        $settings = [PSCustomObject]@{ WindowWidth = 'not-a-number'; WindowHeight = [double]::PositiveInfinity }

        $size = Resolve-TMWindowSize -Settings $settings -WorkingArea $area

        $size.Width | Should Be 208
        $size.Height | Should Be 118
    }
}

Describe 'TokenMinister single instance lock' {
    It 'allows only one owner for the same widget name' {
        $name = 'Local\TokenMinister.Tests.' + [Guid]::NewGuid().ToString('N')
        $first = New-TMSingleInstanceLock -Name $name
        $second = New-TMSingleInstanceLock -Name $name
        try {
            $first.Acquired | Should Be $true
            $second.Acquired | Should Be $false
        }
        finally {
            Close-TMSingleInstanceLock -Lock $second
            Close-TMSingleInstanceLock -Lock $first
        }
    }
}

Describe 'TokenMinister window placement' {
    It 'centers the widget in the selected screen working area' {
        $area = [PSCustomObject]@{ Left = 0; Top = 0; Width = 1920; Height = 1040 }

        $position = Get-TMCenteredWindowPosition -WorkingArea $area -WindowWidth 336 -WindowHeight 286

        $position.Left | Should Be 792
        $position.Top | Should Be 377
    }

    It 'accounts for a screen whose working area starts at a negative coordinate' {
        $area = [PSCustomObject]@{ Left = -1280; Top = 20; Width = 1280; Height = 984 }

        $position = Get-TMCenteredWindowPosition -WorkingArea $area -WindowWidth 336 -WindowHeight 286

        $position.Left | Should Be -808
        $position.Top | Should Be 369
    }
}
