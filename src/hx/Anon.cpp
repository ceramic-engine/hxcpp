#include <hxcpp.h>
#ifdef HXCPP_GC_CONCURRENT
#include <atomic>
#include <thread>
#endif
#undef RegisterClass
namespace hx
{

Dynamic FieldMapCreate() { return Dynamic(); }

bool FieldMapGet(FieldMap *inMap, const String &inName, Dynamic &outValue)
{
   if (!inMap || !inMap->mPtr)
      return false;

   if (!__string_hash_exists(*inMap,inName))
      return false;
   outValue = __string_hash_get(*inMap, inName);
   return true;
}


bool FieldMapGet(FieldMap *inMap, int inId, Dynamic &outValue)
{
   if (!inMap || !inMap->mPtr)
      return false;

   const String &key = __hxcpp_field_from_id(inId);
   if (!__string_hash_exists(*inMap,key))
      return false;
   outValue = __string_hash_get(*inMap, key);
   return true;
}




bool FieldMapHas(FieldMap *inMap, const String &inName)
{
   return inMap && inMap->mPtr &&  __string_hash_exists(*inMap,inName);
}


#ifdef HXCPP_GC_GENERATIONAL
void FieldMapSet(hx::Object *inThis,FieldMap *inMap, const String &inName, const Dynamic &inValue)
{
   __string_hash_set(inThis,*inMap, inName, inValue,true);
}
#else
void FieldMapSet(FieldMap *inMap, const String &inName, const Dynamic &inValue)
{
   __string_hash_set(*inMap, inName, inValue,true);
}
#endif


void FieldMapAppendFields(FieldMap *inMap,Array<String> &outFields)
{
   Array<String> keys = __string_hash_keys(*inMap);
   if (outFields->length==0)
      outFields = keys;
   else
      outFields = outFields->concat(keys);
}


// -- Anon_obj -------------------------------------------------



Anon_obj::Anon_obj(int inElements)
{
   mFixedFields = inElements;
   //mFields = hx::FieldMapCreate();
}

#ifdef HXCPP_GC_CONCURRENT
// A fixed field is a cpp::Variant: a type and a value, in two words. A write
//  that changes the type, or that moves fields (__Remove), is not atomic for a
//  concurrent marker, which could then read a type with the value of another
//  one and follow a number as a pointer.
// Such writes are bracketed by a sequence lock while a concurrent mark is
//  active, and the marker retries until it reads a stable view. The locks are
//  striped by object address, and are never held across a safe point, so they
//  are all free inside a stop-the-world pause.
#if defined(_MSC_VER)
   #define HXCPP_NOINLINE_ANON __declspec(noinline)
#else
   #define HXCPP_NOINLINE_ANON __attribute__((noinline))
#endif

namespace
{
enum { ANON_SEQ_STRIPES = 256 };
std::atomic<unsigned int> sAnonSeq[ANON_SEQ_STRIPES];

inline std::atomic<unsigned int> &anonSeq(const void *inObj)
{
   return sAnonSeq[ (((size_t)inObj)>>4) * (size_t)0x9E3779B1 >> 16 & (ANON_SEQ_STRIPES-1) ];
}

inline void anonSpinPause(int &ioSpins)
{
   if (++ioSpins > 64)
   {
      std::this_thread::yield();
      ioSpins = 0;
   }
}

struct AnonWriteLock
{
   std::atomic<unsigned int> *seq;
   unsigned int value;

   inline AnonWriteLock(const void *inObj) : seq(0), value(0)
   {
      if (hx::gConcurrentGcMarkActive)
      {
         seq = &anonSeq(inObj);
         int spins = 0;
         while(true)
         {
            value = seq->load(std::memory_order_relaxed);
            if (!(value&1) && seq->compare_exchange_weak(value,value+1))
               break;
            anonSpinPause(spins);
         }
         // The odd sequence is visible before the writes that follow
         std::atomic_thread_fence(std::memory_order_seq_cst);
      }
   }
   inline ~AnonWriteLock()
   {
      if (seq)
         seq->store(value+2, std::memory_order_release);
   }
};

// Out of line: keeps the lock out of the common path of __SetField
HXCPP_NOINLINE_ANON void anonSetChangingType(const void *inObj, cpp::Variant *ioField, const cpp::Variant &inValue)
{
   AnonWriteLock lock(inObj);
   *ioField = inValue;
}

struct AnonFieldSnapshot
{
   void *ptr;
   int  type;
};
}
#endif

void Anon_obj::__Mark(hx::MarkContext *__inCtx)
{
   #ifdef HXCPP_GC_CONCURRENT
   if (hx::gConcurrentGcMarkActive)
   {
      enum { CHUNK = 16 };
      AnonFieldSnapshot snapshot[CHUNK];
      std::atomic<unsigned int> &seq = anonSeq(this);
      volatile VariantKey *fixed = getFixed();
      int first = 0;
      while(true)
      {
         int n = 0;
         int spins = 0;
         while(true)
         {
            unsigned int s0 = seq.load(std::memory_order_acquire);
            if (!(s0&1))
            {
               // The count only ever decreases (__Remove)
               n = *(volatile int *)&mFixedFields - first;
               if (n>CHUNK)
                  n = CHUNK;
               if (n<0)
                  n = 0;
               for(int i=0;i<n;i++)
               {
                  snapshot[i].type = (int)fixed[first+i].value.type;
                  snapshot[i].ptr = (void *)fixed[first+i].value.valObject;
               }
               std::atomic_thread_fence(std::memory_order_acquire);
               if (seq.load(std::memory_order_relaxed)==s0)
                  break;
            }
            anonSpinPause(spins);
         }
         for(int i=0;i<n;i++)
         {
            if (snapshot[i].type==cpp::Variant::typeObject)
            {
               hx::Object *obj = (hx::Object *)snapshot[i].ptr;
               HX_MARK_OBJECT(obj);
            }
            else if (snapshot[i].type==cpp::Variant::typeString)
            {
               HX_MARK_STRING(snapshot[i].ptr);
            }
         }
         if (n<CHUNK)
            break;
         first += n;
      }
      HX_MARK_MEMBER(mFields);
      return;
   }
   #endif

   if (mFixedFields)
   {
      VariantKey *fixed = getFixed();
      for(int i=0;i<mFixedFields;i++)
         HX_MARK_MEMBER(fixed[i].value);
   }
   HX_MARK_MEMBER(mFields);
}

#ifdef HXCPP_VISIT_ALLOCS
void Anon_obj::__Visit(hx::VisitContext *__inCtx)
{
   if (mFixedFields)
   {
      VariantKey *fixed = getFixed();
      for(int i=0;i<mFixedFields;i++)
         HX_VISIT_MEMBER(fixed[i].value);
   }
   HX_VISIT_MEMBER(mFields);
}
#endif

inline int Anon_obj::findFixed(const ::String &inKey, bool inSkip5)
{
   if (!mFixedFields || !inKey.isAsciiEncoded() )
      return -1;
   VariantKey *fixed = getFixed();

   if (!inSkip5)
      if (inKey.__s[HX_GC_CONST_ALLOC_MARK_OFFSET]  & HX_GC_CONST_ALLOC_MARK_BIT)
      {
         for(int i=0;i<mFixedFields;i++)
         {
            if (fixed[i].key.__s == inKey.__s)
            return i;
         }
      }


   int sought = inKey.hash();

   if (!inSkip5)
   {
      if (mFixedFields<5)
      {
         for(int i=0;i<mFixedFields;i++)
            if (fixed[i].hash==sought && (
                   (fixed[i].key.length == inKey.length && !memcmp(fixed[i].key.raw_ptr(),inKey.raw_ptr(), inKey.length))))
               return i;
         return -1;
      }
   }

   // Find node with same hash...
   /* hash example
      [0] = -3  <- min
      [1] = -1
      [2] = -1   (sought -1)
      [3] =  4
      [4] =  4  <- max
   */

   int min = inSkip5 ? 5 : 0;
   if (fixed[min].hash>sought)
      return -1;
   if (fixed[min].hash!=sought)
   {
      int max = mFixedFields;
      if (fixed[max-1].hash<sought)
         return -1;

      while(max>min+1)
      {
         int mid = (max+min)>>1;
         if (fixed[mid].hash <= sought)
            min = mid;
         else
            max = mid;
      }
   }

   while(fixed[min].hash==sought)
   {
      // Might be multiple?
      if ( fixed[min].key.length == inKey.length && !memcmp(fixed[min].key.raw_ptr(),inKey.raw_ptr(), inKey.length))
         return min;

      min++;
      if (min>=mFixedFields)
         break;
   }

   return -1;
}

hx::Val Anon_obj::__Field(const String &inName, hx::PropertyAccess inCallProp)
{

   #ifdef HX_SMART_STRINGS
   if (inName.isAsciiEncodedQ())
   #endif
   if (mFixedFields>0)
   {
      VariantKey *fixed = getFixed();
      if (inName.__s[HX_GC_CONST_ALLOC_MARK_OFFSET]  & HX_GC_CONST_ALLOC_MARK_BIT)
      {
         for(int i=0;i<mFixedFields;i++)
         {
            if (fixed[i].key.__s == inName.__s)
               return fixed[i].value;
         }
      }

      int hash = inName.hash();
      if (fixed->hash==hash && HX_QSTR_EQ_AE(fixed->key,inName))
         return fixed->value;
      if (mFixedFields>1)
      {
         fixed++;
         if (fixed->hash==hash && HX_QSTR_EQ_AE(fixed->key,inName))
           return fixed->value;
         if (mFixedFields>2)
         {
            fixed++;
            if (fixed->hash==hash && HX_QSTR_EQ_AE(fixed->key,inName))
              return fixed->value;
            if (mFixedFields>3)
            {
               fixed++;
               if (fixed->hash==hash && HX_QSTR_EQ_AE(fixed->key,inName))
                 return fixed->value;
               if (mFixedFields>4)
               {
                  fixed++;
                  if (fixed->hash==hash && HX_QSTR_EQ_AE(fixed->key,inName))
                     return fixed->value;

                  int fixed = findFixed(inName,true);
                  if (fixed>=0)
                     return getFixed()[fixed].value;
               }
            }
         }
      }
   }


   if (!mFields.mPtr)
      return hx::Val();

   return __string_hash_get(mFields,inName);
}

bool Anon_obj::__HasField(const String &inName)
{
   if (findFixed(inName)>=0)
      return true;
   if (!mFields.mPtr)
      return false;
   return __string_hash_exists(mFields,inName);
}

bool Anon_obj::__Remove(String inKey)
{
   int slot = findFixed(inKey);
   if (slot>=0)
   {
      VariantKey *fixed = getFixed();
      // The last field has no successor to copy from
      int last = mFixedFields-1;
      {
         #ifdef HXCPP_GC_CONCURRENT
         AnonWriteLock lock(this);
         #endif
         while(slot<last)
         {
            fixed[slot] = fixed[slot+1];
            slot++;
         }
         mFixedFields = last;
      }
      // A concurrent marker scans the fields in several steps, and may miss a
      //  value that moved down between two of them
      HX_OBJ_WB_CONCURRENT_BULK(this);
      return true;
   }

   if (!mFields.mPtr)
      return false;
   return __string_hash_remove(mFields,inKey);
}


hx::Val Anon_obj::__SetField(const String &inName,const hx::Val &inValue, hx::PropertyAccess inCallProp)
{
   int slot = findFixed(inName);
   if (slot>=0)
   {
      #ifdef HXCPP_GC_GENERATIONAL
      VariantKey *fixed = getFixed() + slot;
      #ifdef HXCPP_GC_CONCURRENT
      // Same type: the marker reads the old or the new pointer, both valid
      if (hx::gConcurrentGcMarkActive && fixed->value.type!=inValue.type)
         anonSetChangingType(this, &fixed->value, inValue);
      else
      #endif
      fixed->value=inValue;
      if (fixed->value.type <= cpp::Variant::typeString)
         HX_OBJ_WB_GET(this, fixed->value.valObject);
      #else
      getFixed()[slot].value=inValue;
      #endif
      return inValue;
   }

   // TODO - fixed
   if (!mFields.mPtr)
   {
      mFields = hx::FieldMapCreate();
      HX_OBJ_WB_GET(this, mFields.mPtr);
   }

   __string_hash_set(HX_MAP_THIS_ mFields,inName,inValue,true);
   return inValue;
}

Anon_obj *Anon_obj::Add(const String &inName,const Dynamic &inValue,bool inSetThisPointer)
{
   // TODO - fixed
   if (!mFields.mPtr)
   {
      mFields = hx::FieldMapCreate();
      HX_OBJ_WB_GET(this, mFields.mPtr);
   }

   __string_hash_set(HX_MAP_THIS_ mFields,inName,inValue,true);
   if (inSetThisPointer && inValue.GetPtr())
      inValue.GetPtr()->__SetThis(this);
   return this;
}

static int _hx_toString_depth = 0;
String Anon_obj::toString()
{
   if (!mFields.mPtr && !mFixedFields)
      return HX_CSTRING("{ }");

   if (_hx_toString_depth >= 5)
      return HX_CSTRING("...");

   _hx_toString_depth++;

   try
   {
      int fixedToString = findFixed(HX_CSTRING("toString"));
      if (fixedToString>=0)
      {
         Dynamic func = getFixed()[fixedToString].value;
         if (func!=null())
         {
            String res = func();
            _hx_toString_depth--;
            return res;
         }
      }

      Dynamic func;
      if (FieldMapGet(&mFields, HX_CSTRING("toString"), func))
      {
         String res = func();
         _hx_toString_depth--;
         return res;
      }

      if (mFixedFields)
      {
         Array<String> array = Array<String>(0,mFixedFields*4+4);
         array->push(HX_CSTRING("{ "));

         if (mFields.mPtr)
         {
            String val = __string_hash_to_string_raw(mFields);
            if (val.raw_ptr())
               array->push(val);
         }

         VariantKey *fixed = getFixed();
         for(int i=0;i<mFixedFields;i++)
         {
            if (array->length>1)
              array->push(HX_CSTRING(", "));

            array->push(fixed[i].key);
            array->push(HX_CSTRING(" => "));
            array->push(fixed[i].value);
         }
         array->push(HX_CSTRING(" }"));
         _hx_toString_depth--;
         return array->join(HX_CSTRING(""));
      }

      String ret = __string_hash_to_string(mFields);
      _hx_toString_depth--;
      return ret;
   } catch (...)
   {
      _hx_toString_depth--;
      throw;
   }
}

void Anon_obj::__GetFields(Array<String> &outFields)
{
   if (mFields.mPtr)
      outFields = __string_hash_keys(mFields);
   if (mFixedFields>0)
   {
      VariantKey *fixed = getFixed();
      for(int i=0;i<mFixedFields;i++)
         outFields->push( fixed[i].key );
   }
}


String Anon_obj::__ToString() const { return HX_CSTRING("Anon"); }

Dynamic Anon_obj::__Create(DynamicArray inArgs) { return Anon(new (0) Anon_obj); }

hx::Class Anon_obj::__mClass;


void Anon_obj::__boot()
{
   Static(__mClass) = hx::_hx_RegisterClass(HX_CSTRING("__Anon"),TCanCast<Anon_obj>,sNone,sNone,0,0,0,0);
}



Anon SourceInfo(String inFile, int inLine, String inClass, String inMethod)
{
   Anon result = Anon_obj::Create();
   result->Add(HX_CSTRING("fileName"),inFile);
   result->Add(HX_CSTRING("lineNumber"),inLine);
   result->Add(HX_CSTRING("className"),inClass);
   result->Add(HX_CSTRING("methodName"),inMethod);
   return result;
}

String StringFromAnonFields(hx::Object *inPtr)
{
   Array<String> fields = Array_obj<String>::__new();
   inPtr->__GetFields(fields);

   int n = fields->length;
   Array<String> array = Array<String>(0,n*4+4);
   array->push(HX_CSTRING("{ "));
   for(int i=0;i<n;i++)
   {
      if (array->length>1)
         array->push(HX_CSTRING(", "));

      array->push(fields[i]);
      array->push(HX_CSTRING(" => "));
      array->push( inPtr->__Field( fields[i], HX_PROP_DYNAMIC) );
   }
   array->push(HX_CSTRING(" }"));
   return array->join(HX_CSTRING(""));
}




}

bool __hxcpp_anon_remove(Dynamic inObj,String inKey)
{
   hx::Anon_obj *anon = dynamic_cast<hx::Anon_obj *>(inObj.mPtr);
   if (anon)
   {
      bool removed = anon->__Remove(inKey);
      if (removed)
         return true;
   }
   Dynamic *map = inObj->__GetFieldMap();
   if (map)
      return __string_hash_remove(*map,inKey);
   return false;
}


