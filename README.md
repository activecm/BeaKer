# BeaKer

## Beaconing Kibana Executable Report

BeaKer helps threat hunters track down which executable created certain network connections. It does this by collecting Microsoft Sysmon network data and aggregating it centrally using Elasticsearch. From there, the Kibana dashboard can be used to examine which executables created connections to a particular host.

### Data Collected By Sysmon Per Network Connection
- Source
  - IP Address
  - Hostname
  - Port
- Destination
  - IP Address
  - Hostname
  - Port
- Network
  - Transport Protocol
  - Application Protocol
  - Community ID
- Process
  - PID
  - Executable
  - Entity ID
- User
  - Domain
  - Name
- Timestamp

## Quick Start
Download the latest release tar file, extract it, and run `./install_beaker.sh`.

Then, on each host you want to monitor, run the powershell script at `./agent/install-sysmon-beats.ps1`.