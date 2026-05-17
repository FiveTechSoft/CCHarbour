# Getting started

## Requirements

- **Harbour** 3.2
- **Windows** — the console layer uses Win32 APIs directly
- A C toolchain: **Visual Studio** (MSVC) for the local build, or
  **mingw-w64** (used by CI)

## Download

Grab `cc.exe` from the
[latest release](https://github.com/FiveTechSoft/CCHarbour/releases/latest).
Release binaries are built fully static — no extra DLLs required.
You can also inspect CI builds in
[GitHub Actions](https://github.com/FiveTechSoft/CCHarbour/actions/workflows/build.yml).

## Build from source

```bat
build.bat
```

`build.bat` locates a Visual Studio toolchain and forces dynamic-CRT linking —
the shipped `msvc64` Harbour libraries were built against `/MD`, so a default
static-CRT link leaves CRT import symbols unresolved. It produces `cc.exe`.

## Run

```bat
set DEEPSEEK_API_KEY=sk-...
cc.exe
```

Optional: `cc.exe <model>` overrides the model, and the `DEEPSEEK_MODEL`
environment variable does the same.

Once running, type a request to talk to the assistant, or a
[command](commands.md) such as `/help`.
