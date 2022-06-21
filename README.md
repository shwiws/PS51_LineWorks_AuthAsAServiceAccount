# PS51_LineWorks_AuthAsAServiceAccount
LINEWORKS API 2.0 の Service Accountの認証処理。PowerShell 5.1前提です。


# 使い方

## 1. Init.ps1 を実行する
opensslkey.cs をダウンロードします。

## 2. config.json ファイルを追加する。
以下の構造のjsonファイルに、クライアントIDなど認証に必要な情報を入力します。

```json
{
    "clientId":"",
    "clientSecret":"",
    "serviceAccount":"",
    "scopes":[
        "bot",
        "user.read"
    ]
}
```

## 3. AuthAsAServiceAccount.ps1 を実行

スクリプトを実行してください。
このスクリプトはそのままレスポンスを返すようになっているので、結果がコンソールに表示されます。
