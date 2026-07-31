#requires -Version 5.1
<#
    eventFE is a public PKCE client, so the password grant is off — correct for
    production, inconvenient for a test run. This enables direct grants just
    long enough to mint one token and puts the flag back afterwards, so the
    realm is left exactly as it was found.
#>
[CmdletBinding()]
param(
    [string]$Keycloak = 'http://localhost:8181',
    [string]$Realm = 'event-app',
    [string]$ClientId = 'eventFE',
    [string]$Username = 'http-test',
    [string]$Password = 'HttpTest123!',
    [string]$AdminUser = 'admin',
    [string]$AdminPass = 'admin'
)

$ErrorActionPreference = 'Stop'

$adminToken = (Invoke-RestMethod -Method Post -TimeoutSec 15 `
        -Uri "$Keycloak/realms/master/protocol/openid-connect/token" `
        -Body @{ grant_type = 'password'; client_id = 'admin-cli'; username = $AdminUser; password = $AdminPass } `
        -ContentType 'application/x-www-form-urlencoded').access_token
$headers = @{ Authorization = "Bearer $adminToken" }

$client = (Invoke-RestMethod -Headers $headers -TimeoutSec 15 `
        -Uri "$Keycloak/admin/realms/$Realm/clients?clientId=$ClientId")[0]
if (-not $client) { throw "$ClientId не постои во $Realm" }

$wasEnabled = $client.directAccessGrantsEnabled
Write-Host "directAccessGrants беше: $wasEnabled"

try {
    if (-not $wasEnabled) {
        $client.directAccessGrantsEnabled = $true
        Invoke-RestMethod -Method Put -Headers $headers -TimeoutSec 15 `
            -Uri "$Keycloak/admin/realms/$Realm/clients/$($client.id)" `
            -ContentType 'application/json' -Body ($client | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host 'вклучен привремено'
    }

    $token = (Invoke-RestMethod -Method Post -TimeoutSec 15 `
            -Uri "$Keycloak/realms/$Realm/protocol/openid-connect/token" `
            -Body @{ grant_type = 'password'; client_id = $ClientId; username = $Username; password = $Password } `
            -ContentType 'application/x-www-form-urlencoded').access_token

    Set-Content -Path "$PSScriptRoot\token.txt" -Value $token -NoNewline
    Write-Host "токен зачуван: $PSScriptRoot\token.txt ($($token.Length) знаци)" -ForegroundColor Green
}
finally {
    if (-not $wasEnabled) {
        $client.directAccessGrantsEnabled = $false
        Invoke-RestMethod -Method Put -Headers $headers -TimeoutSec 15 `
            -Uri "$Keycloak/admin/realms/$Realm/clients/$($client.id)" `
            -ContentType 'application/json' -Body ($client | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host 'directAccessGrants вратен на false'
    }
}
