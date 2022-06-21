Push-Location $PSScriptRoot

$ErrorActionPreference = 'Stop'

$opensslkeyPath = '.\opensslkey.cs'
if (-not (Test-Path $opensslkeyPath)) {
    . .\Init.ps1
}

function Convert-Base64StringToUrlSafe {
    <#
    .SYNOPSIS
        Base64文字列をBase64Url形式に変換する。
    .LINK
        Base64Urlについてはwikipedia参照:
            https://ja.wikipedia.org/wiki/Base64#%E5%A4%89%E5%BD%A2%E7%89%88
    .EXAMPLE
        Convert-Base64StringToUrlSafe -InputObject "AB/CD+EF==" # "AB_CD-EF"
    #>
    param(
        # BASE64文字列
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $InputObject
    )
    return $InputObject.TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Convert-StringToBase64Url {
    <#
    .SYNOPSIS
        文字列をBase64Url形式にエンコードする。
    .EXAMPLE
        Convert-StringToBase64Url -InputObject "AB/CD+EF==" # "AB_CD-EF"
    #>
    param (
        # 文字列
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $InputObject
    )
    $bytes = ([System.Text.Encoding]::UTF8).GetBytes($InputObject)
    return [Convert]::ToBase64String($bytes) | Convert-Base64StringToUrlSafe
}
function Convert-StringToSignedBase64Url {
    <#
    .SYNOPSIS
        指定の文字列をPEM形式の秘密鍵でRSA署名したBASE64URLエンコードの文字列に変換する。
    .EXAMPLE
        Convert-StringToSignedBase64Url `
            -InputObject "ABCDEFG" `
            -PrivateKeyPath "C:\PrivateKey.pem"
    #>
    param (
        # 署名対象文字列
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $InputObject,
        # 秘密鍵のパス
        [Parameter(Mandatory)]
        [string]
        $PrivateKeyPath
    )
    # opensslkey.csを追加する。
    if (-not ('JavaScience.opensslkey' -as [type])) {
        $source = Get-Content .\opensslkey.cs -Encoding UTF8 -Raw
        Add-Type -ReferencedAssemblies System.Security -TypeDefinition "$source"
    }

    # PEMのテキストから RSACryptoServiceProvider を作成する。
    $privateKey = [System.IO.File]::ReadAllText($PrivateKeyPath);
    [byte[]]$pkcs8privatekey = [JavaScience.opensslkey]::DecodePkcs8PrivateKey($privateKey);
    [System.Security.Cryptography.RSACryptoServiceProvider]$rsa =
    [JavaScience.opensslkey]::DecodePrivateKeyInfo($pkcs8privatekey);

    # 署名
    $StringBytes = [System.Text.Encoding]::ASCII.GetBytes($InputObject);
    $signedBytes = $rsa.SignData($StringBytes, [System.Security.Cryptography.SHA256]::Create());
    [string]$signedBase64 = [Convert]::ToBase64String($signedBytes);

    return Convert-Base64StringToUrlSafe $signedBase64
}

# 設定読み込み
<#
# 設定ファイルjson形式
{
    "clientId":"",
    "clientSecret":"",
    "serviceAccount":"",
    "scopes":[
        "bot",
        "user.read"
    ]
}
#>
$config = Get-Content config.json -Encoding UTF8 |
    ConvertFrom-Json

# ヘッダー作成
Write-Host 'ヘッダー作成'
$header = @{
    alg = 'RS256'
    typ = 'JWT'
}
$headerBase64 = $header | ConvertTo-Json -Compress | Convert-StringToBase64Url

Write-Host 'ペイロード作成'
$now = Get-Date
$payload = @{
    iss = $config.clientId
    sub = $config.serviceAccount
    iat = "$([int](Get-Date($now) -UFormat '%s'))"
    exp = "$([int](Get-Date($now.AddMinutes(60)) -UFormat '%s'))"
}
$payloadBase64 = $payload | ConvertTo-Json -Compress | Convert-StringToBase64Url
# 署名作成
Write-Host '署名作成'
$signature = "$headerBase64.$payloadBase64" |
    Convert-StringToSignedBase64Url -PrivateKeyPath 'private.key'

$jwt = "$headerBase64.$payloadBase64.$signature"
Write-Host "JWT完成`n$JWT"

# アクセストークンの取得
$body = @{
    assertion     = $jwt
    grant_type    = 'urn:ietf:params:oauth:grant-type:jwt-bearer'
    client_id     = $config.clientId
    client_secret = $config.clientSecret
    scope         = $config.scopes -join ','
}

Invoke-WebRequest `
    -Method Post `
    -Uri 'https://auth.worksmobile.com/oauth2/v2.0/token' `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body $body

Pop-Location

pause