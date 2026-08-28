// isOSVersionAtLeast.S — arm64 Darwin
//
// The compiler emits __isOSVersionAtLeast / __isPlatformVersionAtLeast for
// @available() checks when the deployment target is below the checked version.
// The theos cross-toolchain does not ship compiler-rt for iOS targets, so we
// provide our own.  Implementation uses sysctlbyname("kern.osproductversion")
// and caches the parsed result on first call.

// ---------------------------------------------------------------------------
// Read-only data
// ---------------------------------------------------------------------------
.section __TEXT,__cstring,cstring_literals
L_osver_key:
	.asciz "kern.osproductversion"

// ---------------------------------------------------------------------------
// Mutable data: three consecutive int32 words (major / minor / subminor).
// major == 0 is the "not yet fetched" sentinel; real Darwin major is always >= 1.
// ---------------------------------------------------------------------------
.section __DATA,__data
.p2align 2
L_osver_cache:
	.long 0
	.long 0
	.long 0

// ---------------------------------------------------------------------------
// ___isOSVersionAtLeast(int32 Major, int32 Minor, int32 Subminor) -> int32
//   Returns 1 if running OS version >= (Major, Minor, Subminor), else 0.
//
// Stack frame layout (112 bytes, 16-byte aligned):
//   [sp +  0.. 7]  x29  (frame pointer)
//   [sp +  8..15]  x30  (link register / return address)
//   [sp + 16..23]  x19  (want_major)
//   [sp + 24..31]  x20  (want_minor)
//   [sp + 32..39]  x21  (want_subminor)
//   [sp + 40..47]  x22  (cache ptr)
//   [sp + 48..55]  x23  (parse ptr / buf base)
//   [sp + 56..63]  x24  (parse accumulator)
//   [sp + 64..95]  32-byte version string buffer
//   [sp + 96..103] size_t buflen for sysctlbyname
//   [sp +104..111] padding to 112
// ---------------------------------------------------------------------------
.section __TEXT,__text,regular,pure_instructions
.globl ___isOSVersionAtLeast
.p2align 2
___isOSVersionAtLeast:
	stp  x29, x30, [sp, #-112]!
	mov  x29, sp
	stp  x19, x20, [sp, #16]
	stp  x21, x22, [sp, #32]
	stp  x23, x24, [sp, #48]

	mov  w19, w0                    // want_major
	mov  w20, w1                    // want_minor
	mov  w21, w2                    // want_subminor

	adrp x22, L_osver_cache@PAGE
	add  x22, x22, L_osver_cache@PAGEOFF

	ldr  w0, [x22]
	cbnz w0, L_compare              // already cached (major != 0)

	// ---- First call: fetch via sysctlbyname ----
	add  x23, sp, #64               // buf = sp+64 (32 bytes, valid until epilogue)
	add  x0,  sp, #96               // &buflen
	mov  x1,  #32
	str  x1,  [x0]                  // buflen = 32

	adrp x0, L_osver_key@PAGE
	add  x0, x0, L_osver_key@PAGEOFF
	mov  x1, x23                    // oldp  = buf
	add  x2, sp, #96                // oldlenp = &buflen
	mov  x3, #0                     // newp  = NULL
	mov  x4, #0                     // newlen = 0
	bl   _sysctlbyname

	cbnz w0, L_permissive           // failed → be permissive

	// ---- Parse "MAJOR[.MINOR[.SUBMINOR]]" ----

	// major
	mov  w24, #0
L_maj_loop:
	ldrb w9,  [x23]
	sub  w9,  w9,  #'0'
	cmp  w9,  #9
	b.hi L_maj_done
	mov  w10, #10
	mul  w24, w24, w10
	add  w24, w24, w9
	add  x23, x23, #1
	b    L_maj_loop
L_maj_done:
	// clamp to 1 so major == 0 never re-triggers init (impossible in practice)
	cmp  w24, #0
	csinc w24, w24, wzr, ne
	str  w24, [x22]                 // cache major

	ldrb w9, [x23]
	cbz  w9, L_zero_min_sub         // no minor → zero both and compare

	// minor
	add  x23, x23, #1               // skip '.'
	mov  w24, #0
L_min_loop:
	ldrb w9,  [x23]
	sub  w9,  w9,  #'0'
	cmp  w9,  #9
	b.hi L_min_done
	mov  w10, #10
	mul  w24, w24, w10
	add  w24, w24, w9
	add  x23, x23, #1
	b    L_min_loop
L_min_done:
	str  w24, [x22, #4]             // cache minor

	ldrb w9, [x23]
	cbz  w9, L_zero_sub             // no subminor → zero it and compare

	// subminor
	add  x23, x23, #1               // skip '.'
	mov  w24, #0
L_sub_loop:
	ldrb w9,  [x23]
	sub  w9,  w9,  #'0'
	cmp  w9,  #9
	b.hi L_sub_done
	mov  w10, #10
	mul  w24, w24, w10
	add  w24, w24, w9
	add  x23, x23, #1
	b    L_sub_loop
L_sub_done:
	str  w24, [x22, #8]             // cache subminor
	b    L_compare

L_zero_min_sub:
	str  wzr, [x22, #4]
L_zero_sub:
	str  wzr, [x22, #8]

	// ---- Compare cached version against wanted ----
L_compare:
	ldr  w0, [x22]                  // got_major
	cmp  w0, w19
	b.gt L_yes
	b.lt L_no
	ldr  w0, [x22, #4]              // got_minor
	cmp  w0, w20
	b.gt L_yes
	b.lt L_no
	ldr  w0, [x22, #8]              // got_subminor
	cmp  w0, w21
	b.ge L_yes
	b    L_no

L_permissive:
L_yes:
	mov  w0, #1
	b    L_ret
L_no:
	mov  w0, #0
L_ret:
	ldp  x23, x24, [sp, #48]
	ldp  x21, x22, [sp, #32]
	ldp  x19, x20, [sp, #16]
	ldp  x29, x30, [sp], #112
	ret

// ---------------------------------------------------------------------------
// ___isPlatformVersionAtLeast(uint32 Platform, uint32 Major, uint32 Minor,
//                             uint32 Subminor) -> int32
// Emitted by newer clang for @available().  Platform arg (w0) is ignored;
// we only build for iOS so we forward to the OS-version check.
// ---------------------------------------------------------------------------
.globl ___isPlatformVersionAtLeast
.p2align 2
___isPlatformVersionAtLeast:
	mov  w0, w1
	mov  w1, w2
	mov  w2, w3
	b    ___isOSVersionAtLeast
