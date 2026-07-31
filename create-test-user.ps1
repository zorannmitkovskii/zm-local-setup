#requires -Version 5.1
<#
    Creates a test user for the HTTP suite.

    Goes through zm-iam-service rather than straight to Keycloak, because that
    is the path the product itself uses — if it works here it works for Ivy.
    Keycloak is touched only to obtain the service credential that IAM expects.
#>
[CmdletBinding()]
param(
    [string]$Keycloak = 'http://localhost:8181',
    [string]$Iam = 'http://localhost:8282',
    [string]$AdminUser = 'admin',
    [string]$AdminPass = 'admin',
    [string]$Realm = 'event-app',
    [string]$Username = 'http-test',
    [string]$Password = 'HttpTest123!',
    [string]$Email = 'http-test@example.com'
)

$ErrorActionPreference = 'Stop'
function Step($text) { Write-Host "-> $text" -ForegroundColor Cyan }

# 1. Keycloak admin token
Step 'Keycloak admin token'
$adminToken = (Invoke-RestMethod -Method Post -TimeoutSec 15 `
        -Uri "$Keycloak/realms/master/protocol/openid-connect/token" `
        -Body @{ grant_type = 'password'; client_id = 'admin-cli'; username = $AdminUser; password = $AdminPass } `
        -ContentType 'application/x-www-form-urlencoded').access_token
Write-Host '   ok'

$adminHeaders = @{ Authorization = "Bearer $adminToken" }

# 2. The service credential IAM expects, read from the zm-services realm.
Step 'service client secret from zm-services'
$clients = Invoke-RestMethod -Headers $adminHeaders -TimeoutSec 15 `
    -Uri "$Keycloak/admin/realms/zm-services/clients?clientId=ivy-events-be-svc"
if (-not $clients) { throw 'ivy-events-be-svc не постои во zm-services' }
$secret = (Invoke-RestMethod -Headers $adminHeaders -TimeoutSec 15 `
        -Uri "$Keycloak/admin/realms/zm-services/clients/$($clients[0].id)/client-secret").value
Write-Host "   ok ($($secret.Substring(0, 4))…)"

# 3. Service token — the identity Ivy itself uses against IAM.
Step 'service token'
$svcToken = (Invoke-RestMethod -Method Post -TimeoutSec 15 `
        -Uri "$Keycloak/realms/zm-services/protocol/openid-connect/token" `
        -Body @{ grant_type = 'client_credentials'; client_id = 'ivy-events-be-svc'; client_secret = $secret } `
        -ContentType 'application/x-www-form-urlencoded').access_token
Write-Host '   ok'

# 4. Create the user through IAM.
Step "create $Username via zm-iam-service"
$payload = @{
    realm     = $Realm
    username  = $Username
    email     = $Email
    firstName = 'HTTP'
    lastName  = 'Test'
    password  = $Password
    enabled   = $true
    roles     = @('ORGANIZER', 'USER')
} | ConvertTo-Json

try {
    $created = Invoke-RestMethod -Method Post -TimeoutSec 20 `
        -Uri "$Iam/internal/users" -ContentType 'application/json' `
        -Headers @{ Authorization = "Bearer $svcToken" } -Body $payload
    Write-Host "   ok: $($created | ConvertTo-Json -Compress)"
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 409) { Write-Host '   веќе постои — продолжувам' -ForegroundColor Yellow }
    else {
        Write-Host "   IAM врати $status : $($_.ErrorDetails.Message)" -ForegroundColor Yellow
        Write-Host '   паѓам назад на Keycloak admin API' -ForegroundColor Yellow

        $user = @{
            username = $Username; email = $Email; enabled = $true
            emailVerified = $true; firstName = 'HTTP'; lastName = 'Test'
            credentials = @(@{ type = 'password'; value = $Password; temporary = $false })
        } | ConvertTo-Json -Depth 5
        try {
            Invoke-RestMethod -Method Post -Headers $adminHeaders -TimeoutSec 15 `
                -Uri "$Keycloak/admin/realms/$Realm/users" -ContentType 'application/json' -Body $user | Out-Null
            Write-Host '   создаден преку Keycloak'
        }
        catch {
            if ($_.Exception.Response.StatusCode.value__ -eq 409) { Write-Host '   веќе постои' -ForegroundColor Yellow }
            else { throw }
        }
    }
}

# 5. The user token the HTTP suite will carry.
Step 'user token (password grant)'
foreach ($clientId in @('eventFE', 'event-fe', 'frontend')) {
    try {
        $token = (Invoke-RestMethod -Method Post -TimeoutSec 15 `
                -Uri "$Keycloak/realms/$Realm/protocol/openid-connect/token" `
                -Body @{ grant_type = 'password'; client_id = $clientId; username = $Username; password = $Password } `
                -ContentType 'application/x-www-form-urlencoded').access_token
        Write-Host "   ok преку client_id=$clientId"
        Set-Content -Path "$PSScriptRoot\token.txt" -Value $token -NoNewline
        Write-Host "   зачуван во $PSScriptRoot\token.txt"
        return
    }
    catch {
        Write-Host "   client_id=$clientId не помина ($($_.Exception.Response.StatusCode.value__))" -ForegroundColor DarkGray
    }
}
# Not fatal: eventFE is a public PKCE client with direct grants off, which is
# correct. get-token.ps1 is the script that knows how to work around that, and
# it runs right after this one. Throwing here would stop the chain over a step
# this script does not own.
Write-Host '   ниту еден client_id не даде токен овде — get-token.ps1 го презема' -ForegroundColor Yellow
