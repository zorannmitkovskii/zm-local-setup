#requires -Version 5.1
<#
    Turns an existing local user into an agency administrator.

    Why this exists: a user who signs up through the app gets no `orgId`. Only
    the admin-create path sets one, so a self-registered account reaches every
    /v1/api/crm/* endpoint and is refused with "Сметката не припаѓа на агенција".
    Nothing in the product is broken — the CRM is scoped to an organization by
    design, and there is no organization on that account.

    This grants both halves of what the agency side needs:

      * `orgId`     — which organization the account acts for. Read straight off
                      the token, never from the request, which is the only reason
                      one agency cannot open another's pipeline.
      * `ORG_ADMIN` — permission to see the agency's money. ORGANIZER is *any*
                      user of an organization, so profitability deliberately
                      refuses it; the assistant who enters leads has no business
                      reading the fee on each one.

    Log out and back in afterwards. The claims are minted into the token, so an
    old token in localStorage keeps every 403 it had.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Email,

    # Any UUID. Reuse the same one across accounts to put them in one agency —
    # that is what makes a colleague's leads visible and is worth testing.
    [string]$OrgId = [guid]::NewGuid().ToString(),

    [string]$Keycloak = 'http://localhost:8181',
    [string]$Realm = 'event-app',
    [string]$AdminUser = 'admin',
    [string]$AdminPass = 'admin'
)

$ErrorActionPreference = 'Stop'
function Step($text) { Write-Host "-> $text" -ForegroundColor Cyan }

Step 'Keycloak admin token'
$token = (Invoke-RestMethod -Method Post -TimeoutSec 15 `
        -Uri "$Keycloak/realms/master/protocol/openid-connect/token" `
        -Body @{ grant_type = 'password'; client_id = 'admin-cli'; username = $AdminUser; password = $AdminPass } `
        -ContentType 'application/x-www-form-urlencoded').access_token
$headers = @{ Authorization = "Bearer $token" }

Step "user $Email"
$users = Invoke-RestMethod -Headers $headers -TimeoutSec 15 `
    -Uri "$Keycloak/admin/realms/$Realm/users?email=$([uri]::EscapeDataString($Email))&exact=true"
if (-not $users) { throw "Нема корисник $Email во realm-от $Realm. Регистрирај се преку апликацијата прво." }
$user = $users[0]
Write-Host "   $($user.id)"

# Merge rather than replace: a PUT with a fresh attribute map drops `packages`
# and `mustChangePassword`, and losing `packages` silently revokes whatever the
# account had bought.
Step "orgId = $OrgId"
$attributes = @{}
if ($user.attributes) {
    $user.attributes.PSObject.Properties | ForEach-Object { $attributes[$_.Name] = $_.Value }
}
$attributes['orgId'] = @($OrgId)

Invoke-RestMethod -Method Put -Headers $headers -TimeoutSec 15 `
    -Uri "$Keycloak/admin/realms/$Realm/users/$($user.id)" `
    -ContentType 'application/json' `
    -Body (@{ attributes = $attributes } | ConvertTo-Json -Depth 5) | Out-Null
Write-Host '   ok'

Step 'role ORG_ADMIN'
$role = Invoke-RestMethod -Headers $headers -TimeoutSec 15 `
    -Uri "$Keycloak/admin/realms/$Realm/roles/ORG_ADMIN"

Invoke-RestMethod -Method Post -Headers $headers -TimeoutSec 15 `
    -Uri "$Keycloak/admin/realms/$Realm/users/$($user.id)/role-mappings/realm" `
    -ContentType 'application/json' `
    -Body (ConvertTo-Json @(@{ id = $role.id; name = $role.name })) | Out-Null
Write-Host '   ok'

Write-Host ''
Write-Host "$Email е сега агенциски админ на организација $OrgId" -ForegroundColor Green
Write-Host 'Одјави се и најави се повторно — податоците се во токенот.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Потоа: http://localhost:5173/mk/dashboard/pipeline'
Write-Host '       http://localhost:5173/mk/dashboard/agency'
