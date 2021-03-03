## Features

 * Installs and updates Steam apps on container startup.
 * Drops privileges to a configurable UID and GID.

## Usage

 1. Set `STEAMCMD_APP_ID` to the Steam ID of the app you want to install.
 2. Set `USER_UID` and `USER_GID` to match the user on your host.
 2. Map `/data` to a volume.
 3. Map your ports as appropriate.
 4. Prefix the container command with `steamcmd-run`.

## Authentication

If authentication is required, specify the username and password separated by a space via `STEAMCMD_LOGIN` (defaults to `anonymous`).

Note that SteamGuard is not yet supported, but is planned.

## Beta versions

Use the `STEAMCMD_BETA` environment variable to specify which beta version to install with the password specified by `STEAMCMD_BETA_PASSWORD` if required.

## Validation

By default steamcmd is instructed to validate installed files, which does incur a delay when starting a container. Set `STEAMCMD_NO_VALIDATE` to disable validation, though it's not generally advisable.

## Skipping update

If you're absolutely sure you want to skip running steamcmd after initial installation, you can set `STEAMCMD_SKIP` to do so. Note that you will need to run without this flag at least once in order to download the app in the first place.

## Known limitations

 * No support for SteamGuard, yet.
 * No support for `app_set_config`.

## Disclaimer

These containers are designed to be used by Zobees to host game servers for friends and family, and therefore may not suit all use cases.  That said, we are all for flexibility and would welcome pull requests and issues.
