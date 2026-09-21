# Immich 14

**WARNING: AI slop.**

Some sort of iOS 14 oriented (iOS 13-compatible) Immich client without Flutter. Styled like iOS 14 Photos app.
Capable of spawning its own daemon to upload photos in the background. Major functionalities have been
verified on iOS 13, iOS 14, and iOS 16.

## Building Instructions

Dependencies: Theos directory structure (theos itself is unneeded), iOS 14 SDK, iOS toolchain

This is to be built on Linux only. Mac OS is not supported.

```
cd Immich && make -j16
```

To publish it under your `/srv/http/files/immich14` directory, run `make publish`.

## License

[CC0 / Public Domain](https://creativecommons.org/publicdomain/zero/1.0/)

