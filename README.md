# packages

Builds and publishes evoggy's signed APT repository, served at
[evoggy.github.io/packages](https://evoggy.github.io/packages).

Applications publish their `.deb`s by attaching them to a GitHub release and
firing a `repository_dispatch` (`publish-deb`) at this repo; see
[`.github/workflows/publish-apt.yml`](.github/workflows/publish-apt.yml).
Only repositories under `evoggy/` are accepted.

Secrets: `GPG_PRIVATE_KEY` (armored, no passphrase) and `GPG_KEY_ID`.
