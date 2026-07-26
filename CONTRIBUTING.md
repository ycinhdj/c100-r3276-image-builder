# Contributing

## Development requirements

- Bash
- ShellCheck
- Git

Run the local checks before submitting a change:

```bash
bash ./scripts/check.sh
bash ./scripts/check-upstream-patch.sh
```

## Release inputs

Versions, commits, filenames, and URLs belong in `config/release.env`.
Source changes for the pinned `c100-bootupd` revision belong in numbered patches
under `patches/c100-bootupd/`.

A release change should include:

1. matching versions in `VERSION` and `config/release.env`;
2. documentation updates for user-visible behavior;
3. a successful clean-workspace build;
4. SHA-256 checksums for published archives.

Do not commit NVIDIA archives, prepared BSP trees, generated images, private
keys, or credentials.
