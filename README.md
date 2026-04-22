# AD管理ツール (GUI)

Active Directory ユーザーの**パスワード一括リセット**と**Kerberos 暗号化タイプの一括変更**を行う PowerShell GUI ツールです。

## 主な機能

### Tab 1: パスワードリセット
- CSV ファイルから複数ユーザーのパスワードを一括リセット
- 実行前の件数確認ダイアログ
- 成功 / 失敗 / 未検出の集計サマリーを表示
- ログ保存先フォルダを任意に変更可能

### Tab 2: 暗号化タイプ変更（msDS-SupportedEncryptionTypes）
- CSV ファイルから複数ユーザーの `msDS-SupportedEncryptionTypes` を一括変更
- 6 種類のプリセットから設定値を選択
- 実行前の確認ダイアログに選択した設定値を表示
- 値 `0` 指定時は属性を削除（AD のデフォルト動作に委ねる）

## 動作要件

| 項目 | 要件 |
|------|------|
| OS | Windows 10 / 11、Windows Server 2016 以降 |
| PowerShell | 5.1 以上 |
| 必須モジュール | `ActiveDirectory` モジュール (RSAT) |
| 実行権限 | パスワードリセット権限 / AD 属性変更権限を持つアカウント |

## 使い方

### Tab 1: パスワードリセット

**1. CSV ファイルの準備**

以下のヘッダーを持つ CSV ファイルを作成し、`PasswordList.csv` として配置します。

```csv
samAccountName,NewPassword
user01,TempPass123!
user02,TempPass456!
```

**2. 実行**

1. ツールを起動（管理者権限に自動昇格）
2. 「パスワードリセット」タブを選択
3. 「参照...」から CSV ファイルを選択
4. 必要に応じてログ保存先フォルダを変更
5. 「▶ リセット実行」をクリック
6. 確認ダイアログで「はい」を選択

---

### Tab 2: 暗号化タイプ変更

**1. CSV ファイルの準備**

以下のヘッダーを持つ CSV ファイルを作成し、`EncTypeList.csv` として配置します。

```csv
samAccountName
user01
user02
```

**2. 設定値の選択**

| 値 | 内容 | 推奨 |
|----|------|------|
| 24 (0x18) | AES128 + AES256 | **推奨（RC4 なし）** |
| 28 (0x1C) | RC4 + AES128 + AES256 | 移行期の互換設定 |
| 16 (0x10) | AES256 のみ | |
| 8 (0x08) | AES128 のみ | |
| 4 (0x04) | RC4 のみ | 非推奨 |
| 0 | 属性を削除 | AD のデフォルトに従う |

**3. 実行**

1. ツールを起動
2. 「暗号化タイプ変更」タブを選択
3. 「参照...」から CSV ファイルを選択
4. ドロップダウンから設定値を選択
5. 「▶ 暗号化タイプを変更」をクリック
6. 確認ダイアログで設定値を確認し「はい」を選択

> **警告**: Microsoft は 2026 年 Q2 を目途に RC4 を Kerberos のデフォルト暗号化から無効化する予定です。  
> RC4 のみの設定（値 = 4）は将来的に認証エラーの原因となります。可能な限り値 24 への移行を推奨します。  
> 参考: [Kerberos での RC4 使用状況の検出と修復 | Microsoft Learn](https://learn.microsoft.com/ja-jp/windows-server/security/kerberos/detect-remediate-rc4-kerberos)

## ログ

実行ログは `logs/ADTool_yyyyMMdd.log` に保存されます（両タブ共通）。  
保存先は「パスワードリセット」タブの「ログの保存先フォルダ」で変更可能です。

## ファイル構成

```
AD-Password-Reset-Tool/
├── AD_PassReset.ps1       # メインスクリプト
├── パスワードリセット起動.bat  # 起動用バッチファイル
├── PasswordList.csv       # パスワードリセット用CSVサンプル
├── EncTypeList.csv        # 暗号化タイプ変更用CSVサンプル
└── logs/                  # ログ出力先（自動生成）
```
