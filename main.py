#!/usr/bin/env python3
"""
MRAM Automated Test Script
Writes multiple values then reads them back to verify
"""

import serial
import time
import sys

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
        
    def write_mram(self, addr: int, data: int) -> bool:
        """Write 16-bit data to address"""
        addr_h = (addr >> 16) & 0x03
        addr_m = (addr >> 8) & 0xFF
        addr_l = addr & 0xFF
        data_h = (data >> 8) & 0xFF
        data_l = data & 0xFF
        
        cmd = bytes([0x57, addr_h, addr_m, addr_l, data_h, data_l])
        self.ser.write(cmd)
        time.sleep(0.05)
        
        self.ser.reset_input_buffer()
        return True
    
    def read_mram(self, addr: int) -> int:
        """Read 16-bit data from address"""
        addr_h = (addr >> 16) & 0x03
        addr_m = (addr >> 8) & 0xFF
        addr_l = addr & 0xFF
        
        cmd = bytes([0x52, addr_h, addr_m, addr_l])
        self.ser.reset_input_buffer()
        self.ser.write(cmd)
        
        time.sleep(0.1)
        
        if self.ser.in_waiting >= 2:
            response = self.ser.read(2)
            data = (response[0] << 8) | response[1]
            return data
        else:
            return None
    
    def close(self):
        self.ser.close()


def run_test(uart, start_addr: int, count: int, pattern: str = "sequential"):
    """
    Run write/read test
    """
    print("\n" + "="*70)
    print(f"TEST: {count} locations starting at 0x{start_addr:05X}")
    print(f"Pattern: {pattern}")
    print("="*70)
    
    # Générer les données de test
    test_data = []
    for i in range(count):
        if pattern == "sequential":
            data = i & 0xFFFF
        elif pattern == "aa55":
            data = 0xAA55 if i % 2 == 0 else 0x55AA
        elif pattern == "increment":
            data = ((i+1) * 0x1111) & 0xFFFF
        else:
            data = i & 0xFFFF
        test_data.append((start_addr + i, data))
    
    # Phase 1: WRITE
    print("\n[PHASE 1: WRITING]")
    print("-" * 70)
    for addr, data in test_data:
        uart.write_mram(addr, data)
        print(f"  W 0x{addr:05X} ← 0x{data:04X}")
    
    print(f"\n✓ Wrote {count} locations")
    print("\nWaiting 100ms before reading...")
    time.sleep(0.1)
    
    # Phase 2: READ
    print("\n[PHASE 2: READING]")
    print("-" * 70)
    results = []
    for addr, expected in test_data:
        actual = uart.read_mram(addr)
        match = "✓" if actual == expected else "✗"
        results.append((addr, expected, actual))
        print(f"  R 0x{addr:05X} → 0x{actual:04X} (expected 0x{expected:04X}) {match}")
    
    # Statistiques
    print("\n" + "="*70)
    print("RESULTS")
    print("="*70)
    
    correct = sum(1 for _, exp, act in results if exp == act)
    
    print(f"READ: {correct}/{count} correct ({100*correct/count:.1f}%)")
    
    if correct < count:
        print("\n⚠ Failures detected!")
        print("Addresses with errors:")
        for addr, exp, act in results:
            if exp != act:
                print(f"  0x{addr:05X}: got 0x{act:04X}, expected 0x{exp:04X}")
    else:
        print("\n✓ All reads CORRECT!")
    
    print("="*70 + "\n")


def main():
    PORT = '/dev/ttyUSB2'
    BAUDRATE = 115200
    
    print("\n" + "="*70)
    print("MRAM AUTOMATED TEST - MULTIPLE ADDRESS RANGES")
    print("="*70)
    print(f"Port: {PORT}")
    print(f"Baud: {BAUDRATE}")
    print("="*70)
    
    try:
        uart = MRAMUART(PORT, BAUDRATE)
        print("✓ Connected!\n")
        
        # Test à différentes adresses pour voir si le problème est uniforme
        run_test(uart, start_addr=0x00100, count=8, pattern="aa55")
        
        input("\nPress ENTER to run next test...")
        
        run_test(uart, start_addr=0x01000, count=8, pattern="aa55")
        
        input("\nPress ENTER to run next test...")
        
        run_test(uart, start_addr=0x10000, count=8, pattern="aa55")
        
        input("\nPress ENTER to run next test...")
        
        run_test(uart, start_addr=0x20000, count=8, pattern="aa55")
        
        uart.close()
        print("\n✓ Tests completed\n")
        
    except serial.SerialException as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\n✗ Interrupted by user")
        sys.exit(0)


if __name__ == "__main__":
    main()