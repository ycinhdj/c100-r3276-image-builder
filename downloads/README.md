# NVIDIA release archives

The builder downloads the following official NVIDIA files into this directory:

- `Jetson-210_Linux_R32.7.6_aarch64.tbz2`
- `Tegra_Linux_Sample-Root-Filesystem_R32.7.6_aarch64.tbz2`
- `public_sources.tbz2`
- `overlay_32.7.5_PCN211181.tbz2`

The files are not redistributed by this repository. Existing valid archives and
partial downloads are reused automatically.

Download without building:

```bash
bash ./build.sh --accept-nvidia-license --install-deps --download-only
```

For an offline build, place the four archives here and run:

```bash
bash ./build.sh --skip-download --clean
```
