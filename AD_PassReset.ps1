Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- 初期設定（デフォルトのパス設定） ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = Get-Location }

$defaultLogFolder = Join-Path $scriptDir "logs"
$global:currentLogFolder = $defaultLogFolder

# --- メインウィンドウの設定 ---
$form = New-Object Windows.Forms.Form
$form.Text = "ADパスワード一括リセットツール (確認・集計機能付)"
$form.Size = New-Object Drawing.Size(520, 480) 
$form.StartPosition = "CenterScreen"

# --- 1. CSVファイル選択エリア ---
$labelCsv = New-Object Windows.Forms.Label
$labelCsv.Location = New-Object Drawing.Point(20, 20)
$labelCsv.Size = New-Object Drawing.Size(400, 20)
$labelCsv.Text = "1. パスワードリスト（CSV）を選択してください:"
$form.Controls.Add($labelCsv)

$txtFilePath = New-Object Windows.Forms.TextBox
$txtFilePath.Location = New-Object Drawing.Point(20, 45)
$txtFilePath.Size = New-Object Drawing.Size(370, 20)
$txtFilePath.ReadOnly = $true
$txtFilePath.Text = (Join-Path $scriptDir "PasswordList.csv")
$form.Controls.Add($txtFilePath)

$btnBrowseCsv = New-Object Windows.Forms.Button
$btnBrowseCsv.Location = New-Object Drawing.Point(400, 43)
$btnBrowseCsv.Size = New-Object Drawing.Size(80, 25)
$btnBrowseCsv.Text = "参照..."
$btnBrowseCsv.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = "CSVファイル (*.csv)|*.csv"
    if ($dialog.ShowDialog() -eq "OK") { $txtFilePath.Text = $dialog.FileName }
})
$form.Controls.Add($btnBrowseCsv)

# --- 2. ログ出力先選択エリア ---
$labelLog = New-Object Windows.Forms.Label
$labelLog.Location = New-Object Drawing.Point(20, 85)
$labelLog.Size = New-Object Drawing.Size(400, 20)
$labelLog.Text = "2. ログの保存先フォルダ（現在はデフォルト設定です）:"
$form.Controls.Add($labelLog)

$txtLogPath = New-Object Windows.Forms.TextBox
$txtLogPath.Location = New-Object Drawing.Point(20, 110)
$txtLogPath.Size = New-Object Drawing.Size(370, 20)
$txtLogPath.Text = $global:currentLogFolder
$txtLogPath.ReadOnly = $true
$form.Controls.Add($txtLogPath)

$btnBrowseLog = New-Object Windows.Forms.Button
$btnBrowseLog.Location = New-Object Drawing.Point(400, 108)
$btnBrowseLog.Size = New-Object Drawing.Size(80, 25)
$btnBrowseLog.Text = "変更..."
$btnBrowseLog.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = "ログファイルを保存するフォルダを選択してください"
    $dialog.SelectedPath = $global:currentLogFolder
    if ($dialog.ShowDialog() -eq "OK") {
        $global:currentLogFolder = $dialog.SelectedPath
        $txtLogPath.Text = $global:currentLogFolder
    }
})
$form.Controls.Add($btnBrowseLog)

# --- 3. 実行ログ表示エリア ---
$txtLogOutput = New-Object Windows.Forms.RichTextBox
$txtLogOutput.Location = New-Object Drawing.Point(20, 210)
$txtLogOutput.Size = New-Object Drawing.Size(460, 180)
$txtLogOutput.ReadOnly = $true
$txtLogOutput.BackColor = "Black"
$txtLogOutput.ForeColor = "White"
$form.Controls.Add($txtLogOutput)

# --- ログ書き込み用関数 ---
function Write-GuiLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $txtLogOutput.AppendText($logEntry + "`n")
    $txtLogOutput.ScrollToCaret()
    
    $fileTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$fileTimestamp] [$Level] $Message" | Out-File -FilePath $global:activeLogFile -Append -Encoding UTF8
    [System.Windows.Forms.Application]::DoEvents()
}

# --- 4. 実行ボタン ---
$btnRun = New-Object Windows.Forms.Button
$btnRun.Location = New-Object Drawing.Point(190, 160)
$btnRun.Size = New-Object Drawing.Size(120, 35)
$btnRun.Text = "リセット実行"
$btnRun.BackColor = "LightGreen"
$btnRun.Font = New-Object Drawing.Font("MS Gothic", 10, [Drawing.FontStyle]::Bold)

$btnRun.Add_Click({
    if (!(Test-Path $txtFilePath.Text)) {
        [Windows.Forms.MessageBox]::Show("CSVファイルが見つかりません。パスを確認してください。")
        return
    }

    # 集計用カウンターの初期化
    $countSuccess = 0
    $countError = 0
    $countWarn = 0

    try {
        $userList = Import-Csv $txtFilePath.Text -Encoding UTF8
        $totalUsers = $userList.Count

        # --- 実行確認ダイアログ ---
        $confirmMsg = "$totalUsers 名のパスワードをリセットします。`n実行してもよろしいですか？"
        $result = [Windows.Forms.MessageBox]::Show($confirmMsg, "実行確認", [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
        
        if ($result -eq "No") {
            return # 処理を中断
        }

        # ログフォルダの準備
        if (!(Test-Path $global:currentLogFolder)) {
            New-Item -ItemType Directory -Path $global:currentLogFolder -Force | Out-Null
        }
        $global:activeLogFile = Join-Path $global:currentLogFolder ("PassReset_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
        $txtLogOutput.Clear()
        
        Write-GuiLog "処理を開始します... (対象: $totalUsers 名)"
        Import-Module ActiveDirectory

        foreach ($row in $userList) {
            $sam = $row.samAccountName
            $pass = $row.NewPassword

            $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
            if ($user) {
                try {
                    $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
                    Set-ADAccountPassword -Identity $sam -NewPassword $securePass -Reset -ErrorAction Stop
                    Write-GuiLog "成功: $sam" "SUCCESS"
                    $countSuccess++
                } catch {
                    Write-GuiLog "失敗: $sam ($($_.Exception.Message))" "ERROR"
                    $countError++
                }
            } else {
                Write-GuiLog "未検出: $sam" "WARN"
                $countWarn++
            }
        }

        # --- 完了後の集計表示 ---
        $summaryMsg = "【完了】集計結果`n--------------------`n成功: $countSuccess`n失敗: $countError`n未検出: $countWarn`n--------------------`nログ: $global:activeLogFile"
        Write-GuiLog "------------------------------"
        Write-GuiLog "集計結果 - 成功: $countSuccess, 失敗: $countError, 未検出: $countWarn"
        Write-GuiLog "完了しました。"
        
        [Windows.Forms.MessageBox]::Show($summaryMsg, "処理結果サマリー", [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information)

    } catch {
        Write-GuiLog "致命的なエラー: $($_.Exception.Message)" "ERROR"
    }
})
$form.Controls.Add($btnRun)

$form.ShowDialog()