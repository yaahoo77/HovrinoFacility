# Files uploaded in Lovable

Audio and images that were uploaded in the Lovable editor are not part of the website's repository: Lovable keeps them on its own server. `tools/build-site.sh` copies them from this folder into `site/`, so they also work on your own server.

Keep each file here under its original name (the `original_filename` in the website's `src/assets/*.asset.json`), for example `ward14.wav`. If a file is missing, the build prints `MISSING: <name>`. You can then copy it here, or let the script download it from your published Lovable site:

```bash
LOVABLE_SITE=https://your-site.lovable.app bash tools/build-site.sh HovrinoFacilitySite
```
