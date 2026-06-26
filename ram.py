#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ram.py — Production RAM test.

Allocates a large region, fills it with fixed data patterns, then reads it back
and verifies. OOM-safe: mlock pins physical pages before writing so the write
phase can never trip the OOM killer; if mlock can't pin the requested size it
backs off until it can (or falls back to unlocked with a warning).

Patterns (each is a uniform byte, expanded across the whole region):
  Solid Ones    0xFF  catches stuck-at-0 / data lines shorted to ground
  Solid Zeroes  0x00  catches stuck-at-1 / data lines shorted to power
  Checkerboard  0xAA  catches adjacent-bit shorts and pattern sensitivity
  Inverse       0x55  complementary check of the above

Exit code: 0 = pass, 1 = fail.
"""

import ctypes
import ctypes.util
import datetime
import errno as errno_mod
import mmap
import os
import sys

_MB = 1024 ** 2

# (name, uniform byte value); 32-bit word label = byte * 0x01010101
PATTERNS = [
    ("Solid Ones",   0xFF),
    ("Solid Zeroes", 0x00),
    ("Checkerboard", 0xAA),
    ("Inverse",      0x55),
]

BLOCK_SIZE = _MB                 # read/write granularity
RESERVE_FLOOR = 64 * _MB         # leave at least this for the OS / process
PROBE_STEP = 16 * _MB            # back off this much when mlock fails
MIN_TEST_SIZE = 16 * _MB         # don't bother testing below this
MEMINFO_FALLBACK = 4 * 1024 ** 3  # if /proc/meminfo is unreadable

_SIZE_UNITS = {'B': 0, 'K': 10, 'M': 20, 'G': 30}


def log(level, msg):
    ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{ts}] [{os.getpid()}] [{level}] {msg}")


def get_available_memory():
    """Free memory in bytes (falls back to MEMINFO_FALLBACK on error)."""
    avail = MEMINFO_FALLBACK
    try:
        with open('/proc/meminfo') as f:
            for line in f:
                if line.startswith('MemAvailable:'):
                    avail = int(line.split()[1]) * 1024  # kB -> bytes
                    break
    except Exception as e:
        log("ERROR", f"Failed to get available memory: {e}")
    return avail


def compute_initial_target():
    """Start close to the available-memory ceiling; mlock probes the real limit."""
    return max(get_available_memory() - RESERVE_FLOOR, MIN_TEST_SIZE)


def parse_size(arg):
    """Parse <size>[B|K|M|G]; a bare number is megabytes."""
    arg = arg.strip()
    suffix = arg[-1].upper()
    try:
        if suffix in _SIZE_UNITS:
            return int(arg[:-1]) << _SIZE_UNITS[suffix]
        return int(arg) << 20
    except ValueError:
        raise ValueError(f"Invalid size: {arg!r}")


# --- mlock / munlock via libc -----------------------------------------------
_libc = None


def _get_libc():
    global _libc
    if _libc is None:
        name = ctypes.util.find_library("c") or "libc.so.6"
        lib = ctypes.CDLL(name, use_errno=True)
        lib.mlock.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        lib.mlock.restype = ctypes.c_int
        lib.munlock.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        lib.munlock.restype = ctypes.c_int
        _libc = lib
    return _libc


def _buffer_address(mem):
    return ctypes.addressof(ctypes.c_char.from_buffer(mem))


def try_mlock(mem, size):
    """Return (locked, errno, msg). EPERM = no privilege; ENOMEM = out of memory."""
    try:
        if _get_libc().mlock(_buffer_address(mem), size) == 0:
            return True, None, None
        err = ctypes.get_errno()
        return False, err, os.strerror(err)
    except Exception as e:
        return False, None, str(e)


def do_munlock(mem, size):
    try:
        _get_libc().munlock(_buffer_address(mem), size)
    except Exception:
        pass


def probe_allocate(target, step=PROBE_STEP, min_size=MIN_TEST_SIZE):
    """
    mmap + mlock `target` bytes.
      step > 0: on ENOMEM, back off by `step` until locked or below `min_size`.
      step = 0: no backoff (explicit size); on failure keep the unlocked mapping.
    Returns (mem, size, locked), or (None, 0, False) if nothing could be allocated.
    locked=True guarantees the write phase won't OOM.
    """
    size = target
    while True:
        if size <= 0:
            return None, 0, False
        if step != 0 and size < min_size:   # only the adaptive path floors at min
            return None, 0, False
        try:
            mem = mmap.mmap(-1, size)
        except (MemoryError, OverflowError, ValueError, OSError):
            if step == 0:
                return None, 0, False
            size -= step
            continue

        locked, err, msg = try_mlock(mem, size)
        if locked:
            return mem, size, True

        if err == errno_mod.EPERM:
            log("WARN", f"mlock not permitted ({msg}); continuing unlocked")
            return mem, size, False

        if step == 0:
            log("WARN", f"mlock failed ({msg}); continuing unlocked — "
                        "write-time OOM risk, consider a smaller size")
            return mem, size, False
        mem.close()
        log("INFO", f"mlock {size // _MB}MB failed ({msg}); "
                    f"backing off {step // _MB}MB")
        size -= step


def test_fill(mem, size, byte_val, block_size=BLOCK_SIZE):
    """Fill the region with byte_val, read it back, compare. Returns (offset,
    got_byte) on the first mismatch, or None on success."""
    tile = bytes([byte_val]) * block_size

    for offset in range(0, size, block_size):
        end = offset + block_size
        if end <= size:
            mem[offset:end] = tile
        else:
            mem[offset:size] = tile[:size - offset]

    for offset in range(0, size, block_size):
        end = offset + block_size
        read_back = mem[offset:end]
        expected = tile if end <= size else tile[:size - offset]  # slice only the tail
        if read_back != expected:
            for i, (got, want) in enumerate(zip(read_back, expected)):
                if got != want:
                    return offset + i, got
            return offset, read_back[0] if read_back else None
    return None


def allocate_and_test_memory(target, block_size=BLOCK_SIZE, allow_backoff=True):
    """Allocate then run every pattern. allow_backoff=False uses the exact size
    (no mlock backoff)."""
    step = PROBE_STEP if allow_backoff else 0
    if allow_backoff:
        log("INFO", f"Probing up to {target / _MB:.2f} MB "
                    f"(mlock backs off to physical limit)")
    else:
        log("INFO", f"Trying to allocate {target / _MB:.2f} MB (explicit)")

    mem, size, locked = probe_allocate(target, step)
    if mem is None:
        log("ERROR", "Could not allocate the requested test memory")
        return False
    log("INFO", f"Memory ready: {size / _MB:.2f} MB, "
                f"{'locked' if locked else 'unlocked'}")

    try:
        all_pass = True
        for name, byte_val in PATTERNS:
            word = byte_val * 0x01010101
            log("INFO", f"Testing pattern {name} (0x{word:08X})...")
            result = test_fill(mem, size, byte_val, block_size)
            if result is None:
                log("INFO", f"{name}: ok")
            else:
                offset, got = result
                log("ERROR",
                    f"FAILURE: 0x{got:02x} != 0x{byte_val:02x} "
                    f"at offset 0x{offset:08x} ({name})")
                all_pass = False
                # keep going so every failing pattern is reported; break to stop early

        if all_pass:
            log("INFO", "All pattern tests passed")
        return all_pass
    finally:
        if locked:
            do_munlock(mem, size)
        mem.close()


def main():
    if len(sys.argv) > 1:
        try:
            size = parse_size(sys.argv[1])
        except ValueError as e:
            log("ERROR", str(e))
            sys.exit(1)
        success = allocate_and_test_memory(size, allow_backoff=False)
    else:
        success = allocate_and_test_memory(compute_initial_target(),
                                           allow_backoff=True)

    if success:
        log("PASS", "Memory test succeeded")
    else:
        log("FAIL", "Memory test failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
