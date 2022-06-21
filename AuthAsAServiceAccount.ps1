Push-Location $PSScriptRoot

$ErrorActionPreference = 'Stop'

$opensslkeyPath = '.\opensslkey.cs'
if (-not (Test-Path $opensslkeyPath)) {
    . .\Init.ps1
}

function Convert-Base64StringToUrlSafe {
    <#
    .SYNOPSIS
        Base64�������Base64Url�`���ɕϊ�����B
    .LINK
        Base64Url�ɂ��Ă�wikipedia�Q��:
            https://ja.wikipedia.org/wiki/Base64#%E5%A4%89%E5%BD%A2%E7%89%88
    .EXAMPLE
        Convert-Base64StringToUrlSafe -InputObject "AB/CD+EF==" # "AB_CD-EF"
    #>
    param(
        # BASE64������
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $InputObject
    )
    return $InputObject.TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Convert-StringToBase64Url {
    <#
    .SYNOPSIS
        �������Base64Url�`���ɃG���R�[�h����B
    .EXAMPLE
        Convert-StringToBase64Url -InputObject "AB/CD+EF==" # "AB_CD-EF"
    #>
    param (
        # ������
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
        �w��̕������PEM�`���̔閧����RSA��������BASE64URL�G���R�[�h�̕�����ɕϊ�����B
    .EXAMPLE
        Convert-StringToSignedBase64Url `
            -InputObject "ABCDEFG" `
            -PrivateKeyPath "C:\PrivateKey.pem"
    #>
    param (
        # �����Ώە�����
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $InputObject,
        # �閧���̃p�X
        [Parameter(Mandatory)]
        [string]
        $PrivateKeyPath
    )
    # opensslkey.cs��ǉ�����B
    if (-not ('JavaScience.opensslkey' -as [type])) {
        $source = Get-Content .\opensslkey.cs -Encoding UTF8 -Raw
        Add-Type -ReferencedAssemblies System.Security -TypeDefinition "$source"
    }

    # PEM�̃e�L�X�g���� RSACryptoServiceProvider ���쐬����B
    $privateKey = [System.IO.File]::ReadAllText($PrivateKeyPath);
    [byte[]]$pkcs8privatekey = [JavaScience.opensslkey]::DecodePkcs8PrivateKey($privateKey);
    [System.Security.Cryptography.RSACryptoServiceProvider]$rsa =
    [JavaScience.opensslkey]::DecodePrivateKeyInfo($pkcs8privatekey);

    # ����
    $StringBytes = [System.Text.Encoding]::ASCII.GetBytes($InputObject);
    $signedBytes = $rsa.SignData($StringBytes, [System.Security.Cryptography.SHA256]::Create());
    [string]$signedBase64 = [Convert]::ToBase64String($signedBytes);

    return Convert-Base64StringToUrlSafe $signedBase64
}

# �ݒ�ǂݍ���
<#
# �ݒ�t�@�C��json�`��
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

# �w�b�_�[�쐬
Write-Host '�w�b�_�[�쐬'
$header = @{
    alg = 'RS256'
    typ = 'JWT'
}
$headerBase64 = $header | ConvertTo-Json -Compress | Convert-StringToBase64Url

Write-Host '�y�C���[�h�쐬'
$now = Get-Date
$payload = @{
    iss = $config.clientId
    sub = $config.serviceAccount
    iat = "$([int](Get-Date($now) -UFormat '%s'))"
    exp = "$([int](Get-Date($now.AddMinutes(60)) -UFormat '%s'))"
}
$payloadBase64 = $payload | ConvertTo-Json -Compress | Convert-StringToBase64Url
# �����쐬
Write-Host '�����쐬'
$signature = "$headerBase64.$payloadBase64" |
    Convert-StringToSignedBase64Url -PrivateKeyPath 'private.key'

$jwt = "$headerBase64.$payloadBase64.$signature"
Write-Host "JWT����`n$JWT"

# �A�N�Z�X�g�[�N���̎擾
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