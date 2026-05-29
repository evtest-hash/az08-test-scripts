import mmap
import resource
import os
import sys
import datetime

def log(level, msg):
    ts = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    pid = os.getpid()
    print(f"[{ts}] [{pid}] [{level}] {msg}")

def get_available_memory():
    """获取系统可用内存（字节）"""
    try:
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if line.startswith('MemAvailable:'):
                    parts = line.split()
                    # MemAvailable:   12345678 kB
                    return int(parts[1]) * 1024  # kB -> bytes
    except Exception as e:
        log("ERROR", f"Failed to get available memory: {e}")
    return 4 * 1024**3  # fallback: 4GB

def get_max_allocatable_memory_80pct():
    # 获取可用内存
    avail_mem = get_available_memory()
    # 获取进程虚拟内存限制
    soft, _ = resource.getrlimit(resource.RLIMIT_AS)
    max_mem = soft if soft != resource.RLIM_INFINITY else avail_mem
    # 取可用内存和进程虚拟内存限制的较小值
    usable_mem = min(avail_mem, max_mem)
    # 申请可用内存的80%
    alloc_mem = int(usable_mem * 0.80)
    return alloc_mem

def allocate_and_test_memory(size, block_size=1024*1024):  # 默认按 1MB 块处理
    log("INFO", f"Trying to allocate {size / 1024**2:.2f} MB")
    try:
        mem = mmap.mmap(-1, size)
        log("INFO", f"Memory allocation successful, block size = {block_size // 1024} KB")

        pattern = bytearray((i % 256 for i in range(block_size)))

        log("INFO", "Writing test pattern...")
        for offset in range(0, size, block_size):
            mem[offset:offset + block_size] = pattern[:min(block_size, size - offset)]

        log("INFO", "Verifying test pattern...")
        for offset in range(0, size, block_size):
            read_back = mem[offset:offset + block_size]
            expected = pattern[:len(read_back)]
            if read_back != expected:
                log("ERROR", f"Mismatch at offset {offset}")
                return False

        log("INFO", "Memory read/write block verification passed")
        mem.close()
        return True
    except MemoryError:
        log("ERROR", "Memory allocation failed: not enough memory")
    except Exception as e:
        log("ERROR", f"Unexpected error: {e}")
    return False

def main():
    size = get_max_allocatable_memory_80pct()
    success = allocate_and_test_memory(size)
    if not success:
        log("FAIL", "Memory test failed")
        sys.exit(1)
    else:
        log("PASS", "Memory test succeeded")

if __name__ == "__main__":
    main()
