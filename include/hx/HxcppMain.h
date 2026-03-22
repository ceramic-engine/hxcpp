// External targets can provide platform-specific code via HxcppMainAddon.h
// Set HXCPP_MAIN_ADDON in toolchain and add include path to addon header
#if defined(HXCPP_MAIN_ADDON)
#include <hx/HxcppMainAddon.h>
#endif

// On Windows, install a Vectored Exception Handler to write a minidump
// when the process crashes (e.g. during CRT static destruction at exit).
// VEH is called before frame-based SEH handlers, so it works even during
// CRT teardown where SetUnhandledExceptionFilter would not be invoked.
#if defined(HX_WINDOWS) && !defined(HX_WINRT) && !defined(HXCPP_DLL_IMPORT)
#include <windows.h>
#include <dbghelp.h>
#pragma comment(lib, "dbghelp.lib")
static LONG CALLBACK hxcppVEHHandler(EXCEPTION_POINTERS* ep) {
    if (ep->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    fprintf(stderr, "HXCPP CRASH: Access violation at address %p\n",
        ep->ExceptionRecord->ExceptionAddress);
    fflush(stderr);
    // Capture stack trace first — CaptureStackBackTrace is a kernel32 function
    // that doesn't depend on CRT state, so it's more likely to succeed.
    void* stack[64];
    USHORT frames = CaptureStackBackTrace(0, 64, stack, NULL);
    fprintf(stderr, "Stack frames (%d):\n", frames);
    for (USHORT i = 0; i < frames; i++)
        fprintf(stderr, "  [%d] %p\n", i, stack[i]);
    fflush(stderr);
    // Attempt to write a minidump (depends on dbghelp.dll, may fail during CRT teardown)
    HANDLE hFile = CreateFileA("crashdumps\\crash.dmp", GENERIC_WRITE, 0,
        NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        fprintf(stderr, "Failed to create crash dump file (error %lu)\n", GetLastError());
        fflush(stderr);
    } else {
        MINIDUMP_EXCEPTION_INFORMATION mei;
        mei.ThreadId = GetCurrentThreadId();
        mei.ExceptionPointers = ep;
        mei.ClientPointers = FALSE;
        BOOL ok = MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(),
            hFile, (MINIDUMP_TYPE)(MiniDumpWithFullMemory), &mei, NULL, NULL);
        CloseHandle(hFile);
        if (ok) {
            fprintf(stderr, "Minidump written to crashdumps\\crash.dmp\n");
        } else {
            fprintf(stderr, "MiniDumpWriteDump failed (error %lu)\n", GetLastError());
        }
        fflush(stderr);
    }
    // Force exit with error code so CI detects the failure
    _exit(1);
    return EXCEPTION_CONTINUE_SEARCH;
}
static struct HxcppCrashHandlerInit {
    HxcppCrashHandlerInit() { AddVectoredExceptionHandler(1, hxcppVEHHandler); }
} _hxcppCrashHandlerInit;
#endif

#ifdef HXCPP_DLL_IMPORT

   extern "C" EXPORT_EXTRA void __main__()
   {
     __boot_all();
     __hxcpp_main();
   }

#elif defined(HX_ANDROID) && !defined(HXCPP_EXE_LINK)

   // Java Main....
   #include <jni.h>
   #include <hx/Thread.h>
   #include <android/log.h>

   extern "C" EXPORT_EXTRA void hxcpp_main()
   {
      HX_TOP_OF_STACK
      try
      {
         hx::Boot();
         __boot_all();
         __hxcpp_main();
      }
      catch (Dynamic e)
      {
         __hx_dump_stack();
         __android_log_print(ANDROID_LOG_ERROR, "Exception", "%s", e==null() ? "null" : e->toString().__CStr());
      }
      hx::SetTopOfStack((int *)0,true);
   }

   extern "C" EXPORT_EXTRA JNIEXPORT void JNICALL Java_org_haxe_HXCPP_main(JNIEnv * env)
   {
      hxcpp_main();
   }

#elif defined(HX_WINRT) && defined(__cplusplus_winrt)

   #include <Roapi.h>
   [ Platform::MTAThread ]
   int main(Platform::Array<Platform::String^>^)
   {
      HX_TOP_OF_STACK
      RoInitialize(RO_INIT_MULTITHREADED);
      hx::Boot();
      try
      {
         __boot_all();
         __hxcpp_main();
      }
      catch (Dynamic e)
      {
         __hx_dump_stack();
         return -1;
      }
      return 0;
   }

#else

   #if defined(HX_WIN_MAIN) && !defined(_WINDOWS_)
   #ifndef HINSTANCE
   #define HINSTANCE void*
   #endif
   #ifndef LPSTR
   #define LPSTR char*
   #endif
   extern "C" int __stdcall MessageBoxA(void *,const char *,const char *,int);
   #endif


   #if defined(TIZEN)
   extern "C" EXPORT_EXTRA int OspMain (int argc, char* pArgv[])
   {
   #elif defined(HX_WIN_MAIN)
   int __stdcall WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
   {
   #else

   extern int _hxcpp_argc;
   extern char **_hxcpp_argv;
   int main(int argc,char **argv)
   {
      _hxcpp_argc = argc;
      _hxcpp_argv = argv;
   #endif
      HX_TOP_OF_STACK
      hx::Boot();
      try
      {
         __boot_all();
         __hxcpp_main();
      }
      catch (Dynamic e)
      {
          auto customStack = e->__Field(HX_CSTRING("_hx_customStack"), HX_PROP_DYNAMIC).asString();
          if (::hx::IsNotNull(customStack))
          {
              printf("%s\n", customStack.utf8_str());
          }
          else
          {
              __hx_dump_stack();
          }

#ifdef HX_WIN_MAIN
          MessageBoxA(0, e == null() ? "null" : e->toString().__CStr(), "Error", 0);
#else
          printf("Error : %s\n", e == null() ? "null" : e->toString().__CStr());
#endif
          return -1;
      }
      return 0;
   }
   #if 0
   }
   }
   #endif

#endif


