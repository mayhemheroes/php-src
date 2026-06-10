#!/usr/bin/env bash
#
# mayhem/build.sh — build php-src's libFuzzer targets + a clean CLI oracle, ON TOP of the org
# C/C++ base image (ghcr.io/mayhemheroes/base). The base exports the build contract:
#   CC, CXX, LIB_FUZZING_ENGINE (-fsanitize=fuzzer), SANITIZER_FLAGS (ASan+UBSan, both halting),
#   SRC (/mayhem). We default them so the script also runs outside the image.
#
# This is a re-base of PHP's OSS-Fuzz integration (sapi/fuzzer/*) onto the org base. PHP's
# `--enable-fuzzer` SAPI builds one libFuzzer binary per sapi/fuzzer/fuzzer-<name>.c. We ship the
# six the upstream OSS-Fuzz build.sh shipped:
#   /mayhem/out/php-fuzz-{json,exif,unserialize,unserializehash,parser,execute}
# and a separate clean (no-sanitizer) `sapi/cli/php` used by test.sh for a known-answer oracle.
#
# VM kind under ASan: on x86_64 with a musttail-capable clang, PHP's zend_vm_opcodes.h selects the
# TAILCALL VM, whose `musttail` handlers crash clang 19's backend ("Finalize ISel" on
# *_TAILCALL_HANDLER — an LLVM musttail+ASan ISel bug). We gate that selection on our own
# -DMAYHEM_NO_MUSTTAIL (see phase [2/3]) so the instrumented build falls through to the CALL VM —
# one ordinary fastcall function per opcode, no musttail, which the opcache JIT also supports.
# (Upstream guards the *HYBRID* branch with !__SANITIZE_ADDRESS__, but clang doesn't define that
# macro under -fsanitize=address, so we use an explicit -D we control instead.)
set -euo pipefail

: "${SRC:=/mayhem}"
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${SANITIZER_FLAGS:=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"

export CC CXX
cd "$SRC"

FUZZERS="php-fuzz-json php-fuzz-exif php-fuzz-unserialize php-fuzz-unserializehash php-fuzz-parser php-fuzz-execute"
mkdir -p "$SRC/out"

# ---------------------------------------------------------------------------------------------
# [1/3] Clean CLI oracle — a NON-sanitized PHP CLI used by test.sh for the known-answer tests.
# Built with normal flags so the oracle is stable regardless of how the fuzz build's sanitizers
# behave. --disable-all still bundles core + ext/standard (serialize, var_export, string/array
# funcs) + the JSON extension, which is what the KAT exercises.
# ---------------------------------------------------------------------------------------------
echo "== [1/3] clean CLI oracle build (no sanitizers) =="
./buildconf --force
(
  unset CFLAGS CXXFLAGS LIB_FUZZING_ENGINE || true
  ./configure \
      --disable-all \
      --enable-option-checking=fatal \
      --without-pcre-jit \
      --disable-phpdbg \
      --disable-cgi
  make -j"$(nproc)"
)
cp sapi/cli/php "$SRC/out/php-oracle"

# ---------------------------------------------------------------------------------------------
# [2/3] Instrumented fuzzer build.
# PHP's fuzzer config.m4: when LIB_FUZZING_ENGINE is UNSET it links with `-fsanitize=fuzzer` and
# plain libstdc++ (adds `-fsanitize=fuzzer-no-link` to CFLAGS itself); when SET it forces
# `$CXX -stdlib=libc++`, which the base doesn't carry. So we deliberately unset it here.
# PHP is not UBSan-clean: its zend_function union trips -fsanitize=object-size, and it calls a few
# callbacks (e.g. php_ini_parser_cb) through deliberately-mismatched function-pointer types which
# trip -fsanitize=function at startup. We exclude those two non-bug checks while keeping ASan + the
# rest of UBSan halting. PROFITABILITY_CHECKS=0 disables JIT profitability checks (from the
# OSS-Fuzz build).
# ---------------------------------------------------------------------------------------------
echo "== [2/3] instrumented fuzzer build (ASan+UBSan, CALL VM) =="
make distclean >/dev/null 2>&1 || true
(
  unset LIB_FUZZING_ENGINE || true
  export CFLAGS="$SANITIZER_FLAGS -fno-sanitize=object-size -fno-sanitize=function -DPROFITABILITY_CHECKS=0 -DMAYHEM_NO_MUSTTAIL=1"
  export CXXFLAGS="$CFLAGS"
  ./buildconf --force
  ./configure \
      --disable-all \
      --enable-debug-assertions \
      --enable-option-checking=fatal \
      --enable-fuzzer \
      --enable-exif \
      --without-pcre-jit \
      --disable-phpdbg \
      --disable-cgi \
      --enable-pic

  # Gate the TAILCALL VM selection on !MAYHEM_NO_MUSTTAIL (defined in CFLAGS above) so the ASan
  # build uses the CALL VM (no musttail) instead of crashing clang's backend. The committed
  # zend_vm_execute.h is multi-kind (the kind is chosen here, at C-compile, by ZEND_VM_KIND), so no
  # regeneration is needed. touch the generated VM sources so `make` keeps this edit rather than
  # regenerating them from zend_vm_def.h.
  sed -i 's/#elif defined(HAVE_MUSTTAIL) && defined(HAVE_PRESERVE_NONE)/#elif !defined(MAYHEM_NO_MUSTTAIL) \&\& defined(HAVE_MUSTTAIL) \&\& defined(HAVE_PRESERVE_NONE)/' Zend/zend_vm_opcodes.h
  grep -nE "MAYHEM_NO_MUSTTAIL.*HAVE_MUSTTAIL" Zend/zend_vm_opcodes.h || { echo "FATAL: VM-kind guard sed did not apply" >&2; exit 1; }
  touch Zend/zend_vm_opcodes.h Zend/zend_vm_opcodes.c Zend/zend_vm_execute.h Zend/zend_vm_handlers.h

  make -j"$(nproc)"
)

for f in $FUZZERS; do
  cp "sapi/fuzzer/$f" "$SRC/out/$f"
done

# Generate the fuzzer dictionaries/corpora the upstream build produces (best-effort; the harnesses
# don't need them to run, and Mayhem seeds from the in-tree sapi/fuzzer/corpus/* anyway).
sapi/cli/php sapi/fuzzer/generate_all.php || true

echo "== [3/3] build.sh done =="
ls -la "$SRC/out/"
