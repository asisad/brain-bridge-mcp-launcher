#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SmokeTest,[string]$PreviewPath,[ValidateSet('fa','en')][string]$Language='fa')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
. (Join-Path $PSScriptRoot 'BrainBridge.Help.ps1')
$script:packageRoot=$PSScriptRoot
$script:installRoot=Join-Path $env:LOCALAPPDATA 'BrainBridge'
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="840" Height="710" ResizeMode="CanMinimize" WindowStyle="SingleBorderWindow" WindowStartupLocation="CenterScreen" Background="#EDF3F7" Foreground="#193548" FontFamily="Segoe UI" FontSize="14">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="10,5"/><Setter Property="Background" Value="#EAF3F7"/><Setter Property="Foreground" Value="#15536A"/><Setter Property="BorderBrush" Value="#CADDE6"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="Chrome" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="7" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Chrome" Property="Opacity" Value="0.85"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Chrome" Property="BorderBrush" Value="#087FA4"/><Setter TargetName="Chrome" Property="BorderThickness" Value="2"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Chrome" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  <Style TargetType="TextBox"><Setter Property="Padding" Value="5"/><Setter Property="Background" Value="#FAFCFE"/><Setter Property="BorderBrush" Value="#BCD0DC"/><Setter Property="FlowDirection" Value="LeftToRight"/><Setter Property="TextAlignment" Value="Left"/></Style>
  <Style TargetType="PasswordBox"><Setter Property="Padding" Value="5"/><Setter Property="Background" Value="#FAFCFE"/><Setter Property="BorderBrush" Value="#BCD0DC"/><Setter Property="FlowDirection" Value="LeftToRight"/></Style>
 </Window.Resources>
 <Grid Background="#EDF3F7"><StackPanel x:Name="Page" Margin="12">
  <Border Background="#153E55" CornerRadius="12" Padding="8" Margin="0,0,0,6"><StackPanel>
   <DockPanel FlowDirection="LeftToRight"><StackPanel Orientation="Horizontal" DockPanel.Dock="Right" Margin="10,0,0,0"><Button x:Name="MinimizeWindow" Content="−" Width="35" Height="32" FontSize="20" Margin="0,0,5,0"/><Button x:Name="CloseWindow" Content="×" Width="35" Height="32" FontSize="20" Background="#FBE5E1" Foreground="#8A302C"/></StackPanel><Button x:Name="HelpGuide" DockPanel.Dock="Right" Margin="8,0,0,0" VerticalAlignment="Center"/><ComboBox x:Name="LanguageChoice" DockPanel.Dock="Right" Width="120" Height="32" FontSize="14" AutomationProperties.Name="Language / زبان"><ComboBoxItem Content="فارسی" Tag="fa"/><ComboBoxItem Content="English" Tag="en"/></ComboBox><StackPanel Orientation="Horizontal"><Border Background="#2C6578" CornerRadius="8" Padding="9" Margin="0,0,12,0"><Path Stroke="#72DECE" StrokeThickness="2.5" Width="24" Height="24" Stretch="Uniform" Data="M 1,20 L 1,4 M 23,20 L 23,4 M 1,8 C 6,19 18,19 23,8 M 1,20 L 23,20 M 8,14 L 8,20 M 16,14 L 16,20"/></Border><TextBlock Text="Brain Bridge" Foreground="White" FontSize="23" FontWeight="SemiBold" VerticalAlignment="Center"/></StackPanel></DockPanel>
   <TextBlock x:Name="Subtitle" Visibility="Collapsed" Foreground="#D9EEF1" Margin="0,13,0,4" FontSize="16"/>
   <TextBlock x:Name="Badge" Visibility="Collapsed" Foreground="#87DBCD" FontSize="11"/>
  </StackPanel></Border>
  <TextBlock x:Name="Intro" Visibility="Collapsed" TextWrapping="Wrap" Margin="4,0,4,12"/>

  <Border Background="White" BorderBrush="#D6E4EC" BorderThickness="1" CornerRadius="12" Padding="8" Margin="0,0,0,6"><StackPanel>
   <StackPanel Orientation="Horizontal" Margin="0,0,0,3"><TextBlock Text="⇄" FontSize="21" Foreground="#128D99" Margin="0,0,9,0"/><TextBlock x:Name="ConnectionHeading" FontWeight="SemiBold" FontSize="15" VerticalAlignment="Center"/></StackPanel>
   <DockPanel><Button x:Name="DownloadClient" DockPanel.Dock="Right"/><TextBlock x:Name="ClientLabel" VerticalAlignment="Center"/></DockPanel>
   <DockPanel Margin="0,4,0,7"><Button x:Name="Browse" DockPanel.Dock="Right" MinWidth="105" Margin="8,0,0,0"/><TextBox x:Name="Client"/></DockPanel>
   <TextBlock x:Name="DownloadHint" Visibility="Collapsed" TextWrapping="Wrap" FontSize="12" Foreground="#526C7C" Margin="0,0,0,12"/>
   <DockPanel><Button x:Name="OpenTunnels" DockPanel.Dock="Right"/><TextBlock x:Name="TunnelLabel" VerticalAlignment="Center"/></DockPanel><TextBox x:Name="Tunnel" Margin="0,4,0,7"/>
   <TextBlock x:Name="TunnelHint" Visibility="Collapsed" TextWrapping="Wrap" FontSize="12" Foreground="#526C7C" Margin="0,0,0,12"/>
   <TextBlock x:Name="UrlLabel"/><TextBox x:Name="Url" Text="http://127.0.0.1:27200/mcp" Margin="0,4,0,0"/>
  </StackPanel></Border>
  <Border Background="#F1FAF8" BorderBrush="#C5E4DF" BorderThickness="1" CornerRadius="12" Padding="8" Margin="0,0,0,6"><StackPanel>
   <StackPanel Orientation="Horizontal" Margin="0,0,0,3"><Path Stroke="#168D81" StrokeThickness="2" Width="18" Height="21" Stretch="Uniform" Data="M 4,9 L 4,5 C 4,-1 16,-1 16,5 L 16,9 M 1,9 L 19,9 L 19,23 L 1,23 Z M 10,14 L 10,18" Margin="0,0,10,0"/><TextBlock x:Name="SecretsHeading" FontWeight="SemiBold" FontSize="15"/></StackPanel>
   <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="16"/><ColumnDefinition/></Grid.ColumnDefinitions><StackPanel><TextBlock x:Name="RuntimeLabel" TextWrapping="Wrap"/><PasswordBox x:Name="Runtime" Margin="0,4,0,5"/><Button x:Name="OpenKeys" HorizontalAlignment="Left"/></StackPanel><StackPanel Grid.Column="2"><TextBlock x:Name="TokenLabel" TextWrapping="Wrap"/><PasswordBox x:Name="Token" Margin="0,4,0,0"/></StackPanel></Grid>
  </StackPanel></Border>
  <CheckBox x:Name="Trust" Margin="2,0,0,5"/><CheckBox x:Name="AutoStart" Margin="2,0,0,8"/>
  <WrapPanel><Button x:Name="Install" Background="#087F8C" Foreground="White" BorderBrush="#087F8C" FontWeight="SemiBold" Margin="0,0,7,7"/><Button x:Name="Test" Margin="0,0,7,7"/><Button x:Name="Start" Margin="0,0,7,7"/><Button x:Name="Refresh" Margin="0,0,7,7"/><Button x:Name="Stop" Margin="0,0,7,7"/><Button x:Name="Remove" Background="#FBF0EE" Foreground="#904A3A" BorderBrush="#EACFC7" Margin="0,0,7,7"/></WrapPanel>
  <Border Background="#E1EDF5" BorderBrush="#C9DBE8" BorderThickness="1" CornerRadius="10" Padding="9" Margin="0,1,0,0"><StackPanel><TextBlock x:Name="StatusLabel" FontWeight="SemiBold" Foreground="#275777" Margin="0,0,0,5"/><TextBlock x:Name="Status" TextWrapping="Wrap" FontSize="12" MaxHeight="66" TextTrimming="CharacterEllipsis"/></StackPanel></Border>
  <TextBlock x:Name="Privacy" Visibility="Collapsed" FontSize="12" Foreground="#526C7C" TextWrapping="Wrap"/>
 </StackPanel></Grid>
</Window>
'@
$reader=New-Object Xml.XmlNodeReader $xaml
$window=[Windows.Markup.XamlReader]::Load($reader)
foreach ($name in @('Client','Tunnel','Url','Runtime','Token','Trust','AutoStart','Browse','Test','Install','Start','Refresh','Stop','Remove','Status','DownloadClient','OpenTunnels','OpenKeys','HelpGuide')) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }
$window.FindName('MinimizeWindow').Add_Click({ $window.WindowState='Minimized' })
$window.FindName('CloseWindow').Add_Click({ $window.Close() })
$script:translations=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'strings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:currentLanguage=$Language
$script:statusSource='Ready to configure. No credentials are loaded into this form.'
function Get-UiText([string]$Key) { return $script:translations.$script:currentLanguage.labels.$Key }
function Set-GuiStatus([string]$Message) {
  $script:statusSource=$Message
  $Status.Text=(@($Message -split '\r?\n' | Where-Object { $_.Trim() } | ForEach-Object {
    $entry=$script:translations.$script:currentLanguage.messages.PSObject.Properties[$_.Trim()]
    if ($entry) { $entry.Value } else { $script:translations.$script:currentLanguage.messages.'Action failed. No diagnostic containing credentials was saved.' }
  }) -join "`n")
  $Status.ToolTip=$Status.Text
}
function Set-GuiLanguage([string]$Value) {
  $script:currentLanguage=$Value
  $window.FlowDirection=if ($Value -eq 'fa') { 'RightToLeft' } else { 'LeftToRight' }
  $window.Title=Get-UiText 'Title'
  foreach ($property in $script:translations.$Value.labels.PSObject.Properties) {
    $control=$window.FindName($property.Name)
    if ($control -is [Windows.Controls.TextBlock]) { $control.Text=$property.Value }
    elseif ($control -is [Windows.Controls.ContentControl]) { $control.Content=$property.Value }
  }
  $window.FindName('CloseWindow').ToolTip=Get-UiText 'CloseTip'
  $window.FindName('MinimizeWindow').ToolTip=Get-UiText 'MinimizeTip'
  $Client.ToolTip=Get-UiText 'DownloadHint'
  $Tunnel.ToolTip=Get-UiText 'TunnelHint'
  Set-GuiStatus $script:statusSource
  $window.Content.InvalidateMeasure()
  $window.Content.InvalidateArrange()
  $window.Content.UpdateLayout()
}
$languageChoice=$window.FindName('LanguageChoice')
$languageChoice.SelectedIndex=if ($Language -eq 'fa') { 0 } else { 1 }
$languageChoice.Add_SelectionChanged({ Set-GuiLanguage ([string]$languageChoice.SelectedItem.Tag) })
Set-GuiLanguage $Language
function Confirm-GuiRemoval([switch]$InspectOnly) {
  $dialog=New-Object Windows.Window
  $dialog.Title=Get-UiText 'ConfirmTitle'; $dialog.Width=480; $dialog.SizeToContent='Height'
  if (-not $InspectOnly) { $dialog.Owner=$window }
  $dialog.WindowStartupLocation='CenterOwner'; $dialog.ResizeMode='NoResize'
  $dialog.FlowDirection=$window.FlowDirection
  $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='22'
  $text=New-Object Windows.Controls.TextBlock; $text.Text=Get-UiText 'ConfirmBody'; $text.TextWrapping='Wrap'; $text.FontSize=15
  $panel.Children.Add($text) | Out-Null
  $buttonsPanel=New-Object Windows.Controls.StackPanel; $buttonsPanel.Orientation='Horizontal'; $buttonsPanel.Margin='0,18,0,0'
  $yes=New-Object Windows.Controls.Button; $yes.Content=Get-UiText 'ConfirmYes'; $yes.Padding='16,8'; $yes.Margin='0,0,10,0'
  $no=New-Object Windows.Controls.Button; $no.Content=Get-UiText 'ConfirmNo'; $no.Padding='16,8'; $no.IsCancel=$true; $no.IsDefault=$true
  $yes.Add_Click({ $dialog.DialogResult=$true }); $no.Add_Click({ $dialog.DialogResult=$false })
  $buttonsPanel.Children.Add($no) | Out-Null; $buttonsPanel.Children.Add($yes) | Out-Null
  $panel.Children.Add($buttonsPanel) | Out-Null; $dialog.Content=$panel
  if ($InspectOnly) { return $dialog }
  return $dialog.ShowDialog()
}
function Show-GuiResource([string]$Key) {
  try { $script:lastHelpDestination=Open-BrainBridgeResource $Key -Language $script:currentLanguage -ResolveOnly:$SmokeTest }
  catch { Set-GuiStatus 'Help could not be opened. Check the complete package and your default browser.' }
}
$DownloadClient.Add_Click({ Show-GuiResource 'download' })
$OpenTunnels.Add_Click({ Show-GuiResource 'tunnels' })
$OpenKeys.Add_Click({ Show-GuiResource 'keys' })
$HelpGuide.Add_Click({ Show-GuiResource 'guide' })
$script:worker=$null
$script:handle=$null
$script:busy=$false
$script:buttons=@($Browse,$Test,$Install,$Start,$Refresh,$Stop,$Remove)
$existing=Join-Path $installRoot 'config.json'
if (-not $SmokeTest -and (Test-Path -LiteralPath $existing)) {
  try {
    $c=Get-Content -LiteralPath $existing -Raw | ConvertFrom-Json
    $Client.Text=$c.tunnel_client_exe; $Tunnel.Text=$c.tunnel_id; $Url.Text=$c.mcp_url
    $AutoStart.IsChecked=Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Startup')) 'Brain Bridge.lnk')
  } catch { Set-GuiStatus 'Saved settings could not be read.' }
}
function Start-GuiWork([string]$Action) {
  if ($script:busy) { return }
  $config=@{tunnel_client_exe=$Client.Text.Trim();tunnel_id=$Tunnel.Text.Trim();mcp_url=$Url.Text.Trim()}
  if ($Action -in @('test','install')) {
    try {
      $null=Assert-BrainBridgeConfig $config.tunnel_client_exe $config.tunnel_id $config.mcp_url
      if (-not $Trust.IsChecked) { throw 'Confirm the downloaded ZIP checksum against the official release first.' }
      if (-not $Runtime.SecurePassword.Length -or -not $Token.SecurePassword.Length) { throw 'Enter both credentials. Saved secrets are not prefilled.' }
    } catch { Set-GuiStatus $_.Exception.Message; return }
  }
  $script:runtimeCopy=$Runtime.SecurePassword
  $script:tokenCopy=$Token.SecurePassword
  $Runtime.Clear(); $Token.Clear()
  $script:worker=[PowerShell]::Create()
  $code={param($action,$package,$root,$config,$runtime,$token,$autoStart)
    $ErrorActionPreference='Stop'
    . (Join-Path $package 'BrainBridge.Core.ps1')
    switch ($action) {
      'test' { Test-BrainBridgeConnection $config $runtime $token }
      'install' {
        & (Join-Path $package 'Install-BrainBridge.ps1') -InstallRoot $root -TunnelClientPath $config.tunnel_client_exe -TunnelId $config.tunnel_id -McpUrl $config.mcp_url -RuntimeKey $runtime -ObsidianToken $token -EnableAutoStart:$autoStart
        'Installed. Use Start, then Refresh status.'
      }
      'start' {
        if (-not (Test-Path -LiteralPath (Join-Path $root 'config.json'))) { throw 'Not installed.' }
        if (Get-BrainBridgeRunner $root) { 'Runner is already active.'; return }
        $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $exe -ArgumentList ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $root 'Start-BrainBridge.ps1')+'"') -WindowStyle Hidden
        'Start requested. Refresh status in a few seconds.'
      }
      'refresh' { & (Join-Path $package 'Status-BrainBridge.ps1') -InstallRoot $root }
      'stop' { & (Join-Path $package 'Stop-BrainBridge.ps1') -InstallRoot $root }
      'remove' { & (Join-Path $package 'Remove-BrainBridge.ps1') -InstallRoot $root -RemoveLocalConfig -Confirm:$false }
    }
  }
  $null=$worker.AddScript($code.ToString()).AddArgument($Action).AddArgument($packageRoot).AddArgument($installRoot).AddArgument($config).AddArgument($runtimeCopy).AddArgument($tokenCopy).AddArgument([bool]$AutoStart.IsChecked)
  $script:busy=$true
  foreach ($button in $buttons) { $button.IsEnabled=$false }
  Set-GuiStatus 'Working… connection checks can take up to 70 seconds.'
  $script:handle=$worker.BeginInvoke()
}
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
  if ($script:busy -and $handle.IsCompleted) {
    try {
      $result=$worker.EndInvoke($handle)
      if ($worker.HadErrors) { Set-GuiStatus 'Action failed. Check URL, credentials, Read + Use permissions, executable and local server. Raw errors are hidden to protect secrets.' }
      else { Set-GuiStatus (($result | Out-String).Trim()) }
    } catch { Set-GuiStatus 'Action failed. No diagnostic containing credentials was saved.' }
    finally {
      $worker.Dispose(); $runtimeCopy.Dispose(); $tokenCopy.Dispose()
      $script:busy=$false
      foreach ($button in $buttons) { $button.IsEnabled=$true }
    }
  }
})
$Browse.Add_Click({
  $dialog=New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Title=Get-UiText 'Browse'; $dialog.Filter=Get-UiText 'FileFilter'; $dialog.CheckFileExists=$true
  if ($dialog.ShowDialog()) { $Client.Text=$dialog.FileName; $Trust.IsChecked=$false }
})
$Test.Add_Click({ Start-GuiWork 'test' }); $Install.Add_Click({ Start-GuiWork 'install' })
$Start.Add_Click({ Start-GuiWork 'start' }); $Refresh.Add_Click({ Start-GuiWork 'refresh' })
$Stop.Add_Click({ Start-GuiWork 'stop' })
$Remove.Add_Click({
  if (Confirm-GuiRemoval) { Start-GuiWork 'remove' }
})
$window.Add_Closing({param($sender,$eventArgs)
  if ($script:busy) { $eventArgs.Cancel=$true; Set-GuiStatus 'Wait for the current operation to finish before closing.' }
})
if ($SmokeTest) {
  if ($Runtime -isnot [Windows.Controls.PasswordBox] -or $Token -isnot [Windows.Controls.PasswordBox]) { throw 'Secret controls must be PasswordBox.' }
  $Client.Text='synthetic-path'; $Tunnel.Text='synthetic-id'; $Runtime.Password='ui-password-fixture'; $Token.Password='ui-token-fixture'; $AutoStart.IsChecked=$true
  foreach ($code in @('en','fa','en','fa')) {
    $languageChoice.SelectedIndex=if ($code -eq 'fa') { 0 } else { 1 }
    if ($script:currentLanguage -ne $code -or $Install.Content -ne $translations.$code.labels.Install) { throw 'Language selection failed.' }
    $direction=if ($code -eq 'fa') { 'RightToLeft' } else { 'LeftToRight' }
    if ($window.FlowDirection.ToString() -ne $direction) { throw 'Language flow mismatch.' }
    foreach ($field in @($Client,$Tunnel,$Url,$Runtime,$Token)) {
      if ($field.FlowDirection.ToString() -ne 'LeftToRight') { throw 'Technical input must remain LTR.' }
    }
    if ($Client.Text -ne 'synthetic-path' -or $Tunnel.Text -ne 'synthetic-id' -or $Runtime.Password -ne 'ui-password-fixture' -or $Token.Password -ne 'ui-token-fixture' -or -not $AutoStart.IsChecked) { throw 'Language switch changed inputs.' }
    Start-GuiWork 'test'
    if ($Status.Text -ne $translations.$code.messages.'Invalid Tunnel ID.' -or $script:busy) { throw 'Validation was not localized.' }
    foreach ($message in $translations.en.messages.PSObject.Properties) {
      Set-GuiStatus $message.Name
      if ($Status.Text -ne $translations.$code.messages.($message.Name)) { throw 'Status translation missing.' }
    }
    Set-GuiStatus 'untrusted-private-diagnostic'
    if ($Status.Text.Contains('untrusted-private-diagnostic')) { throw 'Unknown diagnostic was displayed.' }
    $confirmation=Confirm-GuiRemoval -InspectOnly
    if ($confirmation.Title -ne $translations.$code.labels.ConfirmTitle -or $confirmation.Content.Children[0].Text -ne $translations.$code.labels.ConfirmBody) { throw 'Confirmation localization failed.' }
    $confirmation.Close()
    foreach ($entry in @(@($DownloadClient,'download'),@($OpenTunnels,'tunnels'),@($OpenKeys,'keys'),@($HelpGuide,'guide'))) {
      $script:lastHelpDestination=$null
      $entry[0].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
      if ($lastHelpDestination -ne (Get-BrainBridgeResource $entry[1] -Language $code)) { throw 'Help button destination mismatch.' }
    }
    # Simulate a 1366x768 desktop at 100% scaling: 710px outer window,
    # 824x671 client area after allowing for the standard Windows frame.
    Set-GuiStatus "Installed: yes`nVerified runner active: True`nTunnel readiness: not confirmed`nRunner active; use Refresh status to check readiness`nLocal tunnel readiness endpoint: ready (not a remote ChatGPT test)"
    $layout=$window.Content
    $layout.Measure((New-Object Windows.Size(824,671))); $layout.Arrange((New-Object Windows.Rect(0,0,824,671))); $layout.UpdateLayout()
    $null=$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Render)
    foreach ($name in @('Client','Tunnel','Url','Runtime','Token','Trust','AutoStart','Install','Test','Start','Refresh','Stop','Remove','Status','LanguageChoice','HelpGuide','MinimizeWindow','CloseWindow')) {
      $control=$window.FindName($name)
      $bounds=$control.TransformToAncestor($layout).TransformBounds((New-Object Windows.Rect($control.RenderSize)))
      if ($bounds.Left -lt 0 -or $bounds.Top -lt 0 -or $bounds.Right -gt 824.5 -or $bounds.Bottom -gt 671.5) { throw ('Compact layout overflow: '+$name) }
    }
    if ($window.ResizeMode -ne 'CanMinimize' -or $window.WindowStyle -ne 'SingleBorderWindow' -or $window.Height -gt 728) { throw 'Standard window controls or desktop fit missing.' }
    if ($Status.ToolTip -ne $Status.Text) { throw 'Full status must be available without scrolling.' }
  }
  $Client.Clear(); $Tunnel.Clear(); $Runtime.Clear(); $Token.Clear(); $AutoStart.IsChecked=$false
  $languageChoice.SelectedIndex=if ($Language -eq 'fa') { 0 } else { 1 }
  Set-GuiStatus 'Ready to configure. No credentials are loaded into this form.'
  $visual=$window.Content
  $visual.Measure((New-Object Windows.Size(824,671))); $visual.Arrange((New-Object Windows.Rect(0,0,824,671))); $visual.UpdateLayout()
  $null=$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Render)
  if ($PreviewPath) {
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(824,671,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($PreviewPath)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
  }
  $window.FindName('MinimizeWindow').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  if ($window.WindowState -ne 'Minimized') { throw 'Minimize button failed.' }
  $window.WindowState='Normal'
  $script:closedByButton=$false
  $window.Add_Closed({ $script:closedByButton=$true })
  $window.FindName('CloseWindow').RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
  if (-not $script:closedByButton) { throw 'Close button failed.' }
  'PASS: bilingual compact layout fits 824x671 client area; minimize/close handlers, LTR inputs, translations and help destinations verified.'
  return
}
$timer.Start()
try { $null=$window.ShowDialog() } finally { $timer.Stop(); $Runtime.Clear(); $Token.Clear() }
