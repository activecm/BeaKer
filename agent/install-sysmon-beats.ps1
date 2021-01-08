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

.PARAMETER ESCredential
The username and password used to authenticate to the Elasticsearch server. If a powershell
credential object is not specified, the script will ask for the credentials at runtime.

.EXAMPLE
# Asks for Elasticsearch authentication details at runtime
.\install-sysmon-beats.ps1 my-es-host.com 9200

.NOTES
The Elasticsearch credentials are stored locally using Elastic Winlogbeat's secure
storage facilities. They can be passed into the script as a credential object as follows:
$Cred = (Get-Credential -UserName example-username)
.\install-sysmon-beats.ps1 my-es-host.com 9200 $Cred
#>

param (
    [Parameter(Mandatory=$true)][string]$ESHost,
    [string]$ESPort="9200",
    [ValidateNotNull()][System.Management.Automation.PSCredential][System.Management.Automation.Credential()] $ESCredential = [System.Management.Automation.PSCredential]::Empty 
    
)

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))  
{  
  $arguments = "& '" +$myinvocation.mycommand.definition + "'", $args
  Start-Process powershell -Verb runAs -ArgumentList $arguments
  Break
}

if($ESCredential.username -eq $null)
{
    $ESUsername=Read-Host "Elasticsearch username"
    $ESPassword=Read-Host "Elasticsearch password" -AsSecureString
    $ESCredential=New-Object System.Management.Automation.PSCredential -ArgumentList $ESUsername, $ESPassword

}

if (-not (Test-Path "$Env:programfiles\Sysmon" -PathType Container)) {
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


& "$Env:programfiles\Sysmon\Sysmon64.exe" -accepteula -i "$Env:programfiles\Sysmon\sysmon-net-only.xml" 2>&1 | %{ "$_" }

if (-not (Test-Path "$Env:programfiles\winlogbeat*" -PathType Container)) {
  Invoke-WebRequest -OutFile WinLogBeat.zip https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-7.5.2-windows-x86_64.zip
  Expand-Archive .\WinLogBeat.zip
  rm .\WinLogBeat.zip
  mv .\WinLogBeat\winlogbeat* "$Env:programfiles"
}

cd "$Env:programfiles\winlogbeat*\"
.\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore create
if($ESCredential.UserName -ne $null) {
  Write-Output $ESCredential.UserName | .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_USERNAME --stdin
} else {
  .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_USERNAME
}
if($ESCredential.GetNetworkCredential().Password -ne $null) {
  Write-Output $ESCredential.GetNetworkCredential().Password | .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_PASSWORD --stdin
} else {
  .\winlogbeat.exe --path.data "C:\ProgramData\winlogbeat" keystore add ES_PASSWORD
}

rm .\winlogbeat.yml
echo @"
winlogbeat.event_logs:
  - name: Microsoft-Windows-Sysmon/Operational
    event_id: 3
    processors:
      - script:
          lang: javascript
          id: sysmon
          file: ${path.home}/module/sysmon/config/winlogbeat-sysmon.js

setup.ilm.enabled: false
setup.template.enabled: true
setup.template.name: `"sysmon`"
setup.template.pattern: `"sysmon-*`"

output.elasticsearch:
  hosts:
    - https://${ESHost}:${ESPort}
  index: `"sysmon-%{+YYYY.MM.dd}`"
  username: `"`${ES_USERNAME}`"
  password: `"`${ES_PASSWORD}`"
  ssl:
    enabled: true
    verification_mode: none
"@ > winlogbeat.yml
PowerShell.exe -ExecutionPolicy UnRestricted -File .\install-service-winlogbeat.ps1
Start-Service winlogbeat