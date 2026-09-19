$ErrorActionPreference = "SilentlyContinue"

# =========================================================
# Windows SecurityAudit
# Read-only security collection script
# 不刪除、不停用、不終止、不修改任何系統設定
# =========================================================

$Base = "C:\SecurityAudit"
$Today = Get-Date -Format "yyyy-MM-dd"
$OutDir = Join-Path $Base $Today

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null


# ---------------------------------------------------------
# 通用輸出函式
# ---------------------------------------------------------

function Save-Section {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    $Path = Join-Path $OutDir "$Name.txt"

    try {
        & $Command |
            Out-File `
                -FilePath $Path `
                -Encoding utf8 `
                -Width 400
    }
    catch {
        "ERROR: $($_.Exception.Message)" |
            Out-File `
                -FilePath $Path `
                -Encoding utf8
    }
}


# =========================================================
# 01. 執行中的程序
# =========================================================

Save-Section "01_processes" {

    Get-CimInstance Win32_Process |
        Select-Object `
            ProcessId,
            ParentProcessId,
            Name,
            ExecutablePath,
            CommandLine |
        Sort-Object Name
}


# =========================================================
# 02. CPU / 記憶體使用量
# =========================================================

Save-Section "02_process_usage" {

    Get-Process |
        Sort-Object CPU -Descending |
        Select-Object -First 150 `
            Id,
            ProcessName,
            CPU,
            WorkingSet64,
            Path
}


# =========================================================
# 03. TCP 連線
# =========================================================

Save-Section "03_tcp_connections" {

    Get-NetTCPConnection |
        ForEach-Object {

            $ProcessName = ""

            try {
                $ProcessName = (
                    Get-Process -Id $_.OwningProcess -ErrorAction Stop
                ).ProcessName
            }
            catch {}

            [PSCustomObject]@{
                State         = $_.State
                LocalAddress  = $_.LocalAddress
                LocalPort     = $_.LocalPort
                RemoteAddress = $_.RemoteAddress
                RemotePort    = $_.RemotePort
                PID           = $_.OwningProcess
                ProcessName   = $ProcessName
            }

        } |
        Sort-Object State, RemoteAddress
}


# =========================================================
# 04. UDP
# =========================================================

Save-Section "04_udp_endpoints" {

    Get-NetUDPEndpoint |
        ForEach-Object {

            $ProcessName = ""

            try {
                $ProcessName = (
                    Get-Process -Id $_.OwningProcess -ErrorAction Stop
                ).ProcessName
            }
            catch {}

            [PSCustomObject]@{
                LocalAddress = $_.LocalAddress
                LocalPort    = $_.LocalPort
                PID          = $_.OwningProcess
                ProcessName  = $ProcessName
            }

        } |
        Sort-Object LocalPort
}


# =========================================================
# 05. Windows Services
# =========================================================

Save-Section "05_services" {

    Get-CimInstance Win32_Service |
        Select-Object `
            Name,
            DisplayName,
            State,
            StartMode,
            StartName,
            ProcessId,
            PathName |
        Sort-Object Name
}


# =========================================================
# 06. Scheduled Tasks
# =========================================================

Save-Section "06_scheduled_tasks" {

    Get-ScheduledTask |
        ForEach-Object {

            [PSCustomObject]@{
                TaskName = $_.TaskName
                TaskPath = $_.TaskPath
                State    = $_.State

                Actions = (
                    $_.Actions |
                        ForEach-Object {
                            "$($_.Execute) $($_.Arguments)"
                        }
                ) -join " ; "
            }

        } |
        Sort-Object TaskPath, TaskName
}


# =========================================================
# 07. Registry Startup
# =========================================================

Save-Section "07_registry_startup" {

    $Keys = @(

        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",

        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",

        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",

        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",

        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
    )

    foreach ($Key in $Keys) {

        "===== $Key ====="

        if (Test-Path $Key) {

            Get-ItemProperty $Key |
                Format-List *
        }
        else {

            "Not present"
        }

        ""
    }
}


# =========================================================
# 08. Startup Folder
# =========================================================

Save-Section "08_startup_folders" {

    $Folders = @(

        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",

        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )

    foreach ($Folder in $Folders) {

        "===== $Folder ====="

        if (Test-Path $Folder) {

            Get-ChildItem `
                -Path $Folder `
                -Force |

                Select-Object `
                    Name,
                    FullName,
                    Length,
                    CreationTime,
                    LastWriteTime
        }
        else {

            "Not present"
        }

        ""
    }
}


# =========================================================
# 09. Windows 登入 Session
# =========================================================

Save-Section "09_sessions" {

    "===== quser ====="

    quser

    ""

    "===== Win32 LoggedOnUser ====="

    Get-CimInstance Win32_LoggedOnUser |
        Select-Object `
            Antecedent,
            Dependent
}


# =========================================================
# 10. 本機帳號
# =========================================================

Save-Section "10_local_users" {

    Get-LocalUser |
        Select-Object `
            Name,
            Enabled,
            LastLogon,
            PasswordRequired,
            PasswordExpires,
            UserMayChangePassword
}


# =========================================================
# 11. Defender 狀態
# =========================================================

Save-Section "11_defender_status" {

    "===== Defender Computer Status ====="

    Get-MpComputerStatus |
        Format-List *

    ""

    "===== Defender Preferences ====="

    Get-MpPreference |
        Select-Object `
            DisableRealtimeMonitoring,
            DisableBehaviorMonitoring,
            DisableIOAVProtection,
            DisableScriptScanning,
            DisableArchiveScanning,
            DisableEmailScanning,
            DisableIntrusionPreventionSystem,
            ExclusionPath,
            ExclusionProcess,
            ExclusionExtension |
        Format-List *
}


# =========================================================
# 12. Defender 威脅紀錄
# =========================================================

Save-Section "12_defender_threats" {

    Get-MpThreatDetection |
        Select-Object `
            InitialDetectionTime,
            LastThreatStatusChangeTime,
            ThreatID,
            ThreatName,
            Resources,
            ActionSuccess,
            CurrentThreatExecutionStatusID
}


# =========================================================
# 13. 遠端控制 / VPN / Tunnel 工具
# =========================================================

Save-Section "13_remote_tools" {

    $Keywords = @(

        "AnyDesk",
        "TeamViewer",
        "RustDesk",
        "UltraViewer",
        "ScreenConnect",
        "ConnectWise",
        "Chrome Remote Desktop",
        "Tailscale",
        "ZeroTier",
        "ngrok",
        "cloudflared",
        "OpenSSH",
        "Remote Utilities",
        "Splashtop",
        "Parsec",
        "DWService",
        "LogMeIn",
        "RealVNC",
        "TightVNC",
        "UltraVNC",
        "NordVPN",
        "FortiClient",
        "WireGuard",
        "OpenVPN"
    )

    $RegistryPaths = @(

        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",

        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",

        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $Installed = @()

    foreach ($Path in $RegistryPaths) {

        $Installed += Get-ItemProperty $Path
    }

    foreach ($Word in $Keywords) {

        $Matches = $Installed |
            Where-Object {
                $_.DisplayName -like "*$Word*"
            }

        if ($Matches) {

            "===== FOUND: $Word ====="

            $Matches |
                Select-Object `
                    DisplayName,
                    DisplayVersion,
                    Publisher,
                    InstallLocation

            ""
        }
    }


    "===== Running Processes Keyword Check ====="

    Get-CimInstance Win32_Process |
        Where-Object {

            $Name = $_.Name
            $Path = $_.ExecutablePath

            foreach ($Word in $Keywords) {

                if (
                    $Name -like "*$Word*" -or
                    $Path -like "*$Word*"
                ) {
                    return $true
                }
            }

            return $false
        } |
        Select-Object `
            ProcessId,
            Name,
            ExecutablePath,
            CommandLine
}


# =========================================================
# 14. 最近 7 天新增或修改執行檔
# =========================================================

Save-Section "14_recent_files" {

    $Since = (Get-Date).AddDays(-7)

    $SearchPaths = @(

        "$env:USERPROFILE\Downloads",

        "$env:USERPROFILE\Desktop",

        "$env:LOCALAPPDATA",

        "$env:APPDATA",

        "C:\ProgramData"
    )

    $Extensions = @(

        ".exe",
        ".dll",
        ".ps1",
        ".bat",
        ".cmd",
        ".vbs",
        ".js"
    )

    foreach ($Folder in $SearchPaths) {

        if (Test-Path $Folder) {

            Get-ChildItem `
                -Path $Folder `
                -Recurse `
                -Force `
                -File `
                -ErrorAction SilentlyContinue |

                Where-Object {

                    $_.LastWriteTime -gt $Since -and

                    $Extensions -contains $_.Extension.ToLower()

                } |

                Select-Object `
                    FullName,
                    Length,
                    CreationTime,
                    LastWriteTime
        }
    }
}


# =========================================================
# 15. PowerShell Profile
# =========================================================

Save-Section "15_powershell_profiles" {

    $Profiles = @(

        $PROFILE.CurrentUserCurrentHost,

        $PROFILE.CurrentUserAllHosts,

        $PROFILE.AllUsersCurrentHost,

        $PROFILE.AllUsersAllHosts
    )

    foreach ($P in $Profiles | Select-Object -Unique) {

        "===== $P ====="

        if (Test-Path $P) {

            Get-Content $P
        }
        else {

            "Not present"
        }

        ""
    }
}


# =========================================================
# 16. 可疑路徑執行程序
# =========================================================

Save-Section "16_suspicious_paths" {

    Get-CimInstance Win32_Process |
        Where-Object {

            $_.ExecutablePath -match `
            "\\Temp\\|\\Downloads\\|\\AppData\\Local\\Temp\\"

        } |

        Select-Object `
            ProcessId,
            ParentProcessId,
            Name,
            ExecutablePath,
            CommandLine
}


# =========================================================
# 17. 開機 / 關機 / 異常斷電事件
# =========================================================

Save-Section "17_boot_shutdown_events" {

    Get-WinEvent `
        -FilterHashtable @{

            LogName = "System"

            StartTime = (Get-Date).AddDays(-7)

            Id = 41,6005,6006,6008,1074

        } `
        -ErrorAction SilentlyContinue |

        Select-Object `
            TimeCreated,
            Id,
            ProviderName,
            LevelDisplayName,
            Message
}


# =========================================================
# 18. Windows 登入事件
# =========================================================

Save-Section "18_logon_events" {

    Get-WinEvent `
        -FilterHashtable @{

            LogName = "Security"

            StartTime = (Get-Date).AddDays(-7)

            Id = 4624,4625,4634,4648,4672,4778,4779

        } `
        -ErrorAction SilentlyContinue |

        Select-Object `
            TimeCreated,
            Id,
            ProviderName,
            Message
}


# =========================================================
# 19. RDP LocalSessionManager
# =========================================================

Save-Section "19_rdp_events" {

    Get-WinEvent `
        -LogName `
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" `
        -ErrorAction SilentlyContinue |

        Where-Object {

            $_.TimeCreated -gt (Get-Date).AddDays(-7)

        } |

        Select-Object `
            TimeCreated,
            Id,
            LevelDisplayName,
            Message
}


# =========================================================
# 20. RDP RemoteConnectionManager
# =========================================================

Save-Section "20_rdp_connection_events" {

    Get-WinEvent `
        -LogName `
        "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational" `
        -ErrorAction SilentlyContinue |

        Where-Object {

            $_.TimeCreated -gt (Get-Date).AddDays(-7)

        } |

        Select-Object `
            TimeCreated,
            Id,
            LevelDisplayName,
            Message
}


# =========================================================
# 21. 新服務安裝事件
# Event ID 7045
# =========================================================

Save-Section "21_service_install_events" {

    Get-WinEvent `
        -FilterHashtable @{

            LogName = "System"

            StartTime = (Get-Date).AddDays(-7)

            Id = 7045

        } `
        -ErrorAction SilentlyContinue |

        Select-Object `
            TimeCreated,
            Id,
            ProviderName,
            Message
}


# =========================================================
# 22. 工作排程 Event Log
# =========================================================

Save-Section "22_task_scheduler_events" {

    Get-WinEvent `
        -LogName `
        "Microsoft-Windows-TaskScheduler/Operational" `
        -ErrorAction SilentlyContinue |

        Where-Object {

            $_.TimeCreated -gt (Get-Date).AddDays(-7)

        } |

        Select-Object `
            TimeCreated,
            Id,
            LevelDisplayName,
            Message
}


# =========================================================
# 23. Defender Operational Event Log
# =========================================================

Save-Section "23_defender_events" {

    Get-WinEvent `
        -LogName `
        "Microsoft-Windows-Windows Defender/Operational" `
        -ErrorAction SilentlyContinue |

        Where-Object {

            $_.TimeCreated -gt (Get-Date).AddDays(-7)

        } |

        Select-Object `
            TimeCreated,
            Id,
            LevelDisplayName,
            Message
}


# =========================================================
# 24. PowerShell Operational Event Log
# =========================================================

Save-Section "24_powershell_events" {

    Get-WinEvent `
        -LogName `
        "Microsoft-Windows-PowerShell/Operational" `
        -ErrorAction SilentlyContinue |

        Where-Object {

            $_.TimeCreated -gt (Get-Date).AddDays(-7)

        } |

        Select-Object `
            TimeCreated,
            Id,
            LevelDisplayName,
            Message
}


# =========================================================
# 25. 最近建立的本機帳號相關事件
# =========================================================

Save-Section "25_account_events" {

    Get-WinEvent `
        -FilterHashtable @{

            LogName = "Security"

            StartTime = (Get-Date).AddDays(-7)

            Id = 4720,4722,4725,4726,4732,4733

        } `
        -ErrorAction SilentlyContinue |

        Select-Object `
            TimeCreated,
            Id,
            ProviderName,
            Message
}


# =========================================================
# 26. Administrators 群組
# =========================================================

Save-Section "26_local_administrators" {

    Get-LocalGroupMember `
        -Group "Administrators" `
        -ErrorAction SilentlyContinue |

        Select-Object `
            Name,
            ObjectClass,
            PrincipalSource
}


# =========================================================
# 27. RDP 設定狀態
# =========================================================

Save-Section "27_rdp_configuration" {

    "===== RDP Registry ====="

    Get-ItemProperty `
        "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" `
        -ErrorAction SilentlyContinue |

        Select-Object `
            fDenyTSConnections

    ""

    "===== RDP Service ====="

    Get-Service `
        -Name TermService `
        -ErrorAction SilentlyContinue |

        Select-Object `
            Name,
            Status,
            StartType
}


# =========================================================
# 28. Firewall Profiles
# =========================================================

Save-Section "28_firewall_status" {

    Get-NetFirewallProfile |

        Select-Object `
            Name,
            Enabled,
            DefaultInboundAction,
            DefaultOutboundAction
}


# =========================================================
# 29. 目前 Listening Ports
# =========================================================

Save-Section "29_listening_ports" {

    Get-NetTCPConnection `
        -State Listen `
        -ErrorAction SilentlyContinue |

        ForEach-Object {

            $ProcessName = ""

            try {

                $ProcessName = (
                    Get-Process `
                        -Id $_.OwningProcess `
                        -ErrorAction Stop
                ).ProcessName

            }
            catch {}

            [PSCustomObject]@{

                LocalAddress = $_.LocalAddress

                LocalPort = $_.LocalPort

                PID = $_.OwningProcess

                ProcessName = $ProcessName
            }

        } |

        Sort-Object LocalPort
}


# =========================================================
# 30. 系統基本資訊
# =========================================================

Save-Section "30_system_info" {

    Get-CimInstance Win32_OperatingSystem |

        Select-Object `
            CSName,
            Caption,
            Version,
            BuildNumber,
            LastBootUpTime,
            LocalDateTime

    ""

    Get-CimInstance Win32_ComputerSystem |

        Select-Object `
            Name,
            Manufacturer,
            Model,
            Domain,
            UserName
}




# =========================================================
# 31. Code Signatures / Certificates
# Running processes, services, scheduled-task executables,
# startup executables, and currently connected processes.
# =========================================================

Save-Section "31_code_signatures" {

    $CandidatePaths = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    function Add-SignatureCandidate {
        param([string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) { return }

        $Expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())

        # Remove common command-line quoting and arguments where practical.
        if ($Expanded.StartsWith('"')) {
            $Match = [regex]::Match($Expanded, '^"([^"]+\.(exe|dll|sys|ps1))"', 'IgnoreCase')
            if ($Match.Success) { $Expanded = $Match.Groups[1].Value }
        }
        elseif ($Expanded -match '^(.+?\.(exe|dll|sys|ps1))(\s|$)') {
            $Expanded = $Matches[1]
        }

        if (Test-Path -LiteralPath $Expanded -PathType Leaf) {
            [void]$CandidatePaths.Add((Resolve-Path -LiteralPath $Expanded).Path)
        }
    }

    # Running processes
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        ForEach-Object { Add-SignatureCandidate $_.ExecutablePath }

    # Windows services
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        ForEach-Object { Add-SignatureCandidate $_.PathName }

    # Scheduled tasks
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        ForEach-Object {
            $_.Actions | ForEach-Object { Add-SignatureCandidate $_.Execute }
        }

    # Registry startup entries
    $StartupKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($Key in $StartupKeys) {
        if (Test-Path $Key) {
            $Item = Get-ItemProperty $Key -ErrorAction SilentlyContinue
            if ($Item) {
                $Item.PSObject.Properties |
                    Where-Object { $_.Name -notmatch '^PS' } |
                    ForEach-Object { Add-SignatureCandidate ([string]$_.Value) }
            }
        }
    }

    # Processes currently owning TCP connections
    Get-NetTCPConnection -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object {
            try {
                Add-SignatureCandidate (Get-Process -Id $_ -ErrorAction Stop).Path
            }
            catch {}
        }

    foreach ($FilePath in ($CandidatePaths | Sort-Object)) {
        try {
            $Sig = Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction Stop
            $Cert = $Sig.SignerCertificate

            [PSCustomObject]@{
                FilePath      = $FilePath
                Status        = $Sig.Status
                StatusMessage = $Sig.StatusMessage
                SignerSubject = if ($Cert) { $Cert.Subject } else { '' }
                SignerIssuer  = if ($Cert) { $Cert.Issuer } else { '' }
                NotBefore     = if ($Cert) { $Cert.NotBefore } else { $null }
                NotAfter      = if ($Cert) { $Cert.NotAfter } else { $null }
                Thumbprint    = if ($Cert) { $Cert.Thumbprint } else { '' }
            }
        }
        catch {
            [PSCustomObject]@{
                FilePath      = $FilePath
                Status        = 'ERROR'
                StatusMessage = $_.Exception.Message
                SignerSubject = ''
                SignerIssuer  = ''
                NotBefore     = $null
                NotAfter      = $null
                Thumbprint    = ''
            }
        }
    }
}


# =========================================================
# 32. Enriched Network Activity
# netstat-style process-to-remote-IP mapping with executable
# path and Authenticode signer details for active TCP sessions.
# =========================================================

Save-Section "32_network_activity" {

    $Connections = Get-NetTCPConnection -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne 'Listen' }

    $NetworkResults = foreach ($Conn in $Connections) {

        $ProcessName = ''
        $ProcessPath = ''
        $SignatureStatus = ''
        $SignerSubject = ''

        try {
            $Proc = Get-Process -Id $Conn.OwningProcess -ErrorAction Stop
            $ProcessName = $Proc.ProcessName
            $ProcessPath = $Proc.Path

            if ($ProcessPath -and (Test-Path -LiteralPath $ProcessPath -PathType Leaf)) {
                $Sig = Get-AuthenticodeSignature -FilePath $ProcessPath -ErrorAction SilentlyContinue
                if ($Sig) {
                    $SignatureStatus = [string]$Sig.Status
                    if ($Sig.SignerCertificate) {
                        $SignerSubject = $Sig.SignerCertificate.Subject
                    }
                }
            }
        }
        catch {}

        $RemoteClass = 'ExternalOrUnknown'
        if (
            $Conn.RemoteAddress -eq '0.0.0.0' -or
            $Conn.RemoteAddress -eq '::' -or
            $Conn.RemoteAddress -eq '127.0.0.1' -or
            $Conn.RemoteAddress -eq '::1' -or
            $Conn.RemoteAddress -like '10.*' -or
            $Conn.RemoteAddress -like '192.168.*' -or
            $Conn.RemoteAddress -match '^172\.(1[6-9]|2[0-9]|3[0-1])\.' -or
            $Conn.RemoteAddress -match '^fe80:'
        ) {
            $RemoteClass = 'LocalOrPrivate'
        }

        [PSCustomObject]@{
            State           = $Conn.State
            LocalAddress    = $Conn.LocalAddress
            LocalPort       = $Conn.LocalPort
            RemoteAddress   = $Conn.RemoteAddress
            RemotePort      = $Conn.RemotePort
            RemoteClass     = $RemoteClass
            PID             = $Conn.OwningProcess
            ProcessName     = $ProcessName
            ProcessPath     = $ProcessPath
            SignatureStatus = $SignatureStatus
            SignerSubject   = $SignerSubject
        }
    }

    $NetworkResults |
        Sort-Object ProcessName, RemoteClass, RemoteAddress, RemotePort
}


# =========================================================
# 00. 產生總摘要
# =========================================================

$Summary = @"

Windows Security Audit

Computer:
$env:COMPUTERNAME

Interactive User:
$env:USERNAME

Audit Time:
$(Get-Date)

Output Directory:
$OutDir


CHECKED ITEMS

01 Running Processes
02 CPU / Memory Usage
03 TCP Connections
04 UDP Endpoints
05 Windows Services
06 Scheduled Tasks
07 Registry Startup
08 Startup Folder
09 Login Sessions
10 Local Accounts
11 Defender Status
12 Defender Threats
13 Remote Control / VPN / Tunnel Tools
14 Recent Executables / Scripts
15 PowerShell Profiles
16 Suspicious Running Paths
17 Boot / Shutdown / Crash Events
18 Windows Logon Events
19 RDP Local Session Events
20 RDP Remote Connection Events
21 New Service Installation Events
22 Task Scheduler Events
23 Defender Events
24 PowerShell Events
25 Account Creation / Group Events
26 Local Administrators
27 RDP Configuration
28 Firewall Status
29 Listening Ports
30 Windows System Information
31 Code Signatures / Certificates
32 Enriched Network Activity


IMPORTANT SECURITY FOCUS

- Unexpected boot or reboot
- Unexpected shutdown / power loss
- Unknown local account
- Guest account enabled
- Unknown administrator
- Failed login attempts
- RemoteInteractive / RDP login
- Unknown source IP
- RDP reconnection
- Remote control software
- VPN / tunnel software
- New Windows service
- New scheduled task
- Suspicious startup entry
- Suspicious process path
- Unexpected external TCP connection
- Defender protection disabled
- Defender exclusion changes
- Recently downloaded executable files
- Unsigned / invalidly signed executables
- New or changed process-to-remote-IP connections


READ ONLY

This script only collects security information.

It does NOT:

- delete files
- terminate processes
- disable services
- modify registry
- change firewall rules
- change Windows accounts
- change Defender settings

"@

$Summary |
    Out-File `
        -FilePath (
            Join-Path $OutDir "00_summary.txt"
        ) `
        -Encoding utf8


# =========================================================
# 完成
# =========================================================

Write-Host ""
Write-Host "==============================================="
Write-Host " Windows Security Audit completed"
Write-Host "==============================================="
Write-Host ""
Write-Host "Computer:"
Write-Host $env:COMPUTERNAME
Write-Host ""
Write-Host "Report directory:"
Write-Host $OutDir
Write-Host ""
Write-Host "No system settings were changed."
Write-Host ""


# =========================================================
# Sync SecurityAudit report to Google Drive (Portable v4.1)
# Structure: SecurityAudit Reports\<ComputerName>\<Date>
# Auto-detects drive letter and Traditional Chinese / English My Drive names.
# =========================================================

$ComputerName = $env:COMPUTERNAME
$Today = Get-Date -Format "yyyy-MM-dd"
$OutDir = Join-Path "C:\SecurityAudit" $Today
$SyncStatusFile = "C:\SecurityAudit\last_sync_status.txt"

function Set-SyncStatus {
    param(
        [string]$Status,
        [string]$Message,
        [string]$Target = ""
    )

    @(
        "STATUS=$Status"
        "TIME=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "COMPUTER=$ComputerName"
        "SOURCE=$OutDir"
        "TARGET=$Target"
        "MESSAGE=$Message"
    ) | Out-File -FilePath $SyncStatusFile -Encoding ascii -Force
}

function Find-SecurityAuditDriveRoot {
    $Found = New-Object System.Collections.Generic.List[string]

    # Build the Traditional Chinese folder name without depending on BAT encoding.
    $ChineseMyDrive = ([char]0x6211)+([char]0x7684)+([char]0x96F2)+([char]0x7AEF)+([char]0x786C)+([char]0x789F)

    foreach ($Drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if (-not $Drive.Root) { continue }

        $Candidates = @(
            (Join-Path $Drive.Root "$ChineseMyDrive\SecurityAudit Reports"),
            (Join-Path $Drive.Root "My Drive\SecurityAudit Reports")
        )

        foreach ($Candidate in $Candidates) {
            if (Test-Path -LiteralPath $Candidate) {
                $Found.Add($Candidate)
            }
        }
    }

    # Prefer a candidate that is writable.
    foreach ($Candidate in ($Found | Select-Object -Unique)) {
        $Probe = Join-Path $Candidate (".securityaudit-write-test-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
        try {
            "SecurityAudit write test" | Out-File -LiteralPath $Probe -Encoding ascii -Force -ErrorAction Stop
            Remove-Item -LiteralPath $Probe -Force -ErrorAction SilentlyContinue
            return $Candidate
        }
        catch {
            Remove-Item -LiteralPath $Probe -Force -ErrorAction SilentlyContinue
        }
    }

    return $null
}

$GoogleDriveRoot = Find-SecurityAuditDriveRoot

if (-not (Test-Path -LiteralPath $OutDir)) {
    Set-SyncStatus -Status "FAILED" -Message "Local report folder not found."
    Write-Host "WARNING: Local SecurityAudit report folder not found: $OutDir"
    return
}

if (-not $GoogleDriveRoot) {
    Set-SyncStatus -Status "FAILED" -Message "Google Drive SecurityAudit Reports folder was not found or is not writable. Install/sign in to Google Drive for Desktop and ensure edit access."
    Write-Host ""
    Write-Host "WARNING: Google Drive sync target was not found or is not writable."
    Write-Host "Install Google Drive for Desktop, sign in, and make sure 'SecurityAudit Reports' is available under My Drive."
    Write-Host ""
    return
}

$ComputerFolder = Join-Path $GoogleDriveRoot $ComputerName
$DriveDateFolder = Join-Path $ComputerFolder $Today

try {
    New-Item -ItemType Directory -Force -Path $ComputerFolder -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Force -Path $DriveDateFolder -ErrorAction Stop | Out-Null

    Get-ChildItem -LiteralPath $OutDir -File -ErrorAction Stop |
        Copy-Item -Destination $DriveDateFolder -Force -ErrorAction Stop

    # Verify the summary reached the destination.
    $ExpectedSummary = Join-Path $DriveDateFolder "00_summary.txt"
    if (-not (Test-Path -LiteralPath $ExpectedSummary)) {
        throw "Verification failed: 00_summary.txt was not found in the Google Drive destination."
    }

    Set-SyncStatus -Status "OK" -Message "SecurityAudit report synced successfully." -Target $DriveDateFolder

    Write-Host ""
    Write-Host "==============================================="
    Write-Host " SecurityAudit synced to Google Drive"
    Write-Host "==============================================="
    Write-Host "Computer : $ComputerName"
    Write-Host "Date     : $Today"
    Write-Host "Source   : $OutDir"
    Write-Host "Target   : $DriveDateFolder"
    Write-Host ""
}
catch {
    Set-SyncStatus -Status "FAILED" -Message $_.Exception.Message -Target $DriveDateFolder

    Write-Host ""
    Write-Host "WARNING: SecurityAudit sync encountered an error."
    Write-Host "Computer : $ComputerName"
    Write-Host "Source   : $OutDir"
    Write-Host "Target   : $DriveDateFolder"
    Write-Host "Error    : $($_.Exception.Message)"
    Write-Host ""
}
