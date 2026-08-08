[CmdletBinding()]
param(
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'TokenMinister'),
    [string]$BackendPath,
    [string]$SummaryUri = 'http://127.0.0.1:9211/api/menubar/summary',
    [switch]$ValidateOnly,
    [switch]$ValidateHideLifecycle
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Import-Module (Join-Path $PSScriptRoot 'TokenMinister.Core.psm1') -Force

if ([string]::IsNullOrWhiteSpace($BackendPath)) {
    $BackendPath = Join-Path $DataRoot 'bin\onwatch-windows-amd64.exe'
}

$settingsPath = Join-Path $DataRoot 'settings.json'
$secretPath = Join-Path $DataRoot 'credentials.dat'
$databasePath = Join-Path $env:USERPROFILE '.onwatch\data\onwatch.db'

$mainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="TokenMinister" Width="208" Height="118" MinWidth="192" MinHeight="108"
        WindowStyle="None" Background="#FAFBFD" Opacity="0.96"
        ResizeMode="CanResize" Topmost="True" ShowInTaskbar="False"
        SnapsToDevicePixels="True" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display">
  <shell:WindowChrome.WindowChrome>
    <shell:WindowChrome ResizeBorderThickness="6" CaptionHeight="0" GlassFrameThickness="0"
                        CornerRadius="12" UseAeroCaptionButtons="False"/>
  </shell:WindowChrome.WindowChrome>
  <Window.Resources>
    <Style x:Key="ThinProgressStyle" TargetType="{x:Type ProgressBar}">
      <Setter Property="Height" Value="3"/>
      <Setter Property="Background" Value="#E7ECF3"/>
      <Setter Property="Foreground" Value="#3478F6"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type ProgressBar}">
            <Grid x:Name="PART_Track" SnapsToDevicePixels="True">
              <Border Background="{TemplateBinding Background}" CornerRadius="1.5"/>
              <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}"
                      CornerRadius="1.5" HorizontalAlignment="Left"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="QuotaLabelStyle" TargetType="{x:Type TextBlock}">
      <Setter Property="Foreground" Value="#4F596B"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="QuotaResetStyle" TargetType="{x:Type TextBlock}">
      <Setter Property="Foreground" Value="#7A8496"/>
      <Setter Property="FontSize" Value="9.5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
      <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
    </Style>
    <Style x:Key="QuotaPercentStyle" TargetType="{x:Type TextBlock}">
      <Setter Property="Foreground" Value="#172033"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="HorizontalAlignment" Value="Right"/>
    </Style>
    <Style x:Key="HeaderButtonStyle" TargetType="{x:Type Button}">
      <Setter Property="Width" Value="18"/>
      <Setter Property="Height" Value="18"/>
      <Setter Property="Foreground" Value="#7A8496"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Button}">
            <Border x:Name="BtnBg" Background="{TemplateBinding Background}" CornerRadius="4"
                    SnapsToDevicePixels="True">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="BtnBg" Property="Background" Value="#0F172033"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border x:Name="MainCard" Background="#FAFBFD" BorderBrush="#DDE3EC" BorderThickness="1"
          CornerRadius="12" Padding="8">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="24"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="20"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="20"/>
          <ColumnDefinition Width="20"/>
          <ColumnDefinition Width="20"/>
        </Grid.ColumnDefinitions>
        <Image x:Name="HeaderIcon" Width="14" Height="14" HorizontalAlignment="Left"
               VerticalAlignment="Center" Stretch="Uniform"/>
        <TextBlock Grid.Column="1" Text="TokenMinister" Foreground="#172033" FontSize="12"
                   FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        <StackPanel x:Name="FreshnessPanel" Grid.Column="2" Orientation="Horizontal"
                    VerticalAlignment="Center" Margin="4,0,4,0">
          <Ellipse x:Name="FreshnessDot" Width="7" Height="7" Fill="#A0A8B8"
                   Margin="0,0,4,0" VerticalAlignment="Center"/>
          <TextBlock x:Name="FreshnessText" Text="&#35835;&#21462;&#20013;" Foreground="#7A8496"
                     FontSize="9.5" VerticalAlignment="Center"/>
        </StackPanel>
        <Button x:Name="RefreshButton" Grid.Column="3" Style="{StaticResource HeaderButtonStyle}"
                FontFamily="Segoe MDL2 Assets" FontSize="11" Content="&#xE72C;"
                ToolTip="&#31435;&#21363;&#37325;&#35835;"/>
        <Button x:Name="PinButton" Grid.Column="4" Style="{StaticResource HeaderButtonStyle}"
                FontFamily="Segoe MDL2 Assets" FontSize="11" Content="&#xE718;"
                ToolTip="&#22987;&#32456;&#32622;&#39030;"/>
        <Button x:Name="HideButton" Grid.Column="5" Style="{StaticResource HeaderButtonStyle}"
                Content="&#215;" FontSize="14" FontWeight="Light" ToolTip="&#38544;&#34255;"/>
      </Grid>

      <Grid x:Name="FiveRow" Grid.Row="1" Margin="0,0,0,1">
        <Grid.ColumnDefinitions><ColumnDefinition Width="44"/><ColumnDefinition Width="*"/><ColumnDefinition Width="52"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="3"/></Grid.RowDefinitions>
        <TextBlock x:Name="FiveLabel" Text="5 &#23567;&#26102;" Style="{StaticResource QuotaLabelStyle}"/>
        <TextBlock x:Name="FiveReset" Grid.Column="1" Text="--" Style="{StaticResource QuotaResetStyle}"/>
        <TextBlock x:Name="FivePercent" Grid.Column="2" Text="--" Style="{StaticResource QuotaPercentStyle}"/>
        <ProgressBar x:Name="FiveProgress" Grid.Row="1" Grid.ColumnSpan="3" Minimum="0" Maximum="100"
                     Value="0" Style="{StaticResource ThinProgressStyle}"/>
      </Grid>

      <Grid x:Name="WeeklyRow" Grid.Row="2" Margin="0,0,0,1">
        <Grid.ColumnDefinitions><ColumnDefinition Width="44"/><ColumnDefinition Width="*"/><ColumnDefinition Width="52"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="3"/></Grid.RowDefinitions>
        <TextBlock x:Name="WeeklyLabel" Text="&#27599;&#21608;" Style="{StaticResource QuotaLabelStyle}"/>
        <TextBlock x:Name="WeeklyReset" Grid.Column="1" Text="--" Style="{StaticResource QuotaResetStyle}"/>
        <TextBlock x:Name="WeeklyPercent" Grid.Column="2" Text="--" Style="{StaticResource QuotaPercentStyle}"/>
        <ProgressBar x:Name="WeeklyProgress" Grid.Row="1" Grid.ColumnSpan="3" Minimum="0" Maximum="100"
                     Value="0" Style="{StaticResource ThinProgressStyle}"/>
      </Grid>

      <Grid x:Name="MonthlyRow" Grid.Row="3">
        <Grid.ColumnDefinitions><ColumnDefinition Width="44"/><ColumnDefinition Width="*"/><ColumnDefinition Width="52"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="3"/></Grid.RowDefinitions>
        <TextBlock x:Name="MonthlyLabel" Text="&#27599;&#26376;" Style="{StaticResource QuotaLabelStyle}"/>
        <TextBlock x:Name="MonthlyReset" Grid.Column="1" Text="--" Style="{StaticResource QuotaResetStyle}"/>
        <TextBlock x:Name="MonthlyPercent" Grid.Column="2" Text="--" Style="{StaticResource QuotaPercentStyle}"/>
        <ProgressBar x:Name="MonthlyProgress" Grid.Row="1" Grid.ColumnSpan="3" Minimum="0" Maximum="100"
                     Value="0" Style="{StaticResource ThinProgressStyle}"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$credentialXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TokenMinister" Width="460" Height="340" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#1B1F2A" Foreground="#EEF2F8" ShowInTaskbar="False">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="OpenCode Go &#20973;&#25454;" FontSize="20" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" Margin="0,8,0,16" Foreground="#9AA6BF" TextWrapping="Wrap"
               Text="&#20174; OpenCode dashboard &#22797;&#21046; workspace ID &#21644; auth cookie&#12290;Cookie &#21482;&#20250;&#29992; Windows DPAPI &#21152;&#23494;&#20445;&#23384;&#12290;"/>
    <TextBlock Grid.Row="2" Text="Workspace ID" Margin="0,0,0,5"/>
    <TextBox x:Name="WorkspaceBox" Grid.Row="3" Height="30" Padding="7,4" Background="#282E3D" Foreground="#F2F5FA"
             BorderBrush="#46516A"/>
    <TextBlock Grid.Row="4" Text="auth cookie" Margin="0,14,0,5"/>
    <PasswordBox x:Name="CookieBox" Grid.Row="5" Height="30" Padding="7,4" VerticalAlignment="Top"
                 Background="#282E3D" Foreground="#F2F5FA" BorderBrush="#46516A"/>
    <StackPanel Grid.Row="6" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="CancelButton" Content="&#21462;&#28040;" Width="82" Height="30" Margin="0,0,10,0"/>
      <Button x:Name="SaveButton" Content="&#20445;&#23384;&#24182;&#37325;&#21551;" Width="112" Height="30" Background="#4779F6" Foreground="White"/>
    </StackPanel>
  </Grid>
</Window>
'@

function ConvertFrom-TMXaml {
    param([Parameter(Mandatory = $true)][string]$Xaml)

    [xml]$xml = $Xaml
    $reader = New-Object Xml.XmlNodeReader $xml
    try {
        return [Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
    }
}

function Start-TMWindowMessageLoop {
    param([Parameter(Mandatory = $true)][Windows.Window]$Window)

    $Window.Show()
    [Windows.Threading.Dispatcher]::Run()
}

function Get-TMText {
    param([Parameter(Mandatory = $true)][string]$Key)

    $codes = switch ($Key) {
        'Unavailable'       { @(0x672A, 0x63D0, 0x4F9B) }
        'Stale'             { @(0x6570, 0x636E, 0x8FC7, 0x671F) }
        'CheckLogin'        { @(0x8BF7, 0x68C0, 0x67E5, 0x767B, 0x5F55, 0x51ED, 0x636E) }
        'Updated'           { @(0x66F4, 0x65B0, 0x65F6, 0x95F4) }
        'Reading'           { @(0x6B63, 0x5728, 0x8BFB, 0x53D6) }
        'Current'           { @(0x6570, 0x636E, 0x5DF2, 0x66F4, 0x65B0) }
        'Waiting'           { @(0x7B49, 0x5F85, 0x6570, 0x636E) }
        'ResetIn'           { @(0x540E, 0x91CD, 0x7F6E) }
        'Resetting'         { @(0x5373, 0x5C06, 0x91CD, 0x7F6E) }
        'ShowHide'          { @(0x663E, 0x793A, 0x002F, 0x9690, 0x85CF) }
        'ReadNow'           { @(0x7ACB, 0x5373, 0x91CD, 0x8BFB) }
        'AlwaysOnTop'       { @(0x59CB, 0x7EC8, 0x7F6E, 0x9876) }
        'UpdateCredentials' { @(0x66F4, 0x65B0, 0x51ED, 0x636E) }
        'RestartBackend'    { @(0x91CD, 0x542F, 0x540E, 0x7AEF) }
        'Exit'              { @(0x9000, 0x51FA) }
        'InvalidCredential' { @(0x8BF7, 0x586B, 0x5199, 0x5B8C, 0x6574, 0x7684, 0x51ED, 0x636E) }
        default             { @() }
    }
    return -join @($codes | ForEach-Object { [char]$_ })
}

function Show-TMCredentialDialog {
    param(
        [string]$WorkspaceId,
        [Windows.Window]$Owner
    )

    $dialog = ConvertFrom-TMXaml -Xaml $credentialXaml
    if ($null -ne $Owner -and $Owner.IsVisible) {
        $dialog.Owner = $Owner
        $dialog.WindowStartupLocation = 'CenterOwner'
    }
    $workspaceBox = $dialog.FindName('WorkspaceBox')
    $cookieBox = $dialog.FindName('CookieBox')
    $workspaceBox.Text = $WorkspaceId
    $holder = [PSCustomObject]@{ Value = $null }

    $dialog.FindName('CancelButton').Add_Click({ $dialog.DialogResult = $false })
    $dialog.FindName('SaveButton').Add_Click({
        $workspace = $workspaceBox.Text.Trim()
        $cookie = $cookieBox.Password.Trim()
        if ([string]::IsNullOrWhiteSpace($workspace) -or [string]::IsNullOrWhiteSpace($cookie)) {
            [Windows.MessageBox]::Show((Get-TMText 'InvalidCredential'), 'TokenMinister', 'OK', 'Warning') | Out-Null
            return
        }
        $holder.Value = [PSCustomObject]@{ WorkspaceId = $workspace; AuthCookie = $cookie }
        $dialog.DialogResult = $true
    })

    if ($dialog.ShowDialog() -eq $true) {
        return $holder.Value
    }
    return $null
}

function Test-TMSummaryAvailable {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $SummaryUri -TimeoutSec 1 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function ConvertTo-TMCountdown {
    param(
        [AllowNull()][string]$ResetAt,
        [AllowNull()][string]$Fallback
    )

    $parsed = [DateTimeOffset]::MinValue
    if (-not [string]::IsNullOrWhiteSpace($ResetAt) -and [DateTimeOffset]::TryParse($ResetAt, [ref]$parsed)) {
        $remaining = $parsed - [DateTimeOffset]::Now
        if ($remaining.TotalSeconds -le 0) {
            return Get-TMText 'Resetting'
        }
        if ($remaining.TotalDays -ge 1) {
            return ('{0}d {1}h' -f [Math]::Floor($remaining.TotalDays), $remaining.Hours)
        }
        if ($remaining.TotalHours -ge 1) {
            return ('{0}h {1}m' -f [Math]::Floor($remaining.TotalHours), $remaining.Minutes)
        }
        return ('{0}m' -f [Math]::Max(1, [Math]::Ceiling($remaining.TotalMinutes)))
    }
    if (-not [string]::IsNullOrWhiteSpace($Fallback)) {
        return $Fallback
    }
    return '--'
}

function Save-TMRuntimeSettings {
    param([switch]$Force)

    if ($null -eq $script:window -or (-not $Force -and -not $script:runtime.SettingsDirty)) {
        return
    }
    $script:settings.WindowLeft = [double]$script:window.Left
    $script:settings.WindowTop = [double]$script:window.Top
    $script:settings.WindowWidth = [double]$script:window.ActualWidth
    $script:settings.WindowHeight = [double]$script:window.ActualHeight
    $script:settings.AlwaysOnTop = [bool]$script:window.Topmost
    Save-TMSettings -Path $settingsPath -Settings $script:settings
    $script:runtime.SettingsDirty = $false
}

function Queue-TMRuntimeSettingsSave {
    $script:runtime.SettingsDirty = $true
    if ($null -eq $script:settingsSaveTimer) {
        return
    }
    $script:settingsSaveTimer.Stop()
    $script:settingsSaveTimer.Start()
}

function Set-TMWindowInVisibleArea {
    $screens = @([Windows.Forms.Screen]::AllScreens)
    $left = [double]$script:window.Left
    $top = [double]$script:window.Top
    $visible = $false
    foreach ($screen in $screens) {
        $area = $screen.WorkingArea
        if ($left + 48 -gt $area.Left -and $left -lt $area.Right - 48 -and
            $top + 36 -gt $area.Top -and $top -lt $area.Bottom - 36) {
            $visible = $true
            break
        }
    }
    if (-not $visible) {
        $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $script:window.Left = $area.Right - $script:window.Width - 24
        $script:window.Top = $area.Top + 24
        Queue-TMRuntimeSettingsSave
    }
}

function Update-TMRow {
    param(
        [Parameter(Mandatory = $true)][string]$Prefix,
        [AllowNull()]$Item
    )

    $percentText = $script:window.FindName($Prefix + 'Percent')
    $progress = $script:window.FindName($Prefix + 'Progress')
    $resetText = $script:window.FindName($Prefix + 'Reset')
    if ($null -eq $Item) {
        $percentText.Text = '--'
        $percentText.FontSize = 15
        $progress.Value = 0
        $progress.Visibility = 'Hidden'
        $resetText.Text = Get-TMText 'Waiting'
        return
    }
    if ($null -eq $Item.RemainingPercent) {
        $percentText.Text = Get-TMText 'Unavailable'
        $percentText.FontSize = 10.5
        $progress.Value = 0
        $progress.Visibility = 'Hidden'
        $resetText.Text = '--'
        return
    }
    $percentText.FontSize = 15
    $progress.Visibility = 'Visible'
    $rounded = [Math]::Round([double]$Item.RemainingPercent, 1)
    $percentText.Text = ('{0:g}%' -f $rounded)
    $progress.Value = $rounded
    $countdown = ConvertTo-TMCountdown -ResetAt $Item.ResetAt -Fallback $Item.TimeUntilReset
    $resetText.Text = ('{0} {1}' -f $countdown, (Get-TMText 'ResetIn'))
}

function Update-TMWindow {
    $items = @($script:runtime.State.Items)
    Update-TMRow -Prefix 'Five' -Item ($items | Where-Object Key -eq 'five_hour' | Select-Object -First 1)
    Update-TMRow -Prefix 'Weekly' -Item ($items | Where-Object Key -eq 'weekly' | Select-Object -First 1)
    Update-TMRow -Prefix 'Monthly' -Item ($items | Where-Object Key -eq 'monthly' | Select-Object -First 1)

    $freshness = Get-TMFreshnessView -State $script:runtime.State
    $script:freshnessText.Text = $freshness.RelativeText
    $script:freshnessPanel.ToolTip = $freshness.ToolTip
    switch ($freshness.Kind) {
        'Fresh' {
            $script:freshnessDot.Fill = $script:freshBrush
            $script:freshnessText.Foreground = $script:secondaryBrush
        }
        'Stale' {
            $script:freshnessDot.Fill = $script:staleBrush
            $script:freshnessText.Foreground = $script:staleBrush
        }
        default {
            $script:freshnessDot.Fill = $script:waitingBrush
            $script:freshnessText.Foreground = $script:secondaryBrush
        }
    }
}

function Invoke-TMRefresh {
    if ($script:runtime.IsRefreshing) {
        return
    }
    $script:runtime.IsRefreshing = $true
    try {
        $script:runtime.State = Update-TMQuotaState -State $script:runtime.State -Fetcher {
            Get-TMQuotaSnapshot -Uri $SummaryUri -TimeoutSeconds 3
        }
        Update-TMWindow
        Set-TMWindowInVisibleArea
    }
    finally {
        $script:runtime.IsRefreshing = $false
    }
}

function Get-TMCookie {
    return Get-TMSecret -Path $secretPath
}

function Start-TMBackendIfNeeded {
    if (Test-TMSummaryAvailable) {
        return
    }
    if (-not (Test-Path -LiteralPath $BackendPath)) {
        throw ('onWatch binary was not found: {0}' -f $BackendPath)
    }
    Start-TMOnWatchBackend -BinaryPath $BackendPath -WorkspaceId $script:settings.WorkspaceId `
        -AuthCookie (Get-TMCookie) -DatabasePath $databasePath | Out-Null
}

function Restart-TMRuntimeBackend {
    Restart-TMOnWatchBackend -BinaryPath $BackendPath -WorkspaceId $script:settings.WorkspaceId `
        -AuthCookie (Get-TMCookie) -DatabasePath $databasePath | Out-Null
    $script:runtime.State = New-TMQuotaState
    Start-Sleep -Milliseconds 500
    Invoke-TMRefresh
}

function Update-TMPinButton {
    if ([bool]$script:window.Topmost) {
        $script:pinButton.Foreground = $script:accentBrush
        $script:pinButton.Background = $script:accentSoftBrush
    }
    else {
        $script:pinButton.Foreground = $script:secondaryBrush
        $script:pinButton.Background = [Windows.Media.Brushes]::Transparent
    }
}

function Set-TMWindowVisibility {
    if ($script:window.IsVisible) {
        Save-TMRuntimeSettings -Force
        $script:window.Hide()
    }
    else {
        Set-TMWindowInVisibleArea
        $script:window.Show()
        $script:window.Activate() | Out-Null
    }
}

$validationWindow = ConvertFrom-TMXaml -Xaml $mainXaml
$validationDialog = ConvertFrom-TMXaml -Xaml $credentialXaml
if ($ValidateOnly -or $ValidateHideLifecycle) {
    $requiredControls = @(
        'DragArea', 'HeaderIcon', 'FreshnessPanel', 'FreshnessDot', 'FreshnessText', 'HideButton',
        'RefreshButton', 'PinButton',
        'FiveLabel', 'FiveReset', 'FivePercent', 'FiveProgress',
        'WeeklyLabel', 'WeeklyReset', 'WeeklyPercent', 'WeeklyProgress',
        'MonthlyLabel', 'MonthlyReset', 'MonthlyPercent', 'MonthlyProgress'
    )
    foreach ($name in $requiredControls) {
        if ($null -eq $validationWindow.FindName($name)) {
            throw ('Missing WPF control: {0}' -f $name)
        }
    }
    if ($null -eq $validationDialog.FindName('CookieBox')) {
        throw 'Missing credential dialog controls.'
    }
    $layoutSizes = @(
        @{ Width = 192; Height = 108 },
        @{ Width = 208; Height = 118 },
        @{ Width = 420; Height = 240 }
    )
    foreach ($layoutSize in $layoutSizes) {
        $validationWindow.Width = $layoutSize.Width
        $validationWindow.Height = $layoutSize.Height
        $availableSize = New-Object Windows.Size($layoutSize.Width, $layoutSize.Height)
        $validationWindow.Content.Measure($availableSize)
        $validationWindow.Content.Arrange((New-Object Windows.Rect(0, 0, $layoutSize.Width, $layoutSize.Height)))
        $validationWindow.Content.UpdateLayout()
        foreach ($prefix in @('Five', 'Weekly', 'Monthly')) {
            foreach ($suffix in @('Label', 'Reset', 'Percent', 'Progress')) {
                $control = $validationWindow.FindName($prefix + $suffix)
                if ($control.ActualWidth -le 0 -or $control.ActualHeight -le 0) {
                    throw ('WPF layout failed at {0}x{1}: {2}{3}' -f $layoutSize.Width, $layoutSize.Height, $prefix, $suffix)
                }
            }
        }
    }
    if ($ValidateHideLifecycle) {
        [void]$validationDialog.Close()
        $validationWindow.Opacity = 0
        $validationWindow.ShowActivated = $false
        $validationWindow.Left = -32000
        $validationWindow.Top = -32000
        $probe = [PSCustomObject]@{ AliveAfterHide = $false }
        $hideTimer = New-Object Windows.Threading.DispatcherTimer
        $hideTimer.Interval = [TimeSpan]::FromMilliseconds(40)
        $hideTimer.Add_Tick({
            $hideTimer.Stop()
            $validationWindow.Hide()
        })
        $verifyTimer = New-Object Windows.Threading.DispatcherTimer
        $verifyTimer.Interval = [TimeSpan]::FromMilliseconds(120)
        $verifyTimer.Add_Tick({
            $verifyTimer.Stop()
            $probe.AliveAfterHide = $true
            $validationWindow.Close()
            $validationWindow.Dispatcher.InvokeShutdown()
        })
        $hideTimer.Start()
        $verifyTimer.Start()
        Start-TMWindowMessageLoop -Window $validationWindow
        $hideTimer.Stop()
        $verifyTimer.Stop()
        if (-not $probe.AliveAfterHide) {
            [void]$validationWindow.Close()
            throw 'TokenMinister hide lifecycle ended when the window was hidden.'
        }
        Write-Output 'TokenMinister hide lifecycle is valid.'
        return
    }

    $chrome = [Windows.Shell.WindowChrome]::GetWindowChrome($validationWindow)
    $result = [PSCustomObject]@{
        Message                   = 'TokenMinister WPF resources are valid.'
        Width                     = 208
        Height                    = 118
        MinWidth                  = $validationWindow.MinWidth
        MinHeight                 = $validationWindow.MinHeight
        ResizeMode                = $validationWindow.ResizeMode
        ResizeBorderThickness     = $chrome.ResizeBorderThickness.Left
        CaptionHeight             = $chrome.CaptionHeight
        LayoutSizesValidated      = $layoutSizes.Count
    }
    [void]$validationWindow.Close()
    [void]$validationDialog.Close()
    Write-Output $result
    return
}
$validationWindow.Close()
$validationDialog.Close()

$instanceLock = New-TMSingleInstanceLock
if (-not $instanceLock.Acquired) {
    Close-TMSingleInstanceLock -Lock $instanceLock
    return
}

$script:window = $null
$script:notifyIcon = $null
$script:appIcon = $null
$script:refreshTimer = $null
$script:settingsSaveTimer = $null
$script:runtime = [PSCustomObject]@{
    State         = New-TMQuotaState
    IsRefreshing  = $false
    SettingsDirty = $false
    Exiting       = $false
}

try {
    if (-not (Test-Path -LiteralPath $DataRoot)) {
        [void][IO.Directory]::CreateDirectory($DataRoot)
    }
    $script:settings = Read-TMSettings -Path $settingsPath
    $needsCredentials = [string]::IsNullOrWhiteSpace($script:settings.WorkspaceId) -or -not (Test-Path -LiteralPath $secretPath)
    if (-not $needsCredentials) {
        try { [void](Get-TMCookie) } catch { $needsCredentials = $true }
    }
    if ($needsCredentials) {
        $credentials = Show-TMCredentialDialog -WorkspaceId $script:settings.WorkspaceId
        if ($null -eq $credentials) {
            return
        }
        $script:settings.WorkspaceId = $credentials.WorkspaceId
        Save-TMSettings -Path $settingsPath -Settings $script:settings
        Save-TMSecret -Path $secretPath -PlainText $credentials.AuthCookie
    }

    $script:window = ConvertFrom-TMXaml -Xaml $mainXaml
    $script:freshnessPanel = $script:window.FindName('FreshnessPanel')
    $script:freshnessDot = $script:window.FindName('FreshnessDot')
    $script:freshnessText = $script:window.FindName('FreshnessText')
    $script:refreshButton = $script:window.FindName('RefreshButton')
    $script:pinButton = $script:window.FindName('PinButton')
    $brushConverter = New-Object Windows.Media.BrushConverter
    $script:freshBrush = $brushConverter.ConvertFromString('#2BA471')
    $script:staleBrush = $brushConverter.ConvertFromString('#D7952B')
    $script:waitingBrush = $brushConverter.ConvertFromString('#A0A8B8')
    $script:secondaryBrush = $brushConverter.ConvertFromString('#7A8496')
    $script:accentBrush = $brushConverter.ConvertFromString('#3478F6')
    $script:accentSoftBrush = $brushConverter.ConvertFromString('#1A3478F6')

    $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $windowSize = Resolve-TMWindowSize -Settings $script:settings -WorkingArea $area
    $script:window.Width = $windowSize.Width
    $script:window.Height = $windowSize.Height
    $script:window.Topmost = [bool]$script:settings.AlwaysOnTop
    Update-TMPinButton

    $script:settingsSaveTimer = New-Object Windows.Threading.DispatcherTimer
    $script:settingsSaveTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:settingsSaveTimer.Add_Tick({
        $script:settingsSaveTimer.Stop()
        Save-TMRuntimeSettings
    })

    $script:window.Add_Loaded({
        $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $position = Get-TMCenteredWindowPosition -WorkingArea $area `
            -WindowWidth $script:window.ActualWidth -WindowHeight $script:window.ActualHeight
        $script:window.Left = $position.Left
        $script:window.Top = $position.Top
        Queue-TMRuntimeSettingsSave
        Set-TMWindowInVisibleArea
    })
    $script:window.Add_LocationChanged({ Queue-TMRuntimeSettingsSave })
    $script:window.Add_SizeChanged({ Queue-TMRuntimeSettingsSave })
    $script:window.FindName('DragArea').Add_MouseLeftButtonDown({
        try { $script:window.DragMove() } catch { }
    })
    $script:window.FindName('HideButton').Add_Click({ Set-TMWindowVisibility })
    $script:refreshButton.Add_Click({
        $script:refreshButton.IsEnabled = $false
        try {
            Invoke-TMRefresh
        }
        finally {
            $script:refreshButton.IsEnabled = $true
        }
    })
    $script:pinButton.Add_Click({
        $script:window.Topmost = -not [bool]$script:window.Topmost
        $script:settings.AlwaysOnTop = [bool]$script:window.Topmost
        $topmostItem.Checked = [bool]$script:window.Topmost
        Update-TMPinButton
        $script:runtime.SettingsDirty = $true
        Save-TMRuntimeSettings -Force
    })
    $script:window.Add_Closing({
        param($sender, $eventArgs)
        if (-not $script:runtime.Exiting) {
            $eventArgs.Cancel = $true
            Set-TMWindowVisibility
        }
    })

    $script:notifyIcon = New-Object Windows.Forms.NotifyIcon
    $appIconPath = Join-Path $PSScriptRoot 'TokenMinister.ico'
    if (Test-Path -LiteralPath $appIconPath) {
        $script:appIcon = New-Object Drawing.Icon($appIconPath)
        $script:notifyIcon.Icon = $script:appIcon
        $iconUri = New-Object Uri($appIconPath)
        $iconFrame = [Windows.Media.Imaging.BitmapFrame]::Create($iconUri)
        $script:window.Icon = $iconFrame
        $script:window.FindName('HeaderIcon').Source = $iconFrame
    }
    else {
        $script:notifyIcon.Icon = [Drawing.SystemIcons]::Information
    }
    $script:notifyIcon.Text = 'TokenMinister - OpenCode Go'
    $script:notifyIcon.Visible = $true
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $showItem = $menu.Items.Add((Get-TMText 'ShowHide'))
    $readItem = $menu.Items.Add((Get-TMText 'ReadNow'))
    $topmostItem = $menu.Items.Add((Get-TMText 'AlwaysOnTop'))
    $topmostItem.CheckOnClick = $true
    $topmostItem.Checked = [bool]$script:settings.AlwaysOnTop
    $credentialItem = $menu.Items.Add((Get-TMText 'UpdateCredentials'))
    $restartItem = $menu.Items.Add((Get-TMText 'RestartBackend'))
    [void]$menu.Items.Add('-')
    $exitItem = $menu.Items.Add((Get-TMText 'Exit'))
    $script:notifyIcon.ContextMenuStrip = $menu

    $showItem.Add_Click({ Set-TMWindowVisibility })
    $script:notifyIcon.Add_DoubleClick({ Set-TMWindowVisibility })
    $readItem.Add_Click({ Invoke-TMRefresh })
    $topmostItem.Add_Click({
        $script:settings.AlwaysOnTop = [bool]$topmostItem.Checked
        $script:window.Topmost = [bool]$topmostItem.Checked
        Update-TMPinButton
        $script:runtime.SettingsDirty = $true
        Save-TMRuntimeSettings -Force
    })
    $credentialItem.Add_Click({
        $credentials = Show-TMCredentialDialog -WorkspaceId $script:settings.WorkspaceId -Owner $script:window
        if ($null -ne $credentials) {
            $script:settings.WorkspaceId = $credentials.WorkspaceId
            Save-TMSettings -Path $settingsPath -Settings $script:settings
            Save-TMSecret -Path $secretPath -PlainText $credentials.AuthCookie
            Restart-TMRuntimeBackend
        }
    })
    $restartItem.Add_Click({
        try {
            Restart-TMRuntimeBackend
        }
        catch {
            $script:runtime.State.ErrorMessage = $_.Exception.Message
            Update-TMWindow
        }
    })
    $exitItem.Add_Click({
        $script:runtime.Exiting = $true
        Save-TMRuntimeSettings -Force
        $script:window.Close()
        $script:window.Dispatcher.InvokeShutdown()
    })

    $script:refreshTimer = New-Object Windows.Threading.DispatcherTimer
    $script:refreshTimer.Interval = [TimeSpan]::FromSeconds(30)
    $script:refreshTimer.Add_Tick({ Invoke-TMRefresh })
    $script:refreshTimer.Start()

    try {
        Start-TMBackendIfNeeded
    }
    catch {
        $script:runtime.State.ErrorMessage = $_.Exception.Message
    }
    Invoke-TMRefresh
    Start-TMWindowMessageLoop -Window $script:window
}
finally {
    if ($null -ne $script:refreshTimer) { $script:refreshTimer.Stop() }
    if ($null -ne $script:settingsSaveTimer) { $script:settingsSaveTimer.Stop() }
    if ($null -ne $script:window) {
        try { Save-TMRuntimeSettings -Force } catch { }
    }
    if ($null -ne $script:notifyIcon) {
        $script:notifyIcon.Visible = $false
        $script:notifyIcon.Dispose()
    }
    if ($null -ne $script:appIcon) { $script:appIcon.Dispose() }
    Close-TMSingleInstanceLock -Lock $instanceLock
}
