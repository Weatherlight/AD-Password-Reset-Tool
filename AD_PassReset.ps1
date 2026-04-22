<#
.SYNOPSIS
    ADパスワード一括リセットツール / 暗号化タイプ変更ツール

.DESCRIPTION
    Tab 1: CSVファイルから対象ユーザーのパスワードを一括リセットします。
    Tab 2: CSVファイルから対象ユーザーの msDS-SupportedEncryptionTypes を一括変更します。

.NOTES
    Last Updated: 2026/04/22
#>

param()

# ==========================================
# 管理者権限のチェックと自動昇格 (STAモード、非表示設定)
# ==========================================
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = "-Sta -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File `"$($MyInvocation.MyCommand.Path)`""
    Start-Process powershell -ArgumentList $argList -Verb RunAs
    exit
}

# ==========================================
# --- ユーザー設定エリア ---
# ==========================================
$script:LogDirectoryName = "logs"
# ==========================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

$script:AppDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($script:AppDir)) {
    $script:AppDir = if ($MyInvocation.MyCommand.Path) { Split-Path $MyInvocation.MyCommand.Path } else { $PWD.Path }
}

# ==========================================
# GUI XAML の定義
# ==========================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AD管理ツール" Height="1000" Width="1000"
        Background="#1E1E1E" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI, Meiryo, sans-serif">
    <Window.Resources>

        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#454545"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter Property="BorderBrush" Value="#007ACC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#454545"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Height" Value="36"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton" Focusable="False"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="border" Background="#2D2D30" BorderBrush="#454545" BorderThickness="1" CornerRadius="5">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="30"/>
                                                </Grid.ColumnDefinitions>
                                                <TextBlock Grid.Column="1" Text="▾" Foreground="#AAAAAA" VerticalAlignment="Center" HorizontalAlignment="Center" FontSize="14"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="border" Property="BorderBrush" Value="#007ACC"/>
                                            </Trigger>
                                            <Trigger Property="IsChecked" Value="True">
                                                <Setter TargetName="border" Property="BorderBrush" Value="#007ACC"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite" Margin="12,0,35,0" VerticalAlignment="Center"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              IsHitTestVisible="False"/>
                            <Popup x:Name="Popup" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide" Placement="Bottom">
                                <Border Background="#2D2D30" BorderBrush="#555555" BorderThickness="1" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="300">
                                    <ScrollViewer>
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="#2D2D30"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="bg" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#094771"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="bg" Property="Background" Value="#1C3A5E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="FlatButton" TargetType="Button">
            <Setter Property="Background" Value="#333333"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#555555"/>
            <Setter Property="Padding" Value="18,10"/>
            <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#444444"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#007ACC"/>
                    <Setter Property="BorderBrush" Value="#007ACC"/>
                    <Setter Property="RenderTransform">
                        <Setter.Value>
                            <ScaleTransform ScaleX="0.97" ScaleY="0.97"/>
                        </Setter.Value>
                    </Setter>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Foreground" Value="#777777"/>
                    <Setter Property="Background" Value="#252526"/>
                    <Setter Property="BorderBrush" Value="#333333"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource FlatButton}">
            <Setter Property="Background" Value="#007ACC"/>
            <Setter Property="BorderBrush" Value="#007ACC"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="16"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#0098FF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="#2D7D46"/>
            <Setter Property="BorderBrush" Value="#2D7D46"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#3BA35B"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Padding="25,12" Margin="0" BorderThickness="0,0,0,3" BorderBrush="Transparent" Background="Transparent" CornerRadius="5,5,0,0">
                            <ContentPresenter x:Name="ContentSite" VerticalAlignment="Center" HorizontalAlignment="Center" ContentSource="Header"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="BorderBrush" Value="#007ACC"/>
                                <Setter TargetName="Border" Property="Background" Value="#252526"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter Property="Foreground" Value="#CCCCCC"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#333333"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

    </Window.Resources>

    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="220"/>
        </Grid.RowDefinitions>

        <TabControl Name="MainTab" Grid.Row="0" Background="#252526" BorderThickness="0" Margin="0,0,0,16">

            <!-- ===== Tab 1: パスワードリセット ===== -->
            <TabItem Header="パスワードリセット">
                <Grid Margin="30">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="20"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="20"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="220"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Text="対象CSVファイル：" Foreground="White" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold" Grid.Row="0" Grid.Column="0"/>
                    <TextBox Name="txtCsvPath" Grid.Row="0" Grid.Column="1" Height="36" FontSize="15" Margin="0,0,12,0"/>
                    <Button Name="btnBrowseCsv" Content="参照..." Grid.Row="0" Grid.Column="2" Style="{StaticResource FlatButton}"/>

                    <TextBlock Text="ログの保存先フォルダ：" Foreground="White" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold" Grid.Row="2" Grid.Column="0"/>
                    <TextBox Name="txtLogPath" Grid.Row="2" Grid.Column="1" Height="36" FontSize="15" Margin="0,0,12,0"/>
                    <Button Name="btnBrowseLog" Content="変更..." Grid.Row="2" Grid.Column="2" Style="{StaticResource FlatButton}"/>

                    <Border Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="3" Background="#1C2F3E" BorderBrush="#005A9E" BorderThickness="1" CornerRadius="6" Padding="18" Margin="0,10,0,0" VerticalAlignment="Top">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="30"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Viewbox Grid.Column="0" VerticalAlignment="Top" HorizontalAlignment="Center" Width="20" Height="20" Margin="0,3,10,0">
                                <Path Fill="#9CDCFE" Data="M11 15h2v2h-2zm0-8h2v6h-2zm1-5C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                            </Viewbox>
                            <StackPanel Grid.Column="1" Orientation="Vertical">
                                <TextBlock Text="必須要件と注意事項" Foreground="#9CDCFE" FontSize="15" FontWeight="Bold" Margin="0,0,0,10"/>
                                <TextBlock Text="・指定する CSVファイル には「samAccountName」列と「NewPassword」列が必ず存在している必要があります。" Foreground="#84C0F3" Margin="5,0,0,6"/>
                                <TextBlock Text="・実行端末に RSAT (Active Directory モジュール) がインストールされている必要があります。" Foreground="#84C0F3" Margin="5,0,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <Button Name="btnExecute" Content="▶ リセット実行" Grid.Row="6" Grid.Column="1" Grid.ColumnSpan="2" HorizontalAlignment="Right" Style="{StaticResource SuccessButton}" Width="220" Height="50"/>
                </Grid>
            </TabItem>

            <!-- ===== Tab 2: 暗号化タイプ変更 ===== -->
            <TabItem Header="暗号化タイプ変更 (msDS-SupportedEncryptionTypes)">
                <Grid Margin="30">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="20"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="20"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="16"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="220"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Text="対象CSVファイル：" Foreground="White" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold" Grid.Row="0" Grid.Column="0"/>
                    <TextBox Name="txtEncCsvPath" Grid.Row="0" Grid.Column="1" Height="36" FontSize="15" Margin="0,0,12,0"/>
                    <Button Name="btnEncBrowseCsv" Content="参照..." Grid.Row="0" Grid.Column="2" Style="{StaticResource FlatButton}"/>

                    <TextBlock Text="暗号化タイプ：" Foreground="White" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold" Grid.Row="2" Grid.Column="0"/>
                    <ComboBox Name="cmbEncType" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2"/>

                    <!-- 情報BOX: 設定値の説明 -->
                    <Border Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="3" Background="#1C2F3E" BorderBrush="#005A9E" BorderThickness="1" CornerRadius="6" Padding="18" VerticalAlignment="Top">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="30"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Viewbox Grid.Column="0" VerticalAlignment="Top" HorizontalAlignment="Center" Width="20" Height="20" Margin="0,3,10,0">
                                <Path Fill="#9CDCFE" Data="M11 15h2v2h-2zm0-8h2v6h-2zm1-5C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                            </Viewbox>
                            <StackPanel Grid.Column="1" Orientation="Vertical">
                                <TextBlock Text="主な設定値と要件" Foreground="#9CDCFE" FontSize="15" FontWeight="Bold" Margin="0,0,0,10"/>
                                <TextBlock Text="・24 (0x18) : AES128 + AES256 — RC4 を含まない推奨設定" Foreground="#84C0F3" Margin="5,0,0,5"/>
                                <TextBlock Text="・28 (0x1C) : RC4 + AES128 + AES256 — 移行期の互換設定" Foreground="#84C0F3" Margin="5,0,0,5"/>
                                <TextBlock Text="・16 (0x10) : AES256 のみ" Foreground="#84C0F3" Margin="5,0,0,5"/>
                                <TextBlock Text="・ 8 (0x08) : AES128 のみ" Foreground="#84C0F3" Margin="5,0,0,5"/>
                                <TextBlock Text="・ 4 (0x04) : RC4 のみ（非推奨）" Foreground="#84C0F3" Margin="5,0,0,5"/>
                                <TextBlock Text="・ 0       : 属性を削除（AD のデフォルトに従う）" Foreground="#84C0F3" Margin="5,0,0,5"/>
                                <TextBlock Text="・指定する CSVファイル には「samAccountName」列が必ず存在している必要があります。" Foreground="#84C0F3" Margin="5,6,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- 警告BOX: RC4 廃止 -->
                    <Border Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="3" Background="#2B2D26" BorderBrush="#7D7A2D" BorderThickness="1" CornerRadius="6" Padding="18" VerticalAlignment="Top">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="30"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Viewbox Grid.Column="0" VerticalAlignment="Top" HorizontalAlignment="Center" Width="20" Height="20" Margin="0,3,10,0">
                                <Path Fill="#E0DCA8" Data="M11 15h2v2h-2zm0-8h2v6h-2zm1-5C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8z"/>
                            </Viewbox>
                            <StackPanel Grid.Column="1" Orientation="Vertical">
                                <TextBlock Text="RC4 廃止に関する警告" Foreground="#E0DCA8" FontSize="15" FontWeight="Bold" Margin="0,0,0,10"/>
                                <TextBlock Text="・Microsoft は 2026 年 Q2 を目途に、RC4 を Kerberos のデフォルト暗号化から無効化する予定です。" Foreground="#C7C281" Margin="5,0,0,6"/>
                                <TextBlock Text="・RC4 のみの設定（値 = 4）は将来的に認証エラーの原因となります。可能な限り値 24 への移行を推奨します。" Foreground="#C7C281" Margin="5,0,0,0"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <Button Name="btnEncExecute" Content="▶ 暗号化タイプを変更" Grid.Row="8" Grid.Column="1" Grid.ColumnSpan="2" HorizontalAlignment="Right" Style="{StaticResource SuccessButton}" Width="260" Height="50"/>
                </Grid>
            </TabItem>

        </TabControl>

        <!-- ログラベル -->
        <TextBlock Text="リアルタイム・ログ出力：" Foreground="#CCCCCC" FontSize="14" FontWeight="SemiBold" Grid.Row="1" Margin="6,0,0,6"/>

        <!-- ログエリア -->
        <Border Grid.Row="2" Background="#0C0C0C" BorderBrush="#3E3E42" BorderThickness="1" CornerRadius="6" Padding="6">
            <TextBox Name="txtLog" VerticalContentAlignment="Top" Background="Transparent" Foreground="#10E860" FontFamily="Consolas" FontSize="14" BorderThickness="0" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" IsReadOnly="True" Margin="0"/>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# コントロールの割り当て - Tab 1
$txtCsvPath    = $window.FindName("txtCsvPath")
$txtLogPath    = $window.FindName("txtLogPath")
$btnBrowseCsv  = $window.FindName("btnBrowseCsv")
$btnBrowseLog  = $window.FindName("btnBrowseLog")
$btnExecute    = $window.FindName("btnExecute")

# コントロールの割り当て - Tab 2
$txtEncCsvPath   = $window.FindName("txtEncCsvPath")
$btnEncBrowseCsv = $window.FindName("btnEncBrowseCsv")
$cmbEncType      = $window.FindName("cmbEncType")
$btnEncExecute   = $window.FindName("btnEncExecute")

# 共通
$txtLog     = $window.FindName("txtLog")
$dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher

# 初期値 - Tab 1
$txtCsvPath.Text = Join-Path $script:AppDir "PasswordList.csv"
$txtLogPath.Text = Join-Path $script:AppDir $script:LogDirectoryName

# 初期値 - Tab 2
$txtEncCsvPath.Text = Join-Path $script:AppDir "EncTypeList.csv"

# ComboBox アイテムの追加
$encTypeOptions = @(
    [PSCustomObject]@{ Value = 24; Label = "24 (0x18)  —  AES128 + AES256（推奨・RC4 なし）" },
    [PSCustomObject]@{ Value = 28; Label = "28 (0x1C)  —  RC4 + AES128 + AES256（移行期互換）" },
    [PSCustomObject]@{ Value = 16; Label = "16 (0x10)  —  AES256 のみ" },
    [PSCustomObject]@{ Value =  8; Label =  "8 (0x08)  —  AES128 のみ" },
    [PSCustomObject]@{ Value =  4; Label =  "4 (0x04)  —  RC4 のみ（非推奨）" },
    [PSCustomObject]@{ Value =  0; Label =  "0         —  属性を削除（AD のデフォルトに従う）" }
)
foreach ($opt in $encTypeOptions) {
    $item         = New-Object System.Windows.Controls.ComboBoxItem
    $item.Content = $opt.Label
    $item.Tag     = $opt.Value
    $cmbEncType.Items.Add($item) | Out-Null
}
$cmbEncType.SelectedIndex = 0

# ==========================================
# 共通関数 (ログ出力)
# ==========================================
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
    $logMsg = "[$timestamp] $Message"
    $window.Dispatcher.Invoke([Action]{
        $txtLog.AppendText($logMsg + "`r`n")
        $txtLog.ScrollToEnd()
    })
    try {
        $logDir = $txtLogPath.Text
        if (-not (Test-Path -Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
        $logFile = Join-Path $logDir "ADTool_$(Get-Date -Format 'yyyyMMdd').log"
        $logMsg | Out-File -FilePath $logFile -Append -Encoding UTF8
    } catch {}
    $dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

# ==========================================
# Tab 1: 参照ボタン
# ==========================================
$btnBrowseCsv.Add_Click({
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "CSV files (*.csv)|*.csv"
    $fd.InitialDirectory = $script:AppDir
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtCsvPath.Text = $fd.FileName
    }
})

$btnBrowseLog.Add_Click({
    $fd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fd.Description = "ログファイルを保存するフォルダを選択してください"
    $fd.SelectedPath = $txtLogPath.Text
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtLogPath.Text = $fd.SelectedPath
    }
})

# ==========================================
# Tab 1: 実行ボタン（パスワードリセット）
# ==========================================
$btnExecute.Add_Click({
    $csvPath = $txtCsvPath.Text

    if (-not (Test-Path $csvPath -PathType Leaf)) {
        [System.Windows.MessageBox]::Show($window, "CSVファイルが見つかりません。パスを確認してください。", "エラー", 0, 16)
        return
    }

    $userList = @(Import-Csv $csvPath -Encoding UTF8)
    if ($userList.Count -eq 0) {
        [System.Windows.MessageBox]::Show($window, "CSVファイルにデータが含まれていません。", "エラー", 0, 16)
        return
    }
    if (-not $userList[0].PSObject.Properties.Match("samAccountName")) {
        [System.Windows.MessageBox]::Show($window, "列名 'samAccountName' がCSVに存在しません。", "エラー", 0, 16)
        return
    }
    if (-not $userList[0].PSObject.Properties.Match("NewPassword")) {
        [System.Windows.MessageBox]::Show($window, "列名 'NewPassword' がCSVに存在しません。", "エラー", 0, 16)
        return
    }

    $confirmResult = [System.Windows.MessageBox]::Show(
        $window,
        "$($userList.Count) 件のパスワードをリセットします。`n実行してよろしいですか？",
        "実行確認",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($confirmResult -ne "Yes") { return }

    $btnExecute.IsEnabled = $false
    $window.Cursor = [System.Windows.Input.Cursors]::Wait

    $countSuccess  = 0
    $countError    = 0
    $countNotFound = 0

    try {
        Write-Log "--------------------------------------------------"
        Write-Log "【パスワードリセット】開始 (対象: $($userList.Count) 件)"
        Import-Module ActiveDirectory -ErrorAction Stop

        foreach ($row in $userList) {
            $sam  = $row.samAccountName
            $pass = $row.NewPassword
            if ([string]::IsNullOrWhiteSpace($sam)) { continue }

            $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
            if ($user) {
                try {
                    $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
                    Set-ADAccountPassword -Identity $sam -NewPassword $securePass -Reset -ErrorAction Stop
                    Write-Log "成功: $sam"
                    $countSuccess++
                } catch {
                    Write-Log "失敗: $sam ($($_.Exception.Message))"
                    $countError++
                }
            } else {
                Write-Log "未検出: $sam"
                $countNotFound++
            }
        }

        Write-Log "集計 — 成功: $countSuccess / 失敗: $countError / 未検出: $countNotFound"
        Write-Log "--------------------------------------------------"

        $summaryMsg = "【パスワードリセット完了】`n--------------------`n成功: $countSuccess`n失敗: $countError`n未検出: $countNotFound`n--------------------`nログ: $($txtLogPath.Text)"
        [System.Windows.MessageBox]::Show($window, $summaryMsg, "処理結果サマリー", 0, 64)

    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
    } finally {
        $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        $btnExecute.IsEnabled = $true
    }
})

# ==========================================
# Tab 2: 参照ボタン
# ==========================================
$btnEncBrowseCsv.Add_Click({
    $fd = New-Object System.Windows.Forms.OpenFileDialog
    $fd.Filter = "CSV files (*.csv)|*.csv"
    $fd.InitialDirectory = $script:AppDir
    if ($fd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtEncCsvPath.Text = $fd.FileName
    }
})

# ==========================================
# Tab 2: 実行ボタン（暗号化タイプ変更）
# ==========================================
$btnEncExecute.Add_Click({
    $csvPath = $txtEncCsvPath.Text

    if (-not (Test-Path $csvPath -PathType Leaf)) {
        [System.Windows.MessageBox]::Show($window, "CSVファイルが見つかりません。パスを確認してください。", "エラー", 0, 16)
        return
    }

    $userList = @(Import-Csv $csvPath -Encoding UTF8)
    if ($userList.Count -eq 0) {
        [System.Windows.MessageBox]::Show($window, "CSVファイルにデータが含まれていません。", "エラー", 0, 16)
        return
    }
    if (-not $userList[0].PSObject.Properties.Match("samAccountName")) {
        [System.Windows.MessageBox]::Show($window, "列名 'samAccountName' がCSVに存在しません。", "エラー", 0, 16)
        return
    }

    $selectedItem = $cmbEncType.SelectedItem
    $encTypeValue = [int]($selectedItem.Tag)
    $encTypeLabel = $selectedItem.Content

    $confirmResult = [System.Windows.MessageBox]::Show(
        $window,
        "$($userList.Count) 件のユーザーの msDS-SupportedEncryptionTypes を変更します。`n`n設定値: $encTypeLabel`n`n実行してよろしいですか？",
        "実行確認",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($confirmResult -ne "Yes") { return }

    $btnEncExecute.IsEnabled = $false
    $window.Cursor = [System.Windows.Input.Cursors]::Wait

    $countSuccess  = 0
    $countError    = 0
    $countNotFound = 0

    try {
        Write-Log "--------------------------------------------------"
        Write-Log "【暗号化タイプ変更】開始 (対象: $($userList.Count) 件 / 設定値: $encTypeValue)"
        Import-Module ActiveDirectory -ErrorAction Stop

        foreach ($row in $userList) {
            $sam = $row.samAccountName
            if ([string]::IsNullOrWhiteSpace($sam)) { continue }

            $adUser = Get-ADUser -Filter "SamAccountName -eq '$sam'" -Properties "msDS-SupportedEncryptionTypes" -ErrorAction SilentlyContinue
            if ($adUser) {
                try {
                    if ($encTypeValue -eq 0) {
                        Set-ADUser -Identity $sam -Clear "msDS-SupportedEncryptionTypes" -ErrorAction Stop
                        Write-Log "成功（属性を削除）: $sam"
                    } else {
                        Set-ADUser -Identity $sam -Replace @{ "msDS-SupportedEncryptionTypes" = $encTypeValue } -ErrorAction Stop
                        Write-Log "成功（値 $encTypeValue に変更）: $sam"
                    }
                    $countSuccess++
                } catch {
                    Write-Log "失敗: $sam ($($_.Exception.Message))"
                    $countError++
                }
            } else {
                Write-Log "未検出: $sam"
                $countNotFound++
            }
        }

        Write-Log "集計 — 成功: $countSuccess / 失敗: $countError / 未検出: $countNotFound"
        Write-Log "--------------------------------------------------"

        $summaryMsg = "【暗号化タイプ変更完了】`n設定値: $encTypeLabel`n--------------------`n成功: $countSuccess`n失敗: $countError`n未検出: $countNotFound`n--------------------`nログ: $($txtLogPath.Text)"
        [System.Windows.MessageBox]::Show($window, $summaryMsg, "処理結果サマリー", 0, 64)

    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
    } finally {
        $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        $btnEncExecute.IsEnabled = $true
    }
})

$window.ShowDialog() | Out-Null
