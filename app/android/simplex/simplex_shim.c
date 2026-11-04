// Loaded in place of libsimplex.so (ecp_simplex/lib/ffi.dart); libsimplex.so is its dependency,
// so the core's symbols resolve against this library first.
//
// The 32-bit ARM core (armeabi-v7a) expects some symbols the C library has but Android does
// not export: bionic internals, and on Android 9 and older also reallocarray. Without them
// the core does not load at all. SimpleX's own app defines them the same way
// (apps/multiplatform/common/src/commonMain/cpp/android/simplex-api.c); the internal ones
// are never called on a working path, they only need to resolve. reallocarray is a real
// implementation here, not an empty stub, since the core does call it.
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>

void __svfscanf(void) {}
void __vfwscanf(void) {}
void __memset_chk_fail(void) {}
void __strcpy_chk_generic(void) {}
void __strcat_chk_generic(void) {}
void __libc_globals(void) {}
void __rel_iplt_start(void) {}

void *reallocarray(void *p, size_t n, size_t size) {
  if (size != 0 && n > SIZE_MAX / size) {
    errno = ENOMEM;
    return NULL;
  }
  return realloc(p, n * size);
}
