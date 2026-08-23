# CF Server Monitor - KernelSU Module

Android/KernelSU wrapper for `huilang-me/cfsm-agent`.

## Build

Push to `main` to get a GitHub Actions artifact.

To publish a release:

```text
git tag v1.0.0
git push origin v1.0.0
```

The workflow downloads the latest `cf-probe-linux-arm64`, packages the KernelSU module, and attaches:

- `CF-Server-Monitor-KSU.zip`
- `update.json`

to the GitHub Release.

## Configure online update

After the first release, add this line to `module.prop` if your KernelSU manager uses the module update URL field:

```properties
updateJson=https://raw.githubusercontent.com/OWNER/REPOSITORY/main/update.json
```

`OWNER/REPOSITORY` must be replaced with your actual GitHub repository.

If you prefer release-specific metadata, publish `update.json` to a stable branch/path instead of relying on a release attachment.

## Important

The module starts the agent from `boot-completed.sh`. Configuration changes made in WebUI are written atomically through `scripts/save-config.sh`.

The initial `config/config.conf` intentionally contains empty credentials. Set them from WebUI after installation.
