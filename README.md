# AutoRemesher

AutoRemesher is a cross-platform automatic quad remeshing tool that converts high-polygon meshes into clean quad-based topology. It is built on top of [Geogram](https://github.com/BrunoLevy/geogram), [Eigen](https://gitlab.com/libeigen/eigen), [Intel TBB](https://github.com/oneapi-src/oneTBB), [isotropicremesher](https://github.com/huxingyi/isotropicremesher) and [others](https://github.com/huxingyi/autoremesher/blob/master/ACKNOWLEDGEMENTS.html). Bundled dependency versions and licenses are listed in [`thirdparty/README.md`](thirdparty/README.md).

Buy me a coffee for staying up late coding :-) [![](https://www.paypalobjects.com/en_US/i/btn/btn_donate_SM.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=GHALWLWXYGCU6&item_name=Support+me+coding+in+my+spare+time&currency_code=AUD&source=url)

<img width="3644" height="2202" alt="autoremesher-1 0-screenshot" src="https://github.com/user-attachments/assets/47851f1e-127c-49af-81b7-0c8ac06fb3ad" />

## Getting Started

These instructions will get you a copy of **AutoRemesher** up and running on your local machine for development.

### Prerequisites

- C++ compiler with C++14 support (GCC, Clang, or MSVC)
- Qt 5.15.2
- TBB (Intel Threading Building Blocks) — installed from a package manager on
  Linux/macOS, or built from the bundled source on Windows
- CMake 3.12 or later (only needed on Windows, to build TBB from source)

### Building

#### Linux (Ubuntu/Debian)

```bash
# Install Qt and build tools
sudo apt install build-essential qt5-qmake qtbase5-dev qttools5-dev-tools libqt5svg5-dev libqt5multimedia5-dev

# Install TBB and OpenGL
sudo apt install libtbb-dev libgl1-mesa-dev

# Clone and build
git clone https://github.com/huxingyi/autoremesher.git
cd autoremesher
qmake
make -j$(nproc)
```

> **Fedora:** `sudo dnf install gcc-c++ qt5-qtbase-devel qt5-qttools-devel tbb-devel mesa-libGL-devel`

#### Windows (Visual Studio 2022)

1. Install [Visual Studio 2022](https://visualstudio.microsoft.com/) with **Desktop development with C++** workload.
2. Install [CMake](https://cmake.org/download/) (required to build TBB from source).
3. Install Qt 5.15.2 with the [online installer](https://www.qt.io/download-open-source) — select the `msvc2019_64` archive.
4. Open a **x64 Native Tools Command Prompt for VS 2022** and run:

```cmd
:: Build TBB from the bundled third-party source
cd thirdparty\tbb
cmake -B build2 ^
    -DTBB_BUILD_SHARED=ON ^
    -DTBB_BUILD_STATIC=OFF ^
    -DTBB_BUILD_TBBMALLOC=OFF ^
    -DTBB_BUILD_TBBMALLOC_PROXY=OFF ^
    -DTBB_BUILD_TESTS=OFF
cmake --build build2 --config Release
cd ..\..

:: Build AutoRemesher
qmake -spec win32-msvc
set CL=/MP
nmake -f Makefile.Release
```

The release binary will be at `release\autoremesher.exe`.

#### macOS

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install dependencies via Homebrew (TBB is prebuilt; CMake is not needed on macOS)
brew install qt@5 tbb

# Build
# Works on both Apple Silicon (/opt/homebrew) and Intel (/usr/local) Macs
export PATH="$(brew --prefix qt@5)/bin:$PATH"
git clone https://github.com/huxingyi/autoremesher.git
cd autoremesher
qmake CONFIG+=sdk_no_version_check
make -j$(sysctl -n hw.logicalcpu)
```

> **`qmake: command not found`?** Homebrew does not link `qt@5` onto your `PATH` by
> default. The `export PATH="$(brew --prefix qt@5)/bin:$PATH"` line above fixes it for
> the current shell — make sure you run it before `qmake`.

> **`make: Nothing to be done for 'first'`?** This is not an error — it means the app is
> already built (look for `autoremesher.app`). To force a clean rebuild, run
> `make distclean` first, then re-run `qmake CONFIG+=sdk_no_version_check` and `make`.

> **`ld: warning: building for macOS-11.0, but linking with dylib ... built for newer
> version`?** Harmless. Homebrew builds TBB for your current macOS while AutoRemesher
> targets an older minimum, so the linker just notes the mismatch — the build succeeds
> and the binary runs.

### Running a quick test

AutoRemesher has a CLI mode for headless processing. Try it with one of the [common-3d-test-models](https://github.com/alecjacobson/common-3d-test-models). Use the binary produced by your build:

- **Linux:** `./autoremesher`
- **macOS:** `./autoremesher.app/Contents/MacOS/autoremesher`
- **Windows:** `release\autoremesher.exe`

```bash
./autoremesher \
    --input armadillo.obj \
    --output remeshed.obj \
    --report remeshed_report.txt \
    --target-quads 50000 \
    --edge-scaling 1.0 \
    --sharp-edge 90.0 \
    --smooth-normal 0.0 \
    --adaptivity 1.0
```

#### Command-line options

| Option | Argument | Default | Notes |
|--------|----------|---------|-------|
| `-i`, `--input` | `<file.obj>` | — | Input triangle mesh. Enables headless mode. |
| `-o`, `--output` | `<file.obj>` | — | Output quad mesh. Required when `--input` is given. |
| `--report` | `<file.txt>` | *(none)* | Optional run report (quads, non-quads, vertices, time). |
| `--target-quads` | integer | `50000` | Approximate target quad count. Must be positive. |
| `--edge-scaling` | float | `1.0` | Edge length scaling. Range `1.0`–`4.0`. |
| `--sharp-edge` | degrees | `90.0` | Dihedral angle above which an edge is treated as sharp. Range `30`–`180`. |
| `--smooth-normal` | degrees | `0.0` | Normal-smoothing angle for low-poly output. Range `0`–`180`. |
| `--adaptivity` | float | `1.0` | Curvature-adaptive quad density. Range `0.0`–`1.0`. |

Invalid or out-of-range arguments are rejected with a message and a non-zero exit
code; a successful remesh exits `0`. This makes the CLI safe to drive from scripts
and CI.

When `--input` is given, the tool runs headless and never opens a window. On a
display-less Linux host it automatically selects Qt's `offscreen` platform, so it
works on servers and CI with no `X`/`Wayland` display (no `xvfb` needed); on macOS
and Windows it uses the native platform. Set `QT_QPA_PLATFORM` yourself to override on
any platform.

### Running the tests

The `test/` directory contains black-box CLI tests that drive the built binary
(exit codes, argument validation, and a valid remesh producing a quad mesh):

```bash
# after building
./test/run_tests.sh                 # auto-detects the binary
./test/run_tests.sh /path/to/binary # or pass it explicitly
```

The tests open no window and need no `xvfb`; a display-less Linux host uses the
`offscreen` platform automatically.

### Quick Start

#### Windows

Download `autoremesher-<version>-win32-x86_64.zip` from [releases](https://github.com/huxingyi/autoremesher/releases), extract it and run `autoremesher.exe`.

#### macOS

Download `autoremesher-<version>.dmg` from [releases](https://github.com/huxingyi/autoremesher/releases).

*For the first time, Apple will reject to run and popup something like "can't be opened because its integrity cannot be verified". Go to System Preferences > Security & Privacy > General and under "Allow apps downloaded from" click the button to allow it.*

#### Linux

Download `autoremesher-<version>.AppImage` from [releases](https://github.com/huxingyi/autoremesher/releases).

```
$ chmod a+x ./autoremesher-<version>.AppImage
$ ./autoremesher-<version>.AppImage
```

### Links

- [Check out open-source auto-retopology tool AutoRemesher](http://www.cgchannel.com/2020/08/check-out-open-source-auto-retopology-tool-autoremesher/) **cgchannel.com**
- [A New Open-Source Auto-Retopology Tool](https://80.lv/articles/a-new-open-source-auto-retopology-tool/) **80.lv**
- [[Non-Blender] Autoremesher auto-retopology tool released](https://www.blendernation.com/2020/08/18/non-blender-autoremesher-auto-retopology-tool-released/) **blendernation.com**
- [オープンソースの新しいオートリメッシュツール Auto Remesher](https://cginterest.com/2020/08/20/%e3%82%aa%e3%83%bc%e3%83%97%e3%83%b3%e3%82%bd%e3%83%bc%e3%82%b9%e3%81%ae%e6%96%b0%e3%81%97%e3%81%84%e3%82%aa%e3%83%bc%e3%83%88%e3%83%aa%e3%83%a1%e3%83%83%e3%82%b7%e3%83%a5%e3%83%84%e3%83%bc%e3%83%ab-a/) **cginterest.com**
- [AutoRemesher 1.0.0-alpha - 超高速で高品質のクワッドポリゴン生成！Dust3D開発者によるオープンソースの自動リメッシュツール！](https://3dnchu.com/archives/autoremesher-1-0-0-alpha/) **3dnchu.com**
- [Open Source AutoRemesher released](https://cgpress.org/archives/open-source-remesher.html) **cgpress.org**
- [「autoremesher」多角形を自動でリトポしてれる無料トポロジーツール](https://modelinghappy.com/archives/30339) **modelinghappy.com**
- [Open Source Auto Remesher](https://blender-addons.org/open-source-auto-remesher/) **blender-addons.org**
- [AutoRemesher | Auto-Retopology-Tool](https://www.digitalproduction.com/2020/08/05/autoremesher-auto-retopology-tool/) **digitalproduction.com**
- [Autoremesher open source auto-retopology tool](https://blenderartists.org/t/autoremesher-open-source-auto-retopology-tool/1245131/126) **blenderartists.org**

## License

AutoRemesher is licensed under the MIT License - see the [LICENSE](https://github.com/huxingyi/autoremesher/blob/master/LICENSE) file for details.

## Acknowledgements

See the full [ACKNOWLEDGEMENTS](https://github.com/huxingyi/autoremesher/blob/master/ACKNOWLEDGEMENTS.html) for a list of libraries and resources used in this project.

The bundled third-party dependencies (versions, licenses, upstream URLs, and local
patches) are documented in [`thirdparty/README.md`](thirdparty/README.md).

<!-- Sponsors begin --><!-- Sponsors end -->
