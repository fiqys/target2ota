# target2ota

Turns a target-files zip into a flashable, block-based OTA zip
for legacy (non-A/B) and A/B schemed devices.

Build-system from [UN1CA](https://github.com/salvogiangri/UN1CA)
(Salvo Giangreco). This repo is heavily inspired from UN1CA build_flashable_zip.sh and it just a trimmed version for general purposes.

Licensed GPL-3.0-or-later, see [LICENSE](LICENSE).

## Setup environment

```console
$ source env.sh
```

## Limitations

- `-i/--incremental` is not implemented yet.
