# Pixel 3a XL Docker kernel builder

This GitHub Actions project clones the LineageOS Pixel 3a/3a XL Linux 4.9 kernel,
enables Docker/container kernel options, attempts the Android `xt_qtaguid`
workaround, compiles the kernel, and uploads the output as a workflow artifact.

## Run it

1. Create a new **private** GitHub repository. Do not initialise it with a README.
2. Upload all files from this folder, preserving `.github/workflows/build-kernel.yml`.
3. Commit the files to the default branch.
4. Open **Actions** → **Build bonito Docker kernel** → **Run workflow**.
5. Leave `kernel_ref` as `lineage-22.2` for the first attempt.
6. After the run finishes, open the run and download the artifact at the bottom.

The artifact should contain a kernel image, `vmlinux`, the resolved `.config`, and
any generated modules. GitHub workflow artifacts are downloaded from the workflow
run page.

## Important

The raw `Image`, `Image.gz-dtb`, or `Image.lz4-dtb` is **not a flashable boot.img**.
It must be inserted into a boot image taken from the exact LineageOS build already
installed on the phone. Test a repacked image first with:

```bash
fastboot boot docker-boot.img
```

Do not permanently flash it until temporary booting and ADB both work.

## Matching your installed kernel

The safest source is the exact branch and preferably exact commit used by your
installed LineageOS build. The workflow accepts a branch, tag, or commit in
`kernel_ref`. A shallow branch clone cannot directly check out an arbitrary commit;
if you later need a precise commit, edit the clone step to fetch that commit.

## If the build fails

Open the failed red step and copy the final 100–200 lines of its log. Old Android
4.9 kernels sometimes require a slightly different Android Clang revision or a
small source compatibility patch.
