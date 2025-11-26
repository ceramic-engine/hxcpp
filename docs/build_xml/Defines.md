Defines
-------

There are a number of standard defines you can use to control the hxcpp build.  Some of these are used by the haxe compiler, and affect then generated code.  Others apply to the build tool and affect how the code is compiled.

Defines affecting how the code is generated.  These need to be in the command line when calling haxe.

| Define                  | Meaning            |
|-------------------------|--------------------|
| *HXCPP_DEBUGGER*        | Add extra macros required by debugger.  Usually added automatically be debugger haxelib |
| *HXCPP_GC_GENERATIONAL* | Enable experimental generational garbage collector |
| *annotate_source*       | Add additional annotations to source code - useful for developing hxcpp |
| *dll_export*            | Export hxcpp runtime symbols |
| *file_extension*        | Set the extension (without the dot) of generated files.  eg "-D file_extension=mm" for objc++ code  |
| *force_native_property* | Make dynamic access of fields call property getters/setters where appropriate |
| *include_prefix*        | Place all generated include files in a sub-directory, eg "-D include_prefix=hxinc".  Useful for avoiding name clashes |
| *no-compilation*        | Generate the code, but do not compile it |
| *no-debug*              | Do not generate debug macros in code |
| *nocppiaast*            | Use legacy cppia generation instead of new more recent changes |
| *objc*                  | Generate objective-c++ classes |
| *scriptable*            | Enable extra runtime information required for scripting |



Defines affecting how the code is compiled.  These can be on the command line when calling haxe, or added via the hxcpp build environment.

| Define                  | Meaning            |
|-------------------------|--------------------|
| *HXCPP_GC_MOVING*       | Allow garbage collector to move memory to reduce fragmentation |
| *HXCPP_GC_SUMMARY*      | Print small profiling summary at end of program |
| *HXCPP_GC_DYNAMIC_SIZE* | Monitor GC times and expand memory working space if required |
| *HXCPP_GC_BIG_BLOCKS*   | Allow working memory greater than 1 Gig |
| *HXCPP_GC_DEBUG_LEVEL*  | Number 1-4 indicating additional debugging in GC |
| *HXCPP_DEBUG_LINK*      | Add symbols to final binary, even in release mode. |
| *HXCPP_STACK_TRACE*     | Have valid function-level stack traces, even in release mode. |
| *HXCPP_STACK_LINE*      | Include line information in stack traces, even in release mode. |
| *HXCPP_CHECK_POINTER*   | Add null-pointer checks,even in release mode. |
| *HXCPP_PROFILER*        | Add profiler support |
| *HXCPP_TELEMETRY*       | Add telemetry support |
| *HXCPP_CPP11*           | Use c++11 features and link libraries |
| *HXCPP_CPP17*           | Use c++17 features and link libraries |
| *exe_link*              | Generate executable file (rather than dynamic library on android) |
| *static_link*           | Generate static library |
| *dll_link*              | Generate dynamic library |

Other defines:

| Define                  | Meaning            |
|-------------------------|--------------------|
| *HXCPP_VERBOSE*         | Print extra output from build tool. |
| *HXCPP_TIMES*           | Show some basic profiling information |
| *HXCPP_NEKO_BUILDTOOL*  | Force use of hxcpp.n, rather than compiled BuildTool.exe
| *HXCPP_NO_COLOR*        | Do not add colour-codes to tool output |
| *HXCPP_KEEP_TEMP*       | Does not delete the files created for file 'embedName' option |


Defines affecting target architecture.

| Define                  | Meaning            |
|-------------------------|--------------------|
| *HXCPP_M32*             | Force 32-bit compile for current desktop |
| *HXCPP_M64*             | Force 64-bit compile for current desktop |
| *HXCPP_ARMV6*           | Compile arm-based devices for armv6 |
| *HXCPP_ARM64*           | Compile arm-based devices for 64 bits |
| *HXCPP_ARMV7*           | Compile arm-based devices for armv7 |
| *HXCPP_ARMV7S*          | Compile arm-based devices for armv7s |
| *HXCPP_LINUX_ARMV7*     | Run on a linux ARMv7 device |
| *HXCPP_LINUX_ARM64*     | Run on a linux ARM64 device |
| *winrt*                 | Compile for windowsRt/windows UWP |
| *android*               | Compile for android |
| *HXCPP_ANDROID_PLATFORM* | Specify the android platform for NDK compilation |
| *ANDROID_NDK_ROOT*      | Specify the location of the android NDK toolchain |
| *ANDROID_NDK_DIR*       | Specify the search location for finding the android NDK toolchain |
| *HXCPP_X86*             | Compile android for x86 architecture |
| *iphoneos*              | Compile for iphone iOS |
| *iphonesim*             | Compile for iphone simulator |
| *appletvos*             | Compile for apple tvOS |
| *appletvsim*            | Compile for apple tvOS simulator |
| *watchos*               | Compile for apple watchOS |
| *watchsimulator*        | Compile for apple watchOS simulator |
| *webos*                 | Compile for webOS |
| *tizen*                 | Compile for Tizen |
| *blackberry*            | Compile for Blackberry |
| *emscripten*            | Compile for Emscripten |
| *cygwin*                | Compile for windows using cygwin |
| *linux*                 | (Cross) Compile for linux |
| *rpi*                   | (Cross) Compile for raspberry pi |
| *mingw*                 | Compile for windows using mingw |
| *HXCPP_MINGW*           | Compile for windows using mingw |
| *NO_AUTO_MSVC*          | Do not detect msvc location, use the one already in the executable path |
| *HXCPP_WINXP_COMPAT*    | Remain compatible with Windows XP. Disables condition variables. No effect on ARM. |

Custom External Target System
-----------------------------

hxcpp supports loading external target toolchains from a separate folder. This allows console-specific or proprietary toolchains to be maintained separately from the main hxcpp repository.

### Usage

| Define                   | Meaning            |
|--------------------------|--------------------|
| *HXCPP_TARGET_PATHS*     | Path(s) to external target folders. Can be set via environment variable or `-D` command-line define. Multiple paths separated by `;` (Windows) or `:` (Unix). Command-line takes precedence over environment variable. |
| *HXCPP_CUSTOM_TARGET*    | Name of the custom target (e.g., `myconsole`). Sets toolchain to `<target>-toolchain.xml` and creates a define with the target name. |
| *HXCPP_CUSTOM_BINDIR*    | Output directory name for the custom target. If not specified, capitalizes first letter only (e.g., `mytarget` → `Mytarget`). |

### Example

```bash
# Using environment variable
export HXCPP_TARGET_PATHS=/path/to/custom-targets
haxelib run hxcpp Build.xml -DHXCPP_CUSTOM_TARGET=mytarget

# Using command-line define
haxelib run hxcpp Build.xml -DHXCPP_TARGET_PATHS=/path/to/custom-targets -DHXCPP_CUSTOM_TARGET=mytarget -DHXCPP_CUSTOM_BINDIR=MyTarget
```

This looks for `toolchain/mytarget-toolchain.xml` in the paths specified by `HXCPP_TARGET_PATHS`.

### Generic Feature Flags

External toolchains can use these generic flags to disable features not available on their platform. Set these in your custom toolchain XML:

| Define                    | Purpose |
|---------------------------|---------|
| *HXCPP_NO_UNISTD*         | Disable `unistd.h`, `dirent.h`, `termios.h` includes |
| *HXCPP_NO_ENVIRON*        | Disable environment variable access (`getenv`, `environ`) |
| *HXCPP_NO_LOCALE*         | Disable locale functions (`setlocale`, etc.) |
| *HXCPP_NO_FILESYSTEM*     | Disable file operations |
| *HXCPP_NO_SYSTEM*         | Disable `system()` / `sys_command()` |
| *HXCPP_NO_TERMINAL*       | Disable terminal operations (`getch`, etc.) |
| *HXCPP_NO_SOCKET*         | Disable socket networking |
| *HXCPP_NO_DLOPEN*         | Disable dynamic library loading (`dlopen`, etc.) |
| *HXCPP_NO_TM_GMTOFF*      | Use `mktime`-based GMT offset calculation (when `tm_gmtoff` unavailable) |
| *HXCPP_TIME_USE_CLOCK*    | Use `clock()` for CPU time instead of `getrusage()` |
| *HXCPP_LOCALTIME_S*       | Use `localtime_s`/`gmtime_s` instead of `localtime_r`/`gmtime_r` |
| *HXCPP_PLATFORM_NAME*     | Custom platform name returned by `Sys.systemName()` (e.g., `"MyConsole"`) |
| *HXCPP_MAIN_ADDON*        | Enable including `<hx/HxcppMainAddon.h>` for platform-specific main() additions |
| *HXCPP_DEFAULT_STATIC*    | Platform defaults to static linking (sets `static_link` unless `dll_import` or `exe_link` is set) |
| *HXCPP_DEFAULT_LIBEXTRA*  | Default library filename suffix (e.g., `.mycon` produces `libName.mycon.a`) |
| *HXCPP_GC_LARGE_DEFAULTS* | Use larger default values for GC memory pools |

### External Target Folder Structure

```
my-custom-target/
├── toolchain/
│   └── mytarget-toolchain.xml    # Toolchain configuration
├── include/
│   └── hx/
│       └── HxcppMainAddon.h      # Platform-specific main() code (optional)
└── docs/
    └── MyTarget.md               # Documentation (optional)
```

A typical toolchain XML may do something like that:
1. Set required compiler/linker flags
2. Set generic feature flags as needed
3. Optionally include `toolchain/gcc-toolchain.xml` or similar base toolchain
4. Include `toolchain/common-defines.xml` to convert flags to compiler defines
