$ErrorActionPreference = 'Stop'

Describe 'TokenMinister WPF resources' {
    It 'loads the compact resizable widget and credential XAML without showing a window' {
        $entry = Join-Path $PSScriptRoot '..\src\TokenMinister.ps1'
        $result = & $entry -ValidateOnly

        $result.Message | Should Match 'WPF resources are valid'
        $result.Width | Should Be 208
        $result.Height | Should Be 118
        $result.MinWidth | Should Be 192
        $result.MinHeight | Should Be 108
        $result.ResizeMode.ToString() | Should Be 'CanResize'
        $result.ResizeBorderThickness | Should Be 6
        $result.CaptionHeight | Should Be 0
        $result.LayoutSizesValidated | Should Be 3
    }

    It 'keeps the dispatcher alive after the main window is hidden' {
        $entry = Join-Path $PSScriptRoot '..\src\TokenMinister.ps1'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File $entry -ValidateHideLifecycle

        $LASTEXITCODE | Should Be 0
        ($output -join '') | Should Match 'hide lifecycle is valid'
    }
}
