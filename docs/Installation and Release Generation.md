# Installation and Release Generation

## `install_beaker.sh`

### Description
`install_beaker.sh` installs Docker, Docker-Compose, and the BeaKer server on the local machine.

### Quick Usage

```bash
installer/stage/install_beaker.sh
```

## `stage`
### Description
The stage folder holds exactly one folder which will be what the user sees when they unpack the corresponding tarball.

### Quick Usage

In order to add a file to the release tarball, either create a file inside the `stage` directory, or symlink it in with `ln -s`.

You can also modify the `generate_installer.sh` script to download or generate a file in the `stage` directory, but then be sure you add the name of this file to the `stage/.gitignore` file to avoid committing it.

## `generate_installer.sh`

### Quick Usage

```bash
scripts/installer/generate_installer.sh
```

### Description

The stage directory is built into a corresponding tarball by the accompanying `generate_installer.sh` file.

### Detailed Usage

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

## Generating a Release
- Ensure you are on the latest commit of the master branch with no uncommitted changes
- Run the script `./installer/generate_installer.sh` to generate `BeaKer.tar`
- Tag the current commit with the appropriate version
- Create a new [GitHub release](https://github.com/activecm/BeaKer/releases)
  - Use the new version tag that was just created
  - Upload the `BeaKer.tar` file that was generated