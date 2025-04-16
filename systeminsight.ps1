Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

function Show-TextWindow($title, $text) {
    $win = New-Object Windows.Window
    $win.Title = $title
    $win.Width = 800
    $win.Height = 500
    $win.WindowStartupLocation = "CenterScreen"

    $scrollViewer = New-Object Windows.Controls.ScrollViewer
    $scrollViewer.VerticalScrollBarVisibility = "Auto"
    $scrollViewer.HorizontalScrollBarVisibility = "Auto"

    $textBox = New-Object Windows.Controls.TextBox
    $textBox.Text = $text
    $textBox.FontFamily = "Consolas"
    $textBox.FontSize = 13
    $textBox.AcceptsReturn = $true
    $textBox.AcceptsTab = $true
    $textBox.TextWrapping = "NoWrap"
    $textBox.IsReadOnly = $true
    $textBox.VerticalScrollBarVisibility = "Auto"
    $textBox.HorizontalScrollBarVisibility = "Auto"
    $textBox.Padding = '10'

    $scrollViewer.Content = $textBox
    $win.Content = $scrollViewer
    $win.ShowDialog() | Out-Null
}

function View-DNSCache {
    try {
        $dns = Get-DnsClientCache | Format-Table -AutoSize | Out-String
    } catch {
        $dns = "Failed to read DNS cache. This feature may require admin or Windows 10+."
    }
    Show-TextWindow "DNS Cache View" $dns
}

function View-StartupApps {
    $apps = Get-CimInstance Win32_StartupCommand |
        Select-Object Name, Command, Location |
        Format-Table -AutoSize | Out-String
    Show-TextWindow "Startup Applications" $apps
}

function View-InstalledApps {
    $apps = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Select-Object DisplayName, Publisher |
        Sort-Object DisplayName |
        Format-Table -AutoSize | Out-String
    Show-TextWindow "Installed Applications" $apps
}

function View-Services {
    $services = Get-Service |
        Where-Object { $_.Status -eq 'Running' } |
        Select-Object DisplayName, Status |
        Format-Table -AutoSize | Out-String
    Show-TextWindow "Running Services" $services
}

function View-ScheduledTasks {
    $tasks = Get-ScheduledTask |
        Select-Object TaskName, TaskPath, State |
        Format-Table -AutoSize | Out-String
    Show-TextWindow "Scheduled Tasks" $tasks
}

function Scan-And-Quarantine {
    $jobScript = {
        $domains = @("myflixer.life", "gu.scurhumbugs.top", "mysticechohaven.com")
        $searchPaths = @(
            "$env:USERPROFILE\AppData\Local\Temp",
            "$env:USERPROFILE\AppData\Local",
            "$env:USERPROFILE\AppData\Roaming"
        )
        $excludedFolders = @("Cache", "Code Cache", "ShaderCache", "GPUCache")
        $excludedExtensions = @(".zip", ".dll", ".iso", ".mp4", ".exe", ".msi", ".img")
        $maxSize = 10MB
        $maxFilesPerPath = 1000
        $quarantineDir = "$env:USERPROFILE\Quarantine"
        if (!(Test-Path $quarantineDir)) {
            New-Item -ItemType Directory -Path $quarantineDir | Out-Null
        }

        $foundFiles = @()
        foreach ($path in $searchPaths) {
            foreach ($domain in $domains) {
                $filesScanned = 0
                Get-ChildItem -Path $path -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object {
                    $filesScanned++
                    if ($filesScanned -gt $maxFilesPerPath) { return $false }
                    if ($_.Extension -and $excludedExtensions -contains $_.Extension.ToLower()) { return $false }
                    if ($_.Length -gt $maxSize) { return $false }
                    foreach ($skip in $excludedFolders) {
                        if ($_.FullName -like "*\$skip\*") { return $false }
                    }
                    return $true
                } | ForEach-Object {
                    try {
                        $match = Select-String -Path $_.FullName -Pattern $domain -SimpleMatch -List -ErrorAction Stop
                        if ($match) {
                            $foundFiles += $_.FullName
                        }
                    } catch {
                        # skip
                    }
                }
            }
        }

        $log = ""
        if ($foundFiles.Count -eq 0) {
            $log = "No matching files found for suspicious domains."
        } else {
            $log = "[+] Found suspicious files:`n" + ($foundFiles | Sort-Object -Unique | Out-String)
            $log += "`n`n[!] Moving to quarantine..."

            foreach ($file in $foundFiles | Sort-Object -Unique) {
                try {
                    $name = [System.IO.Path]::GetFileName($file)
                    Move-Item -Path $file -Destination "$quarantineDir\$name" -Force
                } catch {
                    $log += "`n[!] Failed to move: $file"
                }
            }

            $log += "`n`n[OK] Operation complete. Files moved to: $quarantineDir"
        }

        $log
    }

    $job = Start-Job -ScriptBlock $jobScript
    while (-not $job.HasExited) {
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Application]::DoEvents()
    }

    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    Show-TextWindow "Quarantine Result" $result
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="System Insight Tool" Height="480" Width="420" WindowStartupLocation="CenterScreen">
    <StackPanel Margin="20">
        <TextBlock Text="System Insight Control Panel" FontSize="18" FontWeight="Bold" Margin="0 0 0 20" HorizontalAlignment="Center"/>
        <Button Name="btnDNS" Content="View DNS Cache" Height="35" Margin="0 5"/>
        <Button Name="btnStartup" Content="View Startup Apps" Height="35" Margin="0 5"/>
        <Button Name="btnApps" Content="View Installed Apps" Height="35" Margin="0 5"/>
        <Button Name="btnServices" Content="View Running Services" Height="35" Margin="0 5"/>
        <Button Name="btnTasks" Content="View Scheduled Tasks" Height="35" Margin="0 5"/>
        <Button Name="btnQuarantine" Content="Scan &amp; Quarantine Suspicious Domains" Height="35" Margin="0 5"/>
        <Button Name="btnExit" Content="Exit" Height="35" Margin="0 20"/>
    </StackPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$window.FindName("btnDNS").Add_Click({ View-DNSCache })
$window.FindName("btnStartup").Add_Click({ View-StartupApps })
$window.FindName("btnApps").Add_Click({ View-InstalledApps })
$window.FindName("btnServices").Add_Click({ View-Services })
$window.FindName("btnTasks").Add_Click({ View-ScheduledTasks })
$window.FindName("btnQuarantine").Add_Click({ Scan-And-Quarantine })
$window.FindName("btnExit").Add_Click({ $window.Close() })

$window.ShowDialog() | Out-Null
