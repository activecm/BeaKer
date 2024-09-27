<#

.SYNOPSIS
This Powershell script installs and configures Microsoft Sysinternals Sysmon and Elastic Winlogbeat with the aim
of shipping network connection events to a centralized Elasticsearch server.

.DESCRIPTION
This script install Microsoft Sysinternals Sysmon and Elastic Winlogbeat to the Windows Program Files directory.
Sysmon is then configured to report network connections and Winlogbeat is configured to send connection logs to
the desired Elasticsearch server.

.PARAMETER ESHost
The IP address or hostname of the Elasticsearch server to send connection logs. This should not contain a protocol descriptor such as "https://".

.PARAMETER ESPort
The port on which the Elasticsearch server is listening. Defaults to TCP 9200.

.PARAMETER ESUsername
Warning: Insecure!
The username used to authenticate to the Elasticsearch server. If ESUsername is not specified,
the script will ask for the username at runtime. In order to avoid recording the Elasticsearch
username, consider editing this file. Change the line `[string]$ESUsername="",` to
`[string]$ESUsername="YOUR_ELASTIC_USERNAME_HERE",.

.PARAMETER ESPassword
Warning: Insecure!
The password used to authenticate to the Elasticsearch server. If ESPassword is not specified,
the script will ask for the password at runtime. In order to avoid recording the Elasticsearch
password, consider editing this file. Change the line `[string]$ESPassword="",` to
`[string]$ESPassword="YOUR_ELASTIC_PASSWORD_HERE",.

.PARAMETER BeatsVersion
The version of Winlogbeat to install. This will override any logic that handles upgrading to an
intermediate version of Winlogbeat before upgrading to a higher major version.

.EXAMPLE
# Asks for Elasticsearch authentication details at runtime
.\install-sysmon-beats.ps1 my-es-host.com 9200

# Reads Elasticsearch authentication details from the command line aguments
.\install-sysmon-beats.ps1 my-es-host.com 9200 elastic elastic_password

# Overrides the version of Winlogbeat to install
.\install-sysmon-beats.ps1 my-es-host.com 9200 elastic elastic_password 8.6.2

.NOTES
The Elasticsearch credentials are stored locally using Elastic Winlogbeat's secure
storage facilities. The ESUsername and ESPassword parameters should not be passed
into the script in a secure environment. Instead, either leave the credentials blank and
enter the credentials during the installation process, or edit the parameters' default values in the script.
#>

param (
    [Parameter(Mandatory = $true)][string]$ESHost,
    [string]$ESPort = "9200",
    [string]$ESUsername = "",
    [string]$ESPassword = "",
    [string]$BeatsVersion = ""
)

$ELK_STACK_VERSION = "8.7.0"

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {  
    # Use param values instead of $args because $args doesn't appear to get populated if param values are specified
    # Also set the ExecutionPolicy to Bypass otherwise this will likely fail as script
    # execution is disabled by default.
    $arguments = "-ExecutionPolicy", "Bypass", "-File", $myinvocation.mycommand.definition, $ESHost, $ESPort
    if ($ESUsername) {
        # Only add this argument if the user provided it, otherwise it will be blank and will cause an error
        $arguments += $ESUsername
    }
    if ($ESPassword) {
        # Only add this argument if the user provided it, otherwise it will be blank and will cause an error
        $arguments += $ESPassword
    }
    if ($BeatsVersion) {
        # Only add this argument if the user provided it, otherwise it will be blank and will cause an error
        $arguments += $BeatsVersion
    }

    Start-Process -FilePath powershell -Verb runAs -ArgumentList $arguments
    Break
}


[bool] $OverrideBeatsVersion = $false
if ([string]::IsNullOrWhiteSpace("$BeatsVersion")) {
    $BeatsVersion = "$ELK_STACK_VERSION"
}
else {
    if ($null -eq ("$BeatsVersion" -as [System.Version])) {
        throw "Beats version $BeatsVersion is not a valid version, please provide a valid version number."
    }
    if ([System.Version]$BeatsVersion -lt [System.Version]"7.17.9") {
        throw "Minimum supported Beats version is 7.17.9, exiting"
    }
    $OverrideBeatsVersion = $true
}

# Check for existing winlogbeat installation via Espy
if (Test-Path "$Env:programfiles\Winlogbeat-Espy" -PathType Container) {
    Write-Output "Detected existing winlogbeat installation performed by Espy. Continuing the install may result in a partially working Sysmon/winlogbeat setup."
    $installAnyway = Read-Host -Prompt "Are you sure you want to continue? [y/n]"
    if (($installAnyway -eq 'n') -or ($installAnyway -eq 'N')) {
        Exit
    }
}

if (-not (Test-Path "$Env:programfiles\Sysmon" -PathType Container)) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -OutFile Sysmon.zip https://download.sysinternals.com/files/Sysmon.zip
    Expand-Archive .\Sysmon.zip
    rm .\Sysmon.zip
    mv .\Sysmon\ "$Env:programfiles"
}

echo @"
<Sysmon schemaversion="4.22">
    <HashAlgorithms>md5,sha256,IMPHASH</HashAlgorithms>
    <EventFiltering>
        <ProcessCreate onmatch="include">
            <!--SYSMON EVENT ID 1 : PROCESS CREATION [ProcessCreate]-->
        </ProcessCreate>

        <FileCreateTime onmatch="include">
            <!--SYSMON EVENT ID 2 : FILE CREATION TIME RETROACTIVELY CHANGED IN THE FILESYSTEM [FileCreateTime]-->
        </FileCreateTime>

        <NetworkConnect onmatch="exclude">
            <!--SYSMON EVENT ID 3 : NETWORK CONNECTION INITIATED [NetworkConnect]-->
        </NetworkConnect>

        <!--SYSMON EVENT ID 4 : RESERVED FOR SYSMON SERVICE STATUS MESSAGES-->

        <ProcessTerminate onmatch="include">
            <!--SYSMON EVENT ID 5 : PROCESS ENDED [ProcessTerminate]-->
        </ProcessTerminate>

        <DriverLoad onmatch="include">
            <!--SYSMON EVENT ID 6 : DRIVER LOADED INTO KERNEL [DriverLoad]-->
        </DriverLoad>

        <ImageLoad onmatch="include">
            <!--SYSMON EVENT ID 7 : DLL (IMAGE) LOADED BY PROCESS [ImageLoad]-->
        </ImageLoad>

        <CreateRemoteThread onmatch="include">
            <!--SYSMON EVENT ID 8 : REMOTE THREAD CREATED [CreateRemoteThread]-->
        </CreateRemoteThread>

        <RawAccessRead onmatch="include">
            <!--SYSMON EVENT ID 9 : RAW DISK ACCESS [RawAccessRead]-->
        </RawAccessRead>

        <ProcessAccess onmatch="include">
            <!--SYSMON EVENT ID 10 : INTER-PROCESS ACCESS [ProcessAccess]-->
        </ProcessAccess>

        <FileCreate onmatch="include">
            <!--SYSMON EVENT ID 11 : FILE CREATED [FileCreate]-->
        </FileCreate>

        <RegistryEvent onmatch="include">
            <!--SYSMON EVENT ID 12 & 13 & 14 : REGISTRY MODIFICATION [RegistryEvent]-->
        </RegistryEvent>

        <FileCreateStreamHash onmatch="include">
            <!--SYSMON EVENT ID 15 : ALTERNATE DATA STREAM CREATED [FileCreateStreamHash]-->
        </FileCreateStreamHash>

        <!--SYSMON EVENT ID 16 : SYSMON CONFIGURATION CHANGE-->

        <PipeEvent onmatch="include">
            <!--SYSMON EVENT ID 17 & 18 : PIPE CREATED / PIPE CONNECTED [PipeEvent]-->
        </PipeEvent>

        <WmiEvent onmatch="include">
            <!--SYSMON EVENT ID 19 & 20 & 21 : WMI EVENT MONITORING [WmiEvent]-->
        </WmiEvent>

        <DnsQuery onmatch="include">
            <!--SYSMON EVENT ID 19 & 20 & 21 : WMI EVENT MONITORING [WmiEvent]-->
        </DnsQuery>

        <!--SYSMON EVENT ID 255 : ERROR-->
    </EventFiltering>
</Sysmon>
"@ > "$Env:programfiles\Sysmon\sysmon-net-only.xml"


& "$Env:programfiles\Sysmon\Sysmon64.exe" -accepteula -i "$Env:programfiles\Sysmon\sysmon-net-only.xml"

$InstalledBeatsVersion = ""
[bool] $DownloadWinlogbeat = $false

# Check for fresh install or pre-7.17 install
if (-not (Test-Path "$Env:programfiles\Winlogbeat-BeaKer\winlogbeat.exe" -PathType Leaf)) {
    $DownloadWinlogbeat = $true
  
    # Create install directory if it doesn't exist
    if (-not (Test-Path "$Env:programfiles\Winlogbeat-BeaKer" -PathType Container)) {
        mkdir "$Env:programfiles\Winlogbeat-BeaKer" > $null
    }
  
    # Check if this is a pre-7.17 upgrade install
    if ((Test-Path "$Env:programfiles\winlogbeat-7*" -PathType Container)) {
        ### Make sure that Beats is upgraded to 7.17 before installing v8.x
        # Install winlogbeat 7.17.9 if the current version is less than 8.x
        if (!$OverrideBeatsVersion) {
            $BeatsVersion = "7.17.9"
        }
        Copy-Item "$Env:programfiles\winlogbeat-7*\winlogbeat.yml" "$Env:programfiles\Winlogbeat-BeaKer"
    }
}
else {
    # Check if currently installed version is outdated
    $InstalledBeatsVersion = (& "$Env:programfiles\Winlogbeat-BeaKer\winlogbeat.exe" version | Select-String -Pattern "(?<=winlogbeat version )(\d+\.\d+\.\d+)").Matches.Value
    if ($null -eq ("$InstalledBeatsVersion" -as [System.Version])) {
  
        if (!$OverrideBeatsVersion) {
            throw "Unable to retrieve installed winlogbeat version"
        }
        else {
            Write-Output "Unable to retrieve installed winlogbeat version, continuing anyway"
            $DownloadWinlogbeat = $true
        }
    }
    else {
        if ([System.Version]"$InstalledBeatsVersion" -lt [System.Version]"$BeatsVersion") {
            $DownloadWinlogbeat = $true
        }
    }
}
    
# Download winlogbeat and move it to install directory
if ($DownloadWinlogbeat) {
    Write-Output "######## Downloading winlogbeat version $BeatsVersion ########"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -OutFile WinLogBeat.zip https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-"$BeatsVersion"-windows-x86_64.zip
    Expand-Archive .\WinLogBeat.zip
    rm .\WinLogBeat.zip
    rm .\WinLogBeat\winlogbeat*\winlogbeat.yml

    # Stop winlogbeat service if it exists 
    if (Get-Service winlogbeat -ErrorAction SilentlyContinue) {
        Stop-Service winlogbeat
        (Get-Service winlogbeat).WaitForStatus('Stopped')
        Start-Sleep -s 1
    }
    Copy-Item -Path .\WinLogBeat\winlogbeat*\* -Destination "$Env:programfiles\Winlogbeat-BeaKer\" -Recurse -Force
    rm .\Winlogbeat -Recurse
}

Write-Output "######## Installing winlogbeat version $BeatsVersion ########"


# Begin winlogbeat configuration
Set-Location "$Env:programfiles\Winlogbeat-BeaKer\"

# Backup winlogbeat config if it exists
if (Test-Path -PathType Leaf .\winlogbeat.yml) {
    if ($DownloadWinlogbeat) {
        # Backup config with its version in the name if upgrading to a new Beats version
        # so that the config isn't overwritten by subsequent upgrades. This is useful in case
        # breaking changes between configurations need to be referenced in the future for troubleshooting
        Copy-Item .\winlogbeat.yml .\winlogbeat-$InstalledBeatsVersion-old.yml.bak
    }
    else {
        Copy-Item .\winlogbeat.yml .\winlogbeat.yml.bak
    }
}

.\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore create
if ($ESUsername) {
    Write-Output "$ESUsername" | .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_USERNAME --stdin
}
else {
    .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_USERNAME
}
if ($ESPassword) {
    Write-Output "$ESPassword" | .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_PASSWORD --stdin
}
else {
    .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_PASSWORD
}

# Set ACL's of the $Env:ProgramData\winlogbeat folder to be the same as $Env:ProgramFiles\winlogbeat* (the main install path)
# This helps ensure that "normal" users aren't able to access the $Env:ProgramData\winlogbeat folder
Get-ACL -Path "$Env:ProgramFiles\\Winlogbeat-BeaKer*" | Set-ACL -Path "$Env:ProgramData\\winlogbeat"

rm .\winlogbeat.yml

if ([System.Version]$BeatsVersion -lt [System.Version]"8.0.0") {
    Write-Output @"
winlogbeat.event_logs:
  - name: Microsoft-Windows-Sysmon/Operational
    event_id: 3
    processors:
      - drop_event:
          when:
            network:
              destination.ip: ['0.0.0.0/32', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8', '169.254.0.0/16', '224.0.0.0/4', '255.255.255.255/32', 'fe80::/10']
      - script:
          lang: javascript
          id: sysmon
          file: ${path.home}/module/sysmon/config/winlogbeat-sysmon.js

setup.ilm.enabled: false
setup.template.name: `"winlogbeat-%{[agent.version]}`"
setup.template.pattern: `"winlogbeat-%{[agent.version]}`"

output.elasticsearch:
  hosts:
    - https://${ESHost}:${ESPort}
  index: `"winlogbeat-%{[agent.version]}`"
  username: `"`${ES_USERNAME}`"
  password: `"`${ES_PASSWORD}`"
  ssl:
    enabled: true
    verification_mode: none
"@ > winlogbeat.yml
}
else {
    Write-Output @"
winlogbeat.event_logs:
    - name: Microsoft-Windows-Sysmon/Operational
      event_id: 3

setup.ilm.enabled: false

output.elasticsearch:
  hosts:
    - https://${ESHost}:${ESPort}
  pipeline: winlogbeat-%{[agent.version]}-routing
  username: `"`${ES_USERNAME}`"
  password: `"`${ES_PASSWORD}`"
  ssl:
    enabled: true
    verification_mode: none
"@ > winlogbeat.yml
}

PowerShell.exe -ExecutionPolicy UnRestricted -File .\install-service-winlogbeat.ps1

Start-Service winlogbeat
