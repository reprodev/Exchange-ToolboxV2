######################################################################################
# Exchange Toolbox V2.0 - Released 05/02/2026                                        #
#                                                                                    #
# Script Created by ReproDev:   https://github.com/reprodev/Exchange-ToolboxV2/      #
# Released Under MIT Licence                                                         # 
# Check out other projects :    https://github.com/reprodev/                         #
# Why not buy me a coffee? :    https://ko-fi.com/reprodev                           #
#                                                                                    #
######################################################################################

# -------------------------- AUDIT LOGGING SYSTEM -------------------------------

$global:LogFile = Join-Path $PSScriptRoot "ExchangeToolboxV2_Audit.log"

function Write-AuditLog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message,
    [ValidateSet("INFO", "WARNING", "ERROR")]
    [string]$Level = "INFO"
  )
  $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $LogEntry = "[$TimeStamp] [$Level] $Message"
  $LogEntry | Out-File -FilePath $global:LogFile -Append
}

# -------------------------- UTILITY FUNCTIONS ---------------------------------

function Export-Results {
  param(
    [Parameter(Mandatory = $true)]
    $Data
  )
    
  $exportChoice = Read-Host "Export results to CSV? (y/n)"
  if ($exportChoice -eq "y") {
    $fileName = Read-Host "Enter filename (e.g. results.csv)"
    if (-not $fileName.EndsWith(".csv")) { $fileName += ".csv" }
        
    $filePath = Join-Path $PSScriptRoot $fileName
    try {
      $Data | Export-Csv -Path $filePath -NoTypeInformation -Encoding utf8
      Write-Host "SUCCESS: Exported to $filePath" -ForegroundColor Green
      Write-AuditLog "Exported data to $filePath"
    }
    catch {
      Write-Host "ERROR: Could not export. $($_.Exception.Message)" -ForegroundColor Red
      Write-AuditLog "Export FAILED to $filePath : $($_.Exception.Message)" "ERROR"
    }
    Pause
  }
}

# ------------------------ SESSION MANAGEMENT (V3) -----------------------------

function Connect-ToolboxSession {
  Clear-Host
  Write-Host "Checking for active Exchange Online connection..." -ForegroundColor Gray
    
  try {
    # Check if we already have an active connection
    $existingSession = Get-ConnectionInformation -ErrorAction SilentlyContinue
    if ($existingSession) {
      Write-Host "Active session found for $($existingSession.UserPrincipalName)." -ForegroundColor Green
      Write-AuditLog "Re-used existing session for $($existingSession.UserPrincipalName)"
      Pause
      return $true
    }

    Write-Host "No active session found. Initiating Modern Auth (MFA Support)..." -ForegroundColor Cyan
    Connect-ExchangeOnline -ShowBanner:$false
        
    $newSession = Get-ConnectionInformation -ErrorAction Stop
    Write-Host "Successfully connected as $($newSession.UserPrincipalName)" -ForegroundColor Green
    Write-AuditLog "New session established for $($newSession.UserPrincipalName)"
    Pause
    return $true
  }
  catch {
    Write-Host "FAILED to connect to Exchange Online." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "Connection failure: $($_.Exception.Message)" "ERROR"
        
    Write-Host "`nEnsure the 'ExchangeOnlineManagement' module is installed:" -ForegroundColor Yellow
    Write-Host "Run: Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser" -ForegroundColor Yellow
    Pause
    return $false
  }
}

function Disconnect-ToolboxSession {
  Write-Host "Closing Exchange Online session..." -ForegroundColor Gray
  Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
  Write-AuditLog "Session disconnected"
  Write-Host "Disconnected." -ForegroundColor Green
}

# --------------------------- LIST OF FUNCTIONS  -------------------------------

# ------- FUNCTIONS FOR MAILBOX ADMIN --------------

# This function adds a single user to a Mailbox and gives Full Access as the Default permission
function Add-Box-Single {
  Clear-Host
  [string]$User = Read-Host "Enter the user (Name, Email, or Alias)"
  [string]$TargetMailbox = Read-Host "Enter the MAILBOX they need access to"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Adding $User to $TargetMailbox (Full Access)..." -ForegroundColor Cyan
  try {
    Add-MailboxPermission -Identity $TargetMailbox -User $User -AccessRights "FullAccess" -InheritanceType All -ErrorAction Stop
    Write-Host "SUCCESS: Access granted." -ForegroundColor Green
    Write-AuditLog "Added FullAccess for $User on mailbox $TargetMailbox"
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to add access for $User on $TargetMailbox : $($_.Exception.Message)" "ERROR"
  }
  Pause
}

# This function removes fully removes a single user from a mailbox
function Remove-Box-Single {
  Clear-Host
  [string]$User = Read-Host "Enter the user to remove"
  [string]$TargetMailbox = Read-Host "Enter the MAILBOX"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Removing $User from $TargetMailbox..." -ForegroundColor Cyan
  try {
    Remove-MailboxPermission -Identity $TargetMailbox -User $User -AccessRights "FullAccess" -InheritanceType All -Confirm:$false -ErrorAction Stop
    Write-Host "SUCCESS: Access removed." -ForegroundColor Green
    Write-AuditLog "Removed FullAccess for $User on mailbox $TargetMailbox"
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to remove access for $User on $TargetMailbox : $($_.Exception.Message)" "ERROR"
  }
  Pause
}

# This function lists all users who have access to a mailbox
function ShareBoxList {
  Clear-Host
  [string]$TargetMailbox = Read-Host "Enter the MAILBOX to audit"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Retrieving permissions for $TargetMailbox..." -ForegroundColor Cyan
  try {
    $results = Get-MailboxPermission -Identity $TargetMailbox -ErrorAction Stop | 
    Where-Object { $_.User -notmatch "NT AUTHORITY|S-1-5" } | 
    Select-Object User, Identity, AccessRights
        
    $results | Format-Table -AutoSize
    Write-AuditLog "Audited permissions for mailbox $TargetMailbox"
    Export-Results -Data $results
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to audit $TargetMailbox : $($_.Exception.Message)" "ERROR"
    Pause
  }
}

# This function lists all the mailboxes a single user has delegate access to
function UserBoxList {
  Clear-Host
  Write-Host "WARNING: This can take a long time in large environments!" -ForegroundColor Yellow
  [string]$User = Read-Host "Enter the EMAIL ADDRESS of the USER"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Searching all mailboxes for $User access..." -ForegroundColor Cyan
  try {
    # Using EXO for better performance
    $results = Get-EXOMailbox -RecipientTypeDetails UserMailbox, SharedMailbox -ResultSize Unlimited -Property Sets | 
    Get-MailboxPermission -User $User -ErrorAction Stop | 
    Select-Object User, Identity, AccessRights
            
    $results | Format-Table -AutoSize
    [console]::beep(800, 1000)
    Write-AuditLog "Listed all mailboxes where $User has access"
    Export-Results -Data $results
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to list access for $User : $($_.Exception.Message)" "ERROR"
    Pause
  }
}

# This function adds multiple mailboxes from a single user
function Add-Box-Multi {
  Clear-Host
  [string]$User = Read-Host "Enter the USER to add"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  do {
    [string]$TargetMailbox = Read-Host "Enter MAILBOX (or press Enter to finish)"
    if ([string]::IsNullOrWhiteSpace($TargetMailbox)) { break }
        
    Write-Host "Adding $User to $TargetMailbox..." -ForegroundColor Cyan
    try {
      Add-MailboxPermission -Identity $TargetMailbox -User $User -AccessRights "FullAccess" -InheritanceType All -ErrorAction Stop
      Write-Host "SUCCESS." -ForegroundColor Green
      Write-AuditLog "Bulk-Added FullAccess for $User on $TargetMailbox"
    }
    catch {
      Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
      Write-AuditLog "Bulk-ADD FAILED for $User on $TargetMailbox : $($_.Exception.Message)" "ERROR"
    }
  } while ($true)
  Pause
}

# This function removes multiple mailboxes from a single user
function Remove-Box-Multi {
  Clear-Host
  [string]$User = Read-Host "Enter the USER to remove"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  do {
    [string]$TargetMailbox = Read-Host "Enter MAILBOX (or press Enter to finish)"
    if ([string]::IsNullOrWhiteSpace($TargetMailbox)) { break }
        
    Write-Host "Removing $User from $TargetMailbox..." -ForegroundColor Cyan
    try {
      Remove-MailboxPermission -Identity $TargetMailbox -User $User -AccessRights "FullAccess" -InheritanceType All -Confirm:$false -ErrorAction Stop
      Write-Host "SUCCESS." -ForegroundColor Green
      Write-AuditLog "Bulk-Removed FullAccess for $User on $TargetMailbox"
    }
    catch {
      Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
      Write-AuditLog "Bulk-REMOVE FAILED for $User on $TargetMailbox : $($_.Exception.Message)" "ERROR"
    }
  } while ($true)
  Pause
}

# ---------- FUNCTIONS FOR CALENDAR ADMINISTRATION --------------

# This function lists all the users that have delegate access to a calendar
function UserCalList {
  Clear-Host
  [string]$TargetCalendar = Read-Host "Enter the CALENDAR to check (e.g., room@work.com)"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Retrieving permissions for $TargetCalendar...\calendar..." -ForegroundColor Cyan
  try {
    $results = Get-MailboxFolderPermission -Identity "$($TargetCalendar):\calendar" -ErrorAction Stop | 
    Select-Object User, AccessRights
            
    $results | Format-Table -AutoSize
    Write-AuditLog "Audited calendar permissions for $TargetCalendar"
    Export-Results -Data $results
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to audit calendar $TargetCalendar : $($_.Exception.Message)" "ERROR"
    Pause
  }
}

# This function lets you add a single user to a calendar
function Add-Cal-Single {
  Clear-Host
  [string]$TargetCalendar = Read-Host "Enter the CALENDAR"
  [string]$User = Read-Host "Enter the USER that needs access"
  [string]$Permission = Read-Host "Permissions (Owner, Editor, Author, Reviewer, Contributor)"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Adding $User to $TargetCalendar...\calendar ($Permission)..." -ForegroundColor Cyan
  try {
    Add-MailboxFolderPermission -Identity "$($TargetCalendar):\calendar" -User $User -AccessRights $Permission -ErrorAction Stop
    Write-Host "SUCCESS: Access granted." -ForegroundColor Green
    Write-AuditLog "Added calendar permission $Permission for $User on $TargetCalendar"
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to add calendar permission for $User on $TargetCalendar : $($_.Exception.Message)" "ERROR"
  }
  Pause            
}

# This function lets you remove a single user from a calendar
function Remove-Cal-Single {
  Clear-Host
  [string]$TargetCalendar = Read-Host "Enter the CALENDAR"
  [string]$User = Read-Host "Enter the USER to remove"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Removing $User from $TargetCalendar...\calendar..." -ForegroundColor Cyan
  try {
    Remove-MailboxFolderPermission -Identity "$($TargetCalendar):\calendar" -User $User -Confirm:$false -ErrorAction Stop
    Write-Host "SUCCESS: Access removed." -ForegroundColor Green
    Write-AuditLog "Removed calendar permission for $User on $TargetCalendar"
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to remove calendar permission for $User on $TargetCalendar : $($_.Exception.Message)" "ERROR"
  }
  Pause
}

# This function lets you change a single user's access to a calendar
function Set-Cal-Single {
  Clear-Host
  [string]$TargetCalendar = Read-Host "Enter the CALENDAR"
  [string]$User = Read-Host "Enter the USER changing access"
  [string]$Permission = Read-Host "New Permissions (Owner, Editor, Author, Reviewer, Contributor)"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  Write-Host "Updating $User on $TargetCalendar...\calendar to $Permission..." -ForegroundColor Cyan
  try {
    Set-MailboxFolderPermission -Identity "$($TargetCalendar):\calendar" -User $User -AccessRights $Permission -ErrorAction Stop
    Write-Host "SUCCESS: Access updated." -ForegroundColor Green
    Write-AuditLog "Updated calendar permission to $Permission for $User on $TargetCalendar"
  }
  catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-AuditLog "FAILED to set calendar permission for $User on $TargetCalendar : $($_.Exception.Message)" "ERROR"
  }
  Pause
} 

# This function removes multiple calendars from a single user
function Remove-Cal-Multi {
  Clear-Host
  [string]$User = Read-Host "Enter the USER to remove from calendars"
    
  if (-not (Connect-ToolboxSession)) { return }
    
  do {
    [string]$TargetCalendar = Read-Host "Enter CALENDAR to remove from (or press Enter to finish)"
    if ([string]::IsNullOrWhiteSpace($TargetCalendar)) { break }
        
    Write-Host "Removing $User from $TargetCalendar...\calendar..." -ForegroundColor Cyan
    try {
      Remove-MailboxFolderPermission -Identity "$($TargetCalendar):\calendar" -User $User -Confirm:$false -ErrorAction Stop
      Write-Host "SUCCESS." -ForegroundColor Green
      Write-AuditLog "Bulk-Removed calendar permission for $User on $TargetCalendar"
    }
    catch {
      Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
      Write-AuditLog "Bulk-REMOVE calendar FAILED for $User on $TargetCalendar : $($_.Exception.Message)" "ERROR"
    }
  } while ($true)
  Pause
}


# ---------- Functions for Session Management --------------

# This function starts a session in Exchange Online to carry out the function for carrying out Powershell actions
function Show-Session-Global {
  Clear-Host
  # Writes a message on screen to confirm that the login script to create a new session has started
  Write-Host "Running the requested script..." -ForegroundColor DarkBlue -BackgroundColor Gray
  # This sets the variable Session in the global scope and is the command that you would run before commands usually when you do something with Exchange in Powershell
  $global:Session =
  New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $global:UserCredential -Authentication "Basic" -AllowRedirection;
  # The below line then imports that session using the Variable we have just created to allow us to send the output of this function into the option we need
  # This is why the Menu Options contain these functions so this login part can be changed just here if this changes in future  
  Import-PSSession -Session $global:Session
}
# ---------- Functions for Menus and Submenus ----------

function Show-ToolboxHeader {
  param([string]$Title)
  Clear-Host
  Write-Host "================== $Title ==================" -ForegroundColor DarkBlue -BackgroundColor Gray
  Write-Host ""
}

function Show-MainMenu-Toolbox {
  Show-ToolboxHeader -Title "Exchange Toolbox v2.0"
  Write-Host " 1: Exchange Mailbox Administration"
  Write-Host " 2: Exchange Calendar Administration"
  Write-Host " 3: Full Overview (All Operations)"
  Write-Host " 4: Check / Force Refresh Session"
  Write-Host ""
  Write-Host " Q: Exit Application"
  Write-Host ""
}

function Show-SubMenu-Mailbox {
  Show-ToolboxHeader -Title "Mailbox Administration"
  Write-Host " 1: Grant Full Access (Single User)"
  Write-Host " 2: Remove Full Access (Single User)"
  Write-Host " 3: List Mailbox Permissions (Audit)"
  Write-Host " 4: List Mailboxes for a User (Search)"
  Write-Host " 5: Bulk Grant Access (Multiple Mailboxes)"
  Write-Host " 6: Bulk Remove Access (Multiple Mailboxes)"
  Write-Host ""
  Write-Host " B: Back to Main Menu"
  Write-Host ""
}

function Show-SubMenu-Calendar {
  Show-ToolboxHeader -Title "Calendar Administration"
  Write-Host " 1: List Calendar Delegates"
  Write-Host " 2: Add Calendar Permission"
  Write-Host " 3: Remove Calendar Permission"
  Write-Host " 4: Change Calendar Permission"
  Write-Host " 5: Bulk Remove from Calendars"
  Write-Host ""
  Write-Host " B: Back to Main Menu"
  Write-Host ""
}

function Show-SubMenu-Full {
  Show-ToolboxHeader -Title "Full Tool List"
  Write-Host " -- Mailbox --" -ForegroundColor Gray
  Write-Host " 1: Grant Full Access      2: Remove Full Access"
  Write-Host " 3: Audit Mailbox          4: Search User Access"
  Write-Host " 5: Bulk Grant             6: Bulk Remove"
  Write-Host " -- Calendar --" -ForegroundColor Gray
  Write-Host " 7: List Delegates         8: Add Permission"
  Write-Host " 9: Remove Permission     10: Change Permission"
  Write-Host "11: Bulk Remove"
  Write-Host ""
  Write-Host " B: Back to Main Menu"
  Write-Host ""
}

# --------------------------------- START OF APP ---------------------------------------

do {
  Show-MainMenu-Toolbox
  $MainChoice = Read-Host "Select an option"
    
  switch ($MainChoice) {
    "1" {
      do {
        Show-SubMenu-Mailbox
        $SubChoice = Read-Host "Select 1-6 or B"
        switch ($SubChoice) {
          "1" { Add-Box-Single }
          "2" { Remove-Box-Single }
          "3" { ShareBoxList }
          "4" { UserBoxList }
          "5" { Add-Box-Multi }
          "6" { Remove-Box-Multi }
        }
      } until ($SubChoice -eq "b")
    }
    "2" {
      do {
        Show-SubMenu-Calendar
        $SubChoice = Read-Host "Select 1-5 or B"
        switch ($SubChoice) {
          "1" { UserCalList }
          "2" { Add-Cal-Single }
          "3" { Remove-Cal-Single }
          "4" { Set-Cal-Single }
          "5" { Remove-Cal-Multi }
        }
      } until ($SubChoice -eq "b")
    }
    "3" {
      do {
        Show-SubMenu-Full
        $SubChoice = Read-Host "Select 1-11 or B"
        switch ($SubChoice) {
          "1" { Add-Box-Single }
          "2" { Remove-Box-Single }
          "3" { ShareBoxList }
          "4" { UserBoxList }
          "5" { Add-Box-Multi }
          "6" { Remove-Box-Multi }
          "7" { UserCalList }
          "8" { Add-Cal-Single }
          "9" { Remove-Cal-Single } # FIXED: Previously mapped to UserBoxList
          "10" { Set-Cal-Single }
          "11" { Remove-Cal-Multi }
        }
      } until ($SubChoice -eq "b")
    }
    "4" { Connect-ToolboxSession }
    "q" { 
      $confirmQuit = Read-Host "Are you sure you want to quit? (y/n)"
      if ($confirmQuit -eq "y") {
        Disconnect-ToolboxSession
        Write-Host "Goodbye!" -ForegroundColor Yellow
        return
      }
    }
  }
} until ($false)
```
