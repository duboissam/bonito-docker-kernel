# Pixel Docker kernel builder

This GitHub Actions project clones a configured Pixel Linux 4.9 kernel, enables
Docker/container kernel options, attempts the Android `xt_qtaguid` workaround
when that source file is present, compiles the kernel, and uploads the output as
a workflow artifact.

Supported device configs:

| Device config | Phone | Android codename | Defconfig |
| --- | --- | --- | --- |
| `crosshatch` | Pixel 3 XL | `crosshatch` | `b1c1_defconfig` |
| `sargo` | Pixel 3a | `sargo` | `bonito_defconfig` |
| `bonito` | Pixel 3a XL | `bonito` | `bonito_defconfig` |

## Run it

Before running the full build, run **Actions** -> **Validate Pixel Docker
kernel config** and select the target `device`. That workflow only clones the kernel, applies the Docker config/source
patches, resolves `.config`, and checks required Docker symbols. It does not
compile the kernel.


1. Open **Actions** -> **Validate Pixel Docker kernel config** -> **Run workflow**.
2. Select `crosshatch`, `sargo`, or `bonito`.
3. Only if validation passes, open **Actions** -> **Build Pixel Docker kernel** ->
   **Run workflow** with the same `device`.
4. Leave `kernel_ref` blank for the first attempt unless your phone
   is running a different kernel branch or exact commit.
5. After the run finishes, open the run and download the artifact at the bottom.

The artifact should contain a kernel image, `vmlinux`, the resolved `.config`,
the raw module archive, and a flattened `vendor-modules.tar.gz` package for the
runtime module installer. GitHub workflow artifacts are
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

These Pixels use loadable vendor modules for Wi-Fi and audio. Enabling Docker
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
bash scripts/install_runtime_fix.sh crosshatch vendor-modules
adb reboot
```

For Pixel 3a:

```bash
tar -xzf vendor-modules.tar.gz
bash scripts/install_runtime_fix.sh sargo vendor-modules
adb reboot
```

For Pixel 3a XL:

```bash
tar -xzf vendor-modules.tar.gz
bash scripts/install_runtime_fix.sh bonito vendor-modules
adb reboot
```

The runtime installer stages the matching modules under
`/data/local/tmp/<device>-docker/vendor-modules`, bind-mounts them over
`/vendor/lib/modules`, and installs boot scripts that recover Android's media
routes after the audio modules are loaded. This avoids writing the very full
vendor partition directly.

After reboot, verify media routes before testing audio:

```bash
adb shell dumpsys media_router | grep ROUTE_ID_BUILTIN_SPEAKER
```

If the route remains `DEVICE_ROUTE` with `<provider info has no routes>`, do not
debug the audio app. The kernel audio stack and Android MediaRouter are still
out of order.

The installer refuses to run if the connected phone's Android codename does not
match the selected device config. Do not flash or install crosshatch artifacts
on sargo/bonito, or sargo/bonito artifacts on crosshatch.

`scripts/install_crosshatch_vendor_modules.sh` is kept for direct crosshatch
`/vendor` installs, but the runtime installer is the safer default.

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
bash scripts/check_docker_kernel_config.sh /path/to/current-config
```
