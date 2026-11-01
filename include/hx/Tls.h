#ifdef HX_TLS_H_OVERRIDE
// Users can define their own header to use here, but there is no API
// compatibility gaurantee for future changes.
#include HX_TLS_H_OVERRIDE
#else

#ifndef HX_TLS_INCLUDED
#define HX_TLS_INCLUDED

// Thread-local storage for the per-thread StackContext slot.
//
// Two implementations:
//
//  - HX_TLS_NATIVE: a compiler thread-local variable (__thread on gcc/clang,
//    __declspec(thread) on MSVC). Reading it is an inline TLS load, no
//    library call. This is the default on the platforms where the compiler
//    and the OS support it and make it fast: macOS, iOS 9 and later (tvOS 9,
//    watchOS 2), Linux, Windows (MSVC and MinGW), Android API 21 and later.
//
//  - the TLSData object: pthread_getspecific / TlsGetValue behind a small
//    struct. Kept for Emscripten, WinRT, older Apple deployment targets,
//    Windows DLL builds (MSVC refuses dllimport on thread-local data) and
//    anything else. Define HXCPP_TLS_PTHREAD to force it everywhere.
//
// Both paths have the same semantics: one pointer per thread, null until
// the thread registers with the GC (hx::SetTopOfStack, RegisterCurrentThread)
// and cleared again when the LocalAllocator is released. Every reader and
// writer goes through the tlsStackContext name, so the storage can change
// without touching the GC.
#if !defined(HXCPP_TLS_PTHREAD) && !defined(HX_WINRT)
   #if defined(_MSC_VER)
      #if !defined(HXCPP_DLL_IMPORT) && !defined(HXCPP_DLL_EXPORT)
         #define HX_TLS_NATIVE
         #define HX_TLS_KEYWORD __declspec(thread)
      #endif
   #elif defined(__EMSCRIPTEN__)
      // No native thread-local storage worth using: keep the pthread path.
   #elif defined(__APPLE__)
      #include <TargetConditionals.h>
      #include <Availability.h>
      #if TARGET_OS_MAC && !TARGET_OS_IPHONE
         #define HX_TLS_NATIVE
      #elif defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000
         #define HX_TLS_NATIVE
      #elif defined(__TV_OS_VERSION_MIN_REQUIRED) && __TV_OS_VERSION_MIN_REQUIRED >= 90000
         #define HX_TLS_NATIVE
      #elif defined(__WATCH_OS_VERSION_MIN_REQUIRED) && __WATCH_OS_VERSION_MIN_REQUIRED >= 20000
         #define HX_TLS_NATIVE
      #endif
      #ifdef HX_TLS_NATIVE
         #define HX_TLS_KEYWORD __thread
      #endif
   #elif defined(__ANDROID__)
      #if defined(__ANDROID_API__) && __ANDROID_API__ >= 21
         #define HX_TLS_NATIVE
         #define HX_TLS_KEYWORD __thread
      #endif
   #elif defined(__linux__) || defined(__MINGW32__) || defined(__CYGWIN__)
      #define HX_TLS_NATIVE
      #define HX_TLS_KEYWORD __thread
   #endif
#endif

#ifdef HX_WINDOWS

  #ifdef HX_WINRT
    // Nothing
  #else

   #if ! defined(__GNUC__) && !defined(__BORLANDC__)
   #include <intrin.h>
   #endif

   extern "C"
   {
      __declspec(dllimport)
     int __stdcall TlsSetValue(unsigned long  dwTlsIndex, void *lpTlsValue);

     __declspec(dllimport)
     void * __stdcall TlsGetValue(unsigned long  dwTlsIndex);

     __declspec(dllimport)
     unsigned long __stdcall TlsAlloc(void);
   }


   namespace hx {

   template<typename DATA,bool FAST=false>
   struct TLSData
   {
      static const size_t kMaxInlineSlots = 64;

      TLSData()
      {
         mSlot = TlsAlloc();
         TlsSetValue(mSlot,0);
         #ifdef HXCPP_M64
         mFastOffset = mSlot*sizeof(void *) + 0x1480;
         #else
         if (FAST || mSlot < kMaxInlineSlots)
            mFastOffset = mSlot*sizeof(void *) + 0xE10;
         else
            mFastOffset = mSlot - kMaxInlineSlots;
         #endif
      }
      inline DATA *operator=(DATA *inData)
      {
         TlsSetValue(mSlot,inData);
         return inData;
      }

      inline operator DATA *()
      {
         #if !defined(HXCPP_M64) && (_MSC_VER >= 1400)
         const size_t kTibExtraTlsOffset = 0xF94;

         if (FAST || mSlot < kMaxInlineSlots)
           return (DATA *)__readfsdword(mFastOffset);

         DATA **extra = (DATA **)(__readfsdword(kTibExtraTlsOffset));
         return extra[mFastOffset];
         #elif (_MSC_VER >= 1400) & !defined(HXCPP_DEBUG) && !defined(HXCPP_ARM64)// 64 bit version...
         if (mSlot < 64)
           return (DATA *)__readgsqword(mFastOffset);
         else
           return (DATA *)TlsGetValue(mSlot);
         #else
         return (DATA *)TlsGetValue(mSlot);
         #endif
      }

      int mSlot;
      int mFastOffset;
   };

   } // end namespace hx


   #define DECLARE_TLS_DATA(TYPE,NAME) \
      ::hx::TLSData<TYPE> NAME;
   #define DECLARE_FAST_TLS_DATA(TYPE,NAME) \
      ::hx::TLSData<TYPE,true> NAME;
   #define EXTERN_TLS_DATA(TYPE,NAME) \
      extern ::hx::TLSData<TYPE> NAME;
   #define EXTERN_FAST_TLS_DATA(TYPE,NAME) \
      extern ::hx::TLSData<TYPE,true> NAME;


  #endif
#else // not HX_WINDOWS

#include <pthread.h>

namespace hx
{

template<typename DATA,bool FAST=false>
struct TLSData
{
   TLSData()
   {
      pthread_key_create(&mSlot, 0);
   }
   DATA *Get()
   {
      return (DATA *)pthread_getspecific(mSlot);
   }
   void Set(DATA *inData)
   {
      pthread_setspecific(mSlot,inData);
   }
   inline DATA *operator=(DATA *inData)
   {
      pthread_setspecific(mSlot,inData);
      return inData;
   }
   inline operator DATA *() { return (DATA *)pthread_getspecific(mSlot); }

   pthread_key_t mSlot;
};

} // end namespace hx


#endif



#ifdef HX_WINRT

#define DECLARE_TLS_DATA(TYPE,NAME) \
   __declspec(thread) TYPE * NAME = nullptr;
#define DECLARE_FAST_TLS_DATA(TYPE,NAME) \
   __declspec(thread) TYPE * NAME = nullptr;
#define EXTERN_TLS_DATA(TYPE,NAME) \
   __declspec(thread) extern TYPE * NAME;
#define EXTERN_FAST_TLS_DATA(TYPE,NAME) \
   __declspec(thread) extern TYPE * NAME;

#elif defined(HX_TLS_NATIVE)

// Plain thread-local pointers: zero-initialised in every thread, read and
// written like any pointer, so the existing `tlsStackContext = x` and
// `(StackContext *)tlsStackContext` uses compile unchanged.
#define DECLARE_TLS_DATA(TYPE,NAME) \
   HX_TLS_KEYWORD TYPE * NAME = 0;
#define DECLARE_FAST_TLS_DATA(TYPE,NAME) \
   HX_TLS_KEYWORD TYPE * NAME = 0;
#define EXTERN_TLS_DATA(TYPE,NAME) \
   extern HX_TLS_KEYWORD TYPE * NAME;
#define EXTERN_FAST_TLS_DATA(TYPE,NAME) \
   extern HX_TLS_KEYWORD TYPE * NAME;

#else

#define DECLARE_TLS_DATA(TYPE,NAME) \
   ::hx::TLSData<TYPE> NAME;
#define DECLARE_FAST_TLS_DATA(TYPE,NAME) \
   ::hx::TLSData<TYPE,true> NAME;
#define EXTERN_TLS_DATA(TYPE,NAME) \
   extern ::hx::TLSData<TYPE> NAME;
#define EXTERN_FAST_TLS_DATA(TYPE,NAME) \
   extern ::hx::TLSData<TYPE,true> NAME;

#endif




#endif

#endif
