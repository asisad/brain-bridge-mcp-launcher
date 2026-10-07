#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SmokeTest,[string]$PreviewPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
. (Join-Path $PSScriptRoot 'BrainBridge.Help.ps1')
$script:packageRoot=$PSScriptRoot
$script:installRoot=Join-Path $env:LOCALAPPDATA 'BrainBridge'
[xml]$xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Brain Bridge — Windows prototype" Width="780" Height="850" MinWidth="680" MinHeight="680" WindowStartupLocation="CenterScreen" Background="#F3F5F8" FontFamily="Segoe UI" FontSize="14">
 <ScrollViewer VerticalScrollBarVisibility="Auto" Background="#F3F5F8"><StackPanel Margin="28">
  <TextBlock Text="Brain Bridge" FontSize="30" FontWeight="SemiBold" Foreground="#17374C"/>
  <TextBlock Text="Local MCP tunnel • community prototype 0.2" Margin="0,4,0,18" Foreground="#516575"/>
  <TextBlock Text="Connect your existing Obsidian MCP server. Keep Read/Search access only unless you intentionally need more tools." TextWrapping="Wrap" Margin="0,0,0,16"/>
  <DockPanel Margin="0,0,0,12"><Button x:Name="HelpGuide" Content="راهنمای تصویری فارسی" DockPanel.Dock="Right" Padding="12,7"/><TextBlock Text="لینک‌ها در مرورگر شما باز می‌شوند." VerticalAlignment="Center" FlowDirection="RightToLeft" Margin="0,0,12,0"/></DockPanel>
  <DockPanel><Button x:Name="DownloadClient" Content="دانلود کلاینت ویندوز ↗" DockPanel.Dock="Right" Padding="9,4"/><TextBlock Text="Official tunnel-client.exe" VerticalAlignment="Center"/></DockPanel>
  <DockPanel Margin="0,5,0,12"><Button x:Name="Browse" Content="Browse…" DockPanel.Dock="Right" Width="90" Margin="8,0,0,0"/><TextBox x:Name="Client" Padding="6"/></DockPanel>
  <TextBlock Text="فایل ZIP ویندوز را دانلود و استخراج کنید؛ سپس Browse را بزنید." FlowDirection="RightToLeft" TextWrapping="Wrap" FontSize="12" Foreground="#516575" Margin="0,0,0,12"/>
  <DockPanel><Button x:Name="OpenTunnels" Content="مدیریت تونل‌ها ↗" DockPanel.Dock="Right" Padding="9,4"/><TextBlock Text="Tunnel ID" VerticalAlignment="Center"/></DockPanel><TextBox x:Name="Tunnel" Padding="6" Margin="0,5,0,5"/>
  <TextBlock Text="شناسهٔ تونل خود را از ستون ID کپی و اینجا با Ctrl+V وارد کنید." FlowDirection="RightToLeft" TextWrapping="Wrap" FontSize="12" Foreground="#516575" Margin="0,0,0,12"/>
  <TextBlock Text="Direct Obsidian MCP URL (loopback /mcp)"/><TextBox x:Name="Url" Text="http://127.0.0.1:27200/mcp" Padding="6" Margin="0,5,0,12"/>
  <Grid Margin="0,0,0,12"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="16"/><ColumnDefinition/></Grid.ColumnDefinitions>
   <StackPanel><TextBlock Text="OpenAI Runtime key (Read + Use)"/><PasswordBox x:Name="Runtime" Padding="6" Margin="0,5,0,5"/><Button x:Name="OpenKeys" Content="دریافت کلید اجرا ↗" HorizontalAlignment="Left" Padding="9,4"/></StackPanel>
   <StackPanel Grid.Column="2"><TextBlock Text="Obsidian token (without Bearer)"/><PasswordBox x:Name="Token" Padding="6" Margin="0,5,0,0"/></StackPanel>
  </Grid>
  <CheckBox x:Name="Trust" Content="I verified the downloaded ZIP against the official release checksum." Margin="0,0,0,10"/>
  <CheckBox x:Name="AutoStart" Content="Start hidden when I sign into Windows" Margin="0,0,0,15"/>
  <WrapPanel><Button x:Name="Test" Content="Test connection" Padding="12,7" Margin="0,0,8,8"/><Button x:Name="Install" Content="Install / Save" Padding="12,7" Margin="0,0,8,8" Background="#DCEBF4"/><Button x:Name="Start" Content="Start" Padding="12,7" Margin="0,0,8,8"/><Button x:Name="Refresh" Content="Refresh status" Padding="12,7" Margin="0,0,8,8"/><Button x:Name="Stop" Content="Stop" Padding="12,7" Margin="0,0,8,8"/><Button x:Name="Remove" Content="Uninstall" Padding="12,7" Margin="0,0,8,8"/></WrapPanel>
  <Border Background="White" CornerRadius="6" Padding="12" Margin="0,6,0,12"><TextBlock x:Name="Status" Text="Ready to configure. No credentials are loaded into this form." TextWrapping="Wrap" MinHeight="56"/></Border>
  <TextBlock Text="Secrets are encrypted with Windows DPAPI for this Windows account. They are available in memory while connecting. A running process is not proof of remote connectivity. No vault content is collected by this installer." FontSize="12" Foreground="#516575" TextWrapping="Wrap"/>
 </StackPanel></ScrollViewer>
</Window>
'@
$reader=New-Object Xml.XmlNodeReader $xaml
$window=[Windows.Markup.XamlReader]::Load($reader)
foreach ($name in @('Client','Tunnel','Url','Runtime','Token','Trust','AutoStart','Browse','Test','Install','Start','Refresh','Stop','Remove','Status','DownloadClient','OpenTunnels','OpenKeys','HelpGuide')) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }
function Show-GuiResource([string]$Key) {
  try { $script:lastHelpDestination=Open-BrainBridgeResource $Key -ResolveOnly:$SmokeTest }
  catch { $Status.Text='بازکردن راهنما یا مرورگر ممکن نشد. کامل‌بودن بسته و مرورگر پیش‌فرض را بررسی کنید.' }
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
  } catch { $Status.Text='Saved settings could not be read.' }
}
function Start-GuiWork([string]$Action) {
  if ($script:busy) { return }
  $config=@{tunnel_client_exe=$Client.Text.Trim();tunnel_id=$Tunnel.Text.Trim();mcp_url=$Url.Text.Trim()}
  if ($Action -in @('test','install')) {
    try {
      $null=Assert-BrainBridgeConfig $config.tunnel_client_exe $config.tunnel_id $config.mcp_url
      if (-not $Trust.IsChecked) { throw 'Confirm the downloaded ZIP checksum against the official release first.' }
      if (-not $Runtime.SecurePassword.Length -or -not $Token.SecurePassword.Length) { throw 'Enter both credentials. Saved secrets are not prefilled.' }
    } catch { $Status.Text=$_.Exception.Message; return }
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
  $Status.Text='Working… connection checks can take up to 70 seconds.'
  $script:handle=$worker.BeginInvoke()
}
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
  if ($script:busy -and $handle.IsCompleted) {
    try {
      $result=$worker.EndInvoke($handle)
      if ($worker.HadErrors) { $Status.Text='Action failed. Check URL, credentials, Read + Use permissions, executable and local server. Raw errors are hidden to protect secrets.' }
      else { $Status.Text=($result | Out-String).Trim() }
    } catch { $Status.Text='Action failed. No diagnostic containing credentials was saved.' }
    finally {
      $worker.Dispose(); $runtimeCopy.Dispose(); $tokenCopy.Dispose()
      $script:busy=$false
      foreach ($button in $buttons) { $button.IsEnabled=$true }
    }
  }
})
$Browse.Add_Click({
  $dialog=New-Object Microsoft.Win32.OpenFileDialog
  $dialog.Filter='Tunnel client|tunnel-client.exe'; $dialog.CheckFileExists=$true
  if ($dialog.ShowDialog()) { $Client.Text=$dialog.FileName; $Trust.IsChecked=$false }
})
$Test.Add_Click({ Start-GuiWork 'test' }); $Install.Add_Click({ Start-GuiWork 'install' })
$Start.Add_Click({ Start-GuiWork 'start' }); $Refresh.Add_Click({ Start-GuiWork 'refresh' })
$Stop.Add_Click({ Start-GuiWork 'stop' })
$Remove.Add_Click({
  if ([Windows.MessageBox]::Show('Stop Brain Bridge and delete its local settings, encrypted keys and backups? Your vault and tunnel-client remain.','Uninstall Brain Bridge','YesNo','Warning') -eq 'Yes') { Start-GuiWork 'remove' }
})
$window.Add_Closing({param($sender,$eventArgs)
  if ($script:busy) { $eventArgs.Cancel=$true; $Status.Text='Wait for the current operation to finish before closing.' }
})
if ($SmokeTest) {
  if ($Runtime -isnot [Windows.Controls.PasswordBox] -or $Token -isnot [Windows.Controls.PasswordBox]) { throw 'Secret controls must be PasswordBox.' }
  foreach ($entry in @(@($DownloadClient,'download'),@($OpenTunnels,'tunnels'),@($OpenKeys,'keys'),@($HelpGuide,'guide'))) {
    $script:lastHelpDestination=$null
    $entry[0].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    if ($lastHelpDestination -ne (Get-BrainBridgeResource $entry[1])) { throw 'Help button destination mismatch.' }
  }
  $visual=$window.Content
  $visual.Measure((New-Object Windows.Size(780,850))); $visual.Arrange((New-Object Windows.Rect(0,0,780,850))); $visual.UpdateLayout()
  if ($PreviewPath) {
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(780,850,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create($PreviewPath)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
  }
  'PASS: WPF form, secret controls, four help click handlers and layout rendered (browser launch suppressed).'
  $window.Close(); return
}
$timer.Start()
try { $null=$window.ShowDialog() } finally { $timer.Stop(); $Runtime.Clear(); $Token.Clear() }
