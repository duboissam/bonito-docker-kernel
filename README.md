# Pixel 3 XL Docker kernel builder

This GitHub Actions project clones the LineageOS Pixel 3/3 XL Linux 4.9 kernel
for the `crosshatch`/`bluecross` family, enables Docker/container kernel
options, attempts the Android `xt_qtaguid` workaround when that source file is
present, compiles the kernel, and uploads the output as a workflow artifact.

## Run it

Before running the full build, run **Actions** -> **Validate crosshatch Docker
kernel config**. That workflow only clones the kernel, applies the Docker config/source
patches, resolves `.config`, and checks required Docker symbols. It does not
compile the kernel.

1. Create a new **private** GitHub repository. Do not initialise it with a README.
2. Upload all files from this folder, preserving `.github/workflows/build-kernel.yml`.
3. Commit the files to the default branch.
4. Open **Actions** -> **Validate crosshatch Docker kernel config** -> **Run workflow**.
5. Only if validation passes, open **Actions** -> **Build crosshatch Docker kernel** ->
   **Run workflow**.
6. Leave `kernel_ref` as `lineage-22.2` for the first attempt unless your phone
   is running a different kernel branch or exact commit.
7. After the run finishes, open the run and download the artifact at the bottom.

The artifact should contain a kernel image, `vmlinux`, the resolved `.config`,
the raw module archive, and a flattened `vendor-modules.tar.gz` package for the
phone's `/vendor/lib/modules` directory. GitHub workflow artifacts are
downloaded from the workflow run page.

## Important

The raw `Image`, `Image.gz-dtb`, or `Image.lz4-dtb` is **not a flashable boot.img**.
It must be inserted into a boot image taken from the exact LineageOS build already
installed on the phone. Test a repacked image first with:

```bash
fastboot boot docker-boot.img
```

Do not permanently flash it until temporary booting and ADB both work.

## Vendor modules

Crosshatch uses loadable vendor modules for Wi-Fi and audio. Enabling Docker
kernel options changes the module version CRCs, so the stock
`/vendor/lib/modules/*.ko` files can have the same visible `vermagic` string but
still fail with errors like:

```text
wlan: disagrees about version of symbol module_layout
```

Install the matching `vendor-modules` package from the same build artifact as
the boot image:

```bash
tar -xzf vendor-modules.tar.gz
bash scripts/install_crosshatch_vendor_modules.sh vendor-modules
adb reboot
```

The install script backs up the existing phone modules under
`/data/local/tmp/vendor-modules-backup-*` before replacing files. If `adb remount`
fails, the phone may need verity disabled and a reboot before `/vendor` can be
updated.

## Matching your installed kernel

The safest source is the exact branch and preferably exact commit used by your
installed LineageOS build. The workflow accepts a branch, tag, or commit in
`kernel_ref`. A shallow branch clone cannot directly check out an arbitrary commit;
if you later need a precise commit, edit the clone step to fetch that commit.

## If the build fails

Open the failed red step and copy the final 100–200 lines of its log. Old Android
4.9 kernels sometimes require a slightly different Android Clang revision or a
small source compatibility patch.

## Current phone config check

The checked phone config was not Docker-ready yet. Required missing or
disabled features were:

- `CONFIG_IPC_NS`
- `CONFIG_PID_NS`
- `CONFIG_CGROUP_DEVICE`
- `CONFIG_CGROUP_PIDS`
- `CONFIG_BRIDGE_NETFILTER`
- `CONFIG_POSIX_MQUEUE`

Run locally with:

```bash
bash scripts/check_docker_kernel_config.sh /path/to/crosshatch-current-config
```
