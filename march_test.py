#!/usr/bin/env python3
"""
MRAM March C Test + Comprehensive Memory Testing
Tests all or selected address ranges
"""

import serial
import time
import sys
from typing import List, Tuple

class MRAMUART:
    def __init__(self, port: str, baudrate: int = 115200):
        self.ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=1.0
        )
        time.sleep(0.1)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        self.errors = []
        
    def write_mram(self, addr: int, data: int, delay: float = 0.002) -> bool:
        """Write 16-bit data to address"""
        addr_h = (addr >> 16) & 0x03
        addr_m = (addr >> 8) & 0xFF
        addr_l = addr & 0xFF
        data_h = (data >> 8) & 0xFF
        data_l = data & 0xFF
        
        cmd = bytes([0x57, addr_h, addr_m, addr_l, data_h, data_l])
        self.ser.write(cmd)
        time.sleep(delay)
        self.ser.reset_input_buffer()
        return True
    
    def read_mram(self, addr: int, delay: float = 0.02) -> int:  # ← Augmenter delay!
        """Read 16-bit data from address"""
        addr_h = (addr >> 16) & 0x03
        addr_m = (addr >> 8) & 0xFF
        addr_l = addr & 0xFF
        
        cmd = bytes([0x52, addr_h, addr_m, addr_l])
        self.ser.reset_input_buffer()
        self.ser.write(cmd)
        time.sleep(delay)
        
        if self.ser.in_waiting >= 2:
            response = self.ser.read(2)
            data = (response[0] << 8) | response[1]
            return data
        return 0xDEAD  # ← Valeur d'erreur au lieu de None
    
    def close(self):
        self.ser.close()


def progress_bar(current: int, total: int, width: int = 50):
    """Display progress bar"""
    percent = current / total
    filled = int(width * percent)
    bar = '█' * filled + '░' * (width - filled)
    print(f'\r[{bar}] {percent*100:.1f}% ({current}/{total})', end='', flush=True)


def march_c_test(uart: MRAMUART, start_addr: int, end_addr: int) -> Tuple[bool, List]:
    """
    March C Algorithm:
    ⇕(w0); ⇑(r0,w1); ⇑(r1,w0); ⇓(r0,w1); ⇓(r1,w0); ⇕(r0)
    
    Detects:
    - Stuck-at faults
    - Transition faults
    - Coupling faults
    - Address decoder faults
    """
    print("\n" + "="*70)
    print("MARCH C TEST")
    print("="*70)
    print(f"Range: 0x{start_addr:05X} to 0x{end_addr:05X}")
    print(f"Total: {end_addr - start_addr + 1} addresses")
    print("="*70)
    
    errors = []
    total = end_addr - start_addr + 1
    
    # Phase 1: ⇕(w0) - Write 0 everywhere
    print("\n[Phase 1/6] ⇕(w0): Write 0x0000 to all addresses")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        uart.write_mram(addr, 0x0000)
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Phase 2: ⇑(r0,w1) - Read 0, Write 1 (ascending)
    print("\n[Phase 2/6] ⇑(r0,w1): Read 0x0000, Write 0xFFFF (ascending)")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        data = uart.read_mram(addr)
        if data != 0x0000:
            errors.append((addr, "Phase2", 0x0000, data))
        uart.write_mram(addr, 0xFFFF)
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Phase 3: ⇑(r1,w0) - Read 1, Write 0 (ascending)
    print("\n[Phase 3/6] ⇑(r1,w0): Read 0xFFFF, Write 0x0000 (ascending)")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        data = uart.read_mram(addr)
        if data != 0xFFFF:
            errors.append((addr, "Phase3", 0xFFFF, data))
        uart.write_mram(addr, 0x0000)
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Phase 4: ⇓(r0,w1) - Read 0, Write 1 (descending)
    print("\n[Phase 4/6] ⇓(r0,w1): Read 0x0000, Write 0xFFFF (descending)")
    for i, addr in enumerate(range(end_addr, start_addr - 1, -1)):
        data = uart.read_mram(addr)
        if data != 0x0000:
            errors.append((addr, "Phase4", 0x0000, data))
        uart.write_mram(addr, 0xFFFF)
        if i % 100 == 0:
            progress_bar(total - i, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Phase 5: ⇓(r1,w0) - Read 1, Write 0 (descending)
    print("\n[Phase 5/6] ⇓(r1,w0): Read 0xFFFF, Write 0x0000 (descending)")
    for i, addr in enumerate(range(end_addr, start_addr - 1, -1)):
        data = uart.read_mram(addr)
        if data != 0xFFFF:
            errors.append((addr, "Phase5", 0xFFFF, data))
        uart.write_mram(addr, 0x0000)
        if i % 100 == 0:
            progress_bar(total - i, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Phase 6: ⇕(r0) - Read 0 everywhere
    print("\n[Phase 6/6] ⇕(r0): Read 0x0000 from all addresses")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        data = uart.read_mram(addr)
        if data != 0x0000:
            errors.append((addr, "Phase6", 0x0000, data))
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    return len(errors) == 0, errors


def walking_ones_test(uart: MRAMUART, start_addr: int, count: int) -> Tuple[bool, List]:
    """Walking 1s test - detect bit stuck-at-0"""
    print("\n" + "="*70)
    print("WALKING 1s TEST")
    print("="*70)
    
    errors = []
    patterns = [1 << i for i in range(16)]  # 0x0001, 0x0002, 0x0004, ..., 0x8000
    
    for i, pattern in enumerate(patterns):
        addr = start_addr + i
        uart.write_mram(addr, pattern)
        print(f"  W 0x{addr:05X} ← 0x{pattern:04X}")
    
    print("\nReading back...")
    for i, pattern in enumerate(patterns):
        addr = start_addr + i
        data = uart.read_mram(addr)
        match = "✓" if data == pattern else "✗"
        print(f"  R 0x{addr:05X} → 0x{data:04X} (expected 0x{pattern:04X}) {match}")
        if data != pattern:
            errors.append((addr, "Walking1s", pattern, data))
    
    return len(errors) == 0, errors


def walking_zeros_test(uart: MRAMUART, start_addr: int, count: int) -> Tuple[bool, List]:
    """Walking 0s test - detect bit stuck-at-1"""
    print("\n" + "="*70)
    print("WALKING 0s TEST")
    print("="*70)
    
    errors = []
    patterns = [~(1 << i) & 0xFFFF for i in range(16)]  # 0xFFFE, 0xFFFD, ...
    
    for i, pattern in enumerate(patterns):
        addr = start_addr + i
        uart.write_mram(addr, pattern)
        print(f"  W 0x{addr:05X} ← 0x{pattern:04X}")
    
    print("\nReading back...")
    for i, pattern in enumerate(patterns):
        addr = start_addr + i
        data = uart.read_mram(addr)
        match = "✓" if data == pattern else "✗"
        print(f"  R 0x{addr:05X} → 0x{data:04X} (expected 0x{pattern:04X}) {match}")
        if data != pattern:
            errors.append((addr, "Walking0s", pattern, data))
    
    return len(errors) == 0, errors


def checkerboard_test(uart: MRAMUART, start_addr: int, end_addr: int) -> Tuple[bool, List]:
    """Checkerboard pattern test (0xAAAA / 0x5555)"""
    print("\n" + "="*70)
    print("CHECKERBOARD TEST")
    print("="*70)
    
    errors = []
    total = end_addr - start_addr + 1
    
    # Write checkerboard
    print("\nWriting checkerboard pattern...")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        pattern = 0xAAAA if i % 2 == 0 else 0x5555
        uart.write_mram(addr, pattern)
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Read and verify
    print("\nVerifying...")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        expected = 0xAAAA if i % 2 == 0 else 0x5555
        data = uart.read_mram(addr)
        if data != expected:
            errors.append((addr, "Checkerboard", expected, data))
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Inverse checkerboard
    print("\nWriting inverse checkerboard...")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        pattern = 0x5555 if i % 2 == 0 else 0xAAAA
        uart.write_mram(addr, pattern)
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    print("\nVerifying inverse...")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        expected = 0x5555 if i % 2 == 0 else 0xAAAA
        data = uart.read_mram(addr)
        if data != expected:
            errors.append((addr, "InvCheckerboard", expected, data))
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    return len(errors) == 0, errors


def address_uniqueness_test(uart: MRAMUART, start_addr: int, end_addr: int) -> Tuple[bool, List]:
    """Write address as data - detect address decoder faults"""
    print("\n" + "="*70)
    print("ADDRESS UNIQUENESS TEST")
    print("="*70)
    
    errors = []
    total = end_addr - start_addr + 1
    
    # Write address as data
    print("\nWriting address as data...")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        data = addr & 0xFFFF  # Lower 16 bits of address
        uart.write_mram(addr, data)
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    # Read and verify
    print("\nVerifying...")
    for i, addr in enumerate(range(start_addr, end_addr + 1)):
        expected = addr & 0xFFFF
        data = uart.read_mram(addr)
        if data != expected:
            errors.append((addr, "AddressUnique", expected, data))
        if i % 100 == 0:
            progress_bar(i + 1, total)
    progress_bar(total, total)
    print(" ✓")
    
    return len(errors) == 0, errors


def print_summary(all_errors: List):
    """Print test summary"""
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)
    
    if not all_errors:
        print("✓ ALL TESTS PASSED - NO ERRORS DETECTED!")
    else:
        print(f"✗ TOTAL ERRORS: {len(all_errors)}")
        print("\nFirst 20 errors:")
        for addr, phase, expected, actual in all_errors[:20]:
            if actual is None:
                print(f"  Addr 0x{addr:05X} [{phase}]: READ TIMEOUT!")
            else:
                print(f"  Addr 0x{addr:05X} [{phase}]: Expected 0x{expected:04X}, Got 0x{actual:04X}")
        if len(all_errors) > 20:
            print(f"  ... and {len(all_errors) - 20} more errors")
    
    print("="*70)


def main():
    PORT = '/dev/ttyUSB2'
    BAUDRATE = 115200
    
    # MRAM AS3004316: 4Mbit = 262,144 words (0x00000 to 0x3FFFF)
    FULL_START = 0x00000
    FULL_END = 0x3FFFF
    
    print("\n" + "="*70)
    print("MRAM COMPREHENSIVE MEMORY TEST")
    print("="*70)
    print(f"Port: {PORT}")
    print(f"Baud: {BAUDRATE}")
    print("="*70)
    print(f"Full MRAM: 0x{FULL_START:05X} to 0x{FULL_END:05X} (262,144 addresses)")
    print("="*70)
    
    print("\nTest options:")
    print("  1. Quick test (first 1K addresses)")
    print("  2. Small test (first 10K addresses)")
    print("  3. Medium test (first 100K addresses)")
    print("  4. Full test (ALL 262K addresses) ⚠ LONG!")
    print("  5. Custom range")
    print("  6. Bit tests only (Walking 1s/0s)")
    
    choice = input("\nSelect test (1-6): ").strip()
    
    if choice == '1':
        start_addr, end_addr = 0x00000, 0x003FF
    elif choice == '2':
        start_addr, end_addr = 0x00000, 0x027FF
    elif choice == '3':
        start_addr, end_addr = 0x00000, 0x1869F
    elif choice == '4':
        start_addr, end_addr = FULL_START, FULL_END
        confirm = input("Full test takes ~2-3 hours! Continue? (yes/no): ")
        if confirm.lower() != 'yes':
            print("Cancelled.")
            return
    elif choice == '5':
        start_addr = int(input("Start address (hex, e.g. 1000): "), 16)
        end_addr = int(input("End address (hex, e.g. 2000): "), 16)
    elif choice == '6':
        # Bit tests only
        try:
            uart = MRAMUART(PORT, BAUDRATE)
            print("✓ Connected!\n")
            
            all_errors = []
            
            ok, errors = walking_ones_test(uart, 0x00000, 16)
            all_errors.extend(errors)
            
            ok, errors = walking_zeros_test(uart, 0x00100, 16)
            all_errors.extend(errors)
            
            print_summary(all_errors)
            uart.close()
            return
            
        except serial.SerialException as e:
            print(f"\n✗ Error: {e}")
            return
    else:
        print("Invalid choice.")
        return
    
    try:
        uart = MRAMUART(PORT, BAUDRATE)
        print("✓ Connected!\n")
        
        start_time = time.time()
        all_errors = []
        
        # Run tests
        print("\n" + "="*70)
        print("STARTING TEST SEQUENCE")
        print("="*70)
        
        # March C
        ok, errors = march_c_test(uart, start_addr, end_addr)
        all_errors.extend(errors)
        
        # Checkerboard
        ok, errors = checkerboard_test(uart, start_addr, end_addr)
        all_errors.extend(errors)
        
        # Address uniqueness
        ok, errors = address_uniqueness_test(uart, start_addr, end_addr)
        all_errors.extend(errors)
        
        elapsed = time.time() - start_time
        
        print_summary(all_errors)
        print(f"\nTotal test time: {elapsed:.1f} seconds ({elapsed/60:.1f} minutes)")
        
        uart.close()
        print("\n✓ Tests complete\n")
        
    except serial.SerialException as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\n✗ Interrupted by user")
        sys.exit(0)


if __name__ == "__main__":
    main()