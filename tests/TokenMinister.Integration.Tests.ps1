$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\src\TokenMinister.Core.psm1'
Import-Module $modulePath -Force

function Get-TestTcpPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

Describe 'onWatch loopback integration' {
    BeforeAll {
        $port = Get-TestTcpPort
        $fixture = Join-Path $PSScriptRoot 'fixtures\menubar-summary.json'
        $serverScript = Join-Path $PSScriptRoot 'fixtures\MockOnWatchServer.ps1'
        $server = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $serverScript),
            '-Port', $port,
            '-FixturePath', ('"{0}"' -f $fixture)
        ) -WindowStyle Hidden -PassThru
        $uri = "http://127.0.0.1:$port/api/menubar/summary"
        $ready = $false
        foreach ($attempt in 1..50) {
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 1 | Out-Null
                $ready = $true
                break
            }
            catch {
                Start-Sleep -Milliseconds 100
            }
        }
        if (-not $ready) {
            throw 'Mock onWatch server did not start.'
        }
    }

    AfterAll {
        if ($null -ne $server -and -not $server.HasExited) {
            Stop-Process -Id $server.Id -Force
        }
    }

    It 'polls the summary endpoint and converts used into remaining percentages' {
        $result = @(Get-TMQuotaSnapshot -Uri $uri -TimeoutSeconds 2)

        ($result.RemainingPercent -join ',') | Should Be '75,60,40'
    }
}

Describe 'onWatch backend lifecycle integration' {
    It 'passes the cookie only through the child environment and then restores the parent environment' {
        $previousCookie = [Environment]::GetEnvironmentVariable('OPENCODE_GO_AUTH_COOKIE', 'Process')
        $observedHolder = [PSCustomObject]@{ Value = $null }
        $databasePath = Join-Path $TestDrive 'onwatch\data\onwatch.db'
        try {
            [Environment]::SetEnvironmentVariable('OPENCODE_GO_AUTH_COOKIE', 'parent-sentinel', 'Process')
            $runner = {
                param($FilePath, $ArgumentList, $Wait)
                $observedHolder.Value = [PSCustomObject]@{
                    FilePath   = $FilePath
                    Workspace  = $env:OPENCODE_GO_WORKSPACE_ID
                    Cookie     = $env:OPENCODE_GO_AUTH_COOKIE
                    HostValue  = $env:ONWATCH_HOST
                    PortValue  = $env:ONWATCH_PORT
                    PollValue  = $env:ONWATCH_POLL_INTERVAL
                }
                return [PSCustomObject]@{ Id = 1234 }
            }

            Start-TMOnWatchBackend -BinaryPath 'fake-onwatch.exe' -WorkspaceId 'workspace-abc' `
                -AuthCookie 'child-only-cookie' -DatabasePath $databasePath -ProcessRunner $runner | Out-Null

            $observed = $observedHolder.Value
            $observed.FilePath | Should Be 'fake-onwatch.exe'
            $observed.Workspace | Should Be 'workspace-abc'
            $observed.Cookie | Should Be 'child-only-cookie'
            $observed.HostValue | Should Be '127.0.0.1'
            $observed.PortValue | Should Be '9211'
            $observed.PollValue | Should Be '120'
            (Test-Path -LiteralPath (Split-Path -Parent $databasePath) -PathType Container) | Should Be $true
            $env:OPENCODE_GO_AUTH_COOKIE | Should Be 'parent-sentinel'
            [string]::IsNullOrEmpty($env:OPENCODE_GO_WORKSPACE_ID) | Should Be $true
        }
        finally {
            [Environment]::SetEnvironmentVariable('OPENCODE_GO_AUTH_COOKIE', $previousCookie, 'Process')
        }
    }

    It 'restarts the backend by stopping before starting it again' {
        $calls = New-Object Collections.Generic.List[string]
        $runner = {
            param($FilePath, $ArgumentList, $Wait)
            if (@($ArgumentList) -contains 'stop') {
                [void]$calls.Add('stop')
            }
            else {
                [void]$calls.Add('start')
            }
            return [PSCustomObject]@{ Id = 4321 }
        }

        Restart-TMOnWatchBackend -BinaryPath 'fake-onwatch.exe' -WorkspaceId 'workspace-abc' `
            -AuthCookie 'test-cookie' -ProcessRunner $runner | Out-Null

        ($calls -join ',') | Should Be 'stop,start'
    }
}
