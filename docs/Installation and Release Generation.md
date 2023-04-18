# Installation and Release Generation

## Generating a Release on Github

### Updating ELK Components
1. Update `ELK_VERSION` with the ELK stack version(s) to include in the release, one per line. They must be in ascending order.
2. Update `ELK_STACK_VERSION` in `./agent/install-sysmon-beats.ps1`.
3. For each included ELK version, install WinLogBeat and export the index template and ingest pipelines for each version.
  - Run `.\winlogbeat.exe --path.data C:\ProgramData\winlogbeat export pipelines --es.version=7.16.0` 
    - Refer to the [WinLogBeat Documentation](https://www.elastic.co/guide/en/beats/winlogbeat/current/load-ingest-pipelines.html) for which `--es.version` to pass into this command.
  - Run `.\winlogbeat.exe export template --es.version [winlogbeat-version] | Out-File -Encoding UTF8 winlogbeat-[winlogbeat-version].template.json`
  - Put each template & ingest pipeline in `./installer/stage/BeaKer/elasticsearch/templates`.
  - Delete templates and pipelines from older ELK versions that are no longer included in the release.
  - Edit each index template to:
    - Include `"winlogbeat-[winlogbeat-version]"` within the `index_patterns` array (if it doesn't already)
    - Include a top-level `data_stream` key
    - Include `"aliases":{ "winlogbeat": {} }` within the `template` object
    - Include `"lifecycle":{ "name": "beaker" }` within the `template.settings.index` object

### One-Time Release

1. Create a new [GitHub release](https://github.com/activecm/BeaKer/releases)
  - Name both the tag and the release with the version (e.g. `v1.0.0`)
  - Optionally upload assets to be included (*see below)
2. Publish the release. After a few minutes the assets will be automatically generated and attached to the release.

*Optional manual asset generation

Even if you do not attach any assets to a release they will be automatically generated and uploaded for you. If needed, you can upload `BeaKer.tar` manually before publishing the release. Run the script `installer/generate_installer.sh` on a clean working directory to generate `BeaKer.tar` (see the [`generate_installer.sh`](#generate_installersh) section below for more information on this script).

### Pre-Releases

1. Create a new [GitHub release](https://github.com/activecm/BeaKer/releases)
  - Name the tag with the current release candidate revision (e.g. `v1.0.0-rc1`)
  - Name the release with the version (e.g. `v1.0.0`)
  - Check the box to mark the release as a pre-release

![image](https://user-images.githubusercontent.com/1696711/80836467-6d2c0200-8bba-11ea-9629-168ddb4442fc.png)

2. Publish the release. After a few minutes the assets will be automatically generated and attached to the release.

![image](https://user-images.githubusercontent.com/1696711/80836790-212d8d00-8bbb-11ea-920a-b6c2baec79bb.png)

**For subsequent test releases:**

3. Edit the release and perform the following:
  - Edit the release message. This usually means adding the new change's summary to the changelog.
  - Increment the version tag to be the next rc revision (e.g. `v1.0.0-rc2`). This ensures new changes in master will be included.
  - Delete the existing `BeaKer.tar` asset that is attached (and any other assets). This ensures the asset will be regenerated.
  - Save the changes to the pre-release.

![image](https://user-images.githubusercontent.com/1696711/80836844-373b4d80-8bbb-11ea-90ae-0f9da6fd24a3.png)

4. Repeat step 3 as needed.

**When ready to publish a final version:**

5. Edit the release. Since no further changes have been made there is no need to edit the release message or regenerate `BeaKer.tar` or other assets. The latest release candidate has now become the final version so all that remains is adding the final version tag.
  - Change the version tag and remove the rc revision (e.g. `v1.0.0-rc2` -> `v1.0.0`).
  - Uncheck the pre-release box and publish the release.

![image](https://user-images.githubusercontent.com/1696711/80836917-5fc34780-8bbb-11ea-98f2-d80915379ea9.png)

### Notes

The steps above were written with the following behaviors in mind. Use these as a reference if you need to troubleshoot, modify the workflow, or Github's behavior changes.

- An installer `BeaKer.tar` is generated and uploaded as a release asset whenever a release is created or edited. This is triggered by the `release.yml` workflow.
- This does not apply to "draft" releases. But it applies to pre-releases.
- When you first create a release you make a tag from a specific branch. Even if you edit the content of a release later it keeps the original tag referencing the original commit. This means that if you add new commits to the branch, you will need to create a new tag in order to have the release inclued the new commits.
- In order to trigger the "edited" event in the workflow you have to actually change the release message.
- If the `BeaKer.tar` asset already exists in a release it will not be replaced. In order to have it regenerated and replaced you need to delete the `BeaKer.tar` file when editing the release.
- Check https://github.com/activecm/BeaKer/actions/ if your release is not being automatically generated to troubleshoot.
- Updating the `release.yml` workflow seems to only apply in the master branch. If you need to debug or make changes to the workflow it is best to fork the repository and test there first.

## Component Overview

### `install_beaker.sh`

`install_beaker.sh` installs Docker, Docker-Compose, and the BeaKer server on the local machine.

```bash
installer/stage/install_beaker.sh
```

### `stage`

The stage folder holds exactly one folder which will be what the user sees when they unpack the corresponding tarball.

In order to add a file to the release tarball, either create a file inside the `stage` directory, or symlink it in with `ln -s`.

You can also modify the `generate_installer.sh` script to download or generate a file in the `stage` directory, but then be sure you add the name of this file to the `stage/.gitignore` file to avoid committing it.

### `generate_installer.sh`

The stage directory is built into a corresponding tarball by the accompanying `generate_installer.sh` file.

```bash
installer/generate_installer.sh
```

#### Detailed Usage

By default, the script will pull all latest base images from the remote container repos and then force a local rebuild from scratch (i.e. not using the cache). This reasonably ensures everything is up to date and there are no issues caused by caching. It doesn't (yet) prevent you from having uncomitted or untagged changes to your local source code so beware of this.

Additionally, the installer script has options that can be used to speed up development or testing the installer archives generated.

```
  --use-cache   Builds Docker images using the local cache.
  --no-pull     Do not pull the latest base images from the container
                repository during the build process.
  --no-build    Do not build Docker images from scratch. This requires
                you to have the images already built on your system. (Implies --no-pull)
```

For instance, if you just finished manually building your images that you want to test you can generate an installer that uses those instead of rebuilding its own.

```bash
scripts/installer/generate_installer.sh --no-build
```

Or if you want to have the installer do a fresh build but you are fine speeding the process up by using the local build cache and don't care to fetch the latest remote images you can run it this way.

```bash
scripts/installer/generate_installer.sh --use-cache --no-pull
```
