#!/usr/bin/env python3
"""
MRAM Non-Volatility Test
Write data, power cycle the board, then verify data is retained
"""

import serial
import time
import sys
import os

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
        time.sleep(0.5)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        time.sleep(0.2)  # Délai supplémentaire pour stabilisation
        # ← AJOUTER: Attendre tPU de la MRAM
        print("Waiting for MRAM power-up (tPU = 1ms)...")
        time.sleep(1.5)  # 1.5s pour être sûr (FPGA boot + MRAM tPU)
        print("✓ MRAM ready")
        
    def write_mram(self, addr: int, data: int, delay: float = 0.005) -> bool:
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
    
    def read_mram(self, addr: int, delay: float = 0.05) -> int:
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
        return None

    def warmup(self):
        """Perform dummy reads to stabilize interface after power-up"""
        print("\nWarming up interface...")
        
        # CRITICAL: First access after reset to address 0x00000 fails
        # Do a dummy write to change addr_reg from reset value
        self.write_mram(0x3FFFF, 0x0000)
        time.sleep(0.1)
        
        # Now warm up with reads
        for addr in [0x3FFFF, 0x00100, 0x01000]:
            _ = self.read_mram(addr)
            time.sleep(0.05)
        
        # Clear buffers
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        print("✓ Interface stabilized")
    
    def close(self):
        self.ser.close()


def write_test_data(uart: MRAMUART):
    """Write test pattern to MRAM"""
    print("\n" + "="*70)
    print("PHASE 1: WRITING TEST DATA")
    print("="*70)
    
    # Test data: mix of patterns
    test_data = [
        (0x00010, 0xBAEF, "Magic pattern 1"),  # Commence à 0x10
        (0x00011, 0xBEED, "Magic pattern 2"),
        (0x00012, 0xAAFE, "Magic pattern 3"),
        (0x00013, 0xCABE, "Magic pattern 4"),
        (0x00100, 0x4234, "Sequential 1"),
        (0x00101, 0x2678, "Sequential 2"),
        (0x00102, 0x1ABC, "Sequential 3"),
        (0x00103, 0xCEF0, "Sequential 4"),
        (0x00200, 0xFAAA, "Alternating A"),
        (0x00201, 0x0555, "Alternating 5"),
        (0x00202, 0xEFFF, "All ones"),
        (0x00203, 0x2000, "All zeros"),
        (0x01000, 0x40FF, "Byte pattern 1"),
        (0x01001, 0x8F00, "Byte pattern 2"),
        (0x02000, 0x4001, "Edge bits 1"),
        (0x02001, 0x3002, "Edge bits 2"),
    ]
    
    print(f"\nWriting {len(test_data)} test locations...")
    print("-"*70)
    
    for addr, data, description in test_data:
        uart.write_mram(addr, data)
        print(f"  ✓ 0x{addr:05X} ← 0x{data:04X}  ({description})")
    
    print("\n" + "="*70)
    print("WRITE PHASE COMPLETE")
    print("="*70)
    
    # Save test data to file for verification phase
    with open('/tmp/mram_nonvol_test.txt', 'w') as f:
        for addr, data, desc in test_data:
            f.write(f"{addr:05X} {data:04X} {desc}\n")
    
    return test_data


def verify_test_data(uart: MRAMUART):
    """Read and verify test data from MRAM"""
    print("\n" + "="*70)
    print("PHASE 2: VERIFYING DATA RETENTION")
    print("="*70)
    
    # Load expected data from file
    if not os.path.exists('/tmp/mram_nonvol_test.txt'):
        print("\n✗ ERROR: Test data file not found!")
        print("You must run WRITE phase first (option 1)")
        return False
    
    # # WARM-UP: Stabilize interface after reconnection
    uart.warmup()
    
    test_data = []
    with open('/tmp/mram_nonvol_test.txt', 'r') as f:
        for line in f:
            parts = line.strip().split(maxsplit=2)
            addr = int(parts[0], 16)
            data = int(parts[1], 16)
            desc = parts[2] if len(parts) > 2 else ""
            test_data.append((addr, data, desc))
    
    print(f"\nReading {len(test_data)} test locations...")
    print("-"*70)
    
    errors = 0
    for addr, expected, description in test_data:
        actual = uart.read_mram(addr)
        
        if actual is None:
            print(f"  ✗ 0x{addr:05X}: READ TIMEOUT")
            errors += 1
        elif actual == expected:
            print(f"  ✓ 0x{addr:05X} → 0x{actual:04X}  ({description})")
        else:
            print(f"  ✗ 0x{addr:05X} → 0x{actual:04X} (expected 0x{expected:04X}) - {description}")
            errors += 1
    
    print("\n" + "="*70)
    print("VERIFICATION COMPLETE")
    print("="*70)
    
    if errors == 0:
        print("\n🎉 SUCCESS! All data retained after power cycle!")
        print("✓ MRAM non-volatility confirmed")
    else:
        print(f"\n✗ FAILED: {errors} errors detected")
        print("⚠ Data was NOT retained correctly")
    
    print("="*70)
    return errors == 0


def main():
    PORT = '/dev/ttyUSB2'
    BAUDRATE = 115200
    
    print("\n" + "="*70)
    print("MRAM NON-VOLATILITY TEST")
    print("="*70)
    print(f"Port: {PORT}")
    print(f"Baud: {BAUDRATE}")
    print("="*70)
    
    print("\nThis test verifies that MRAM retains data without power.")
    print("\nTest procedure:")
    print("  1. Write test data to MRAM")
    print("  2. Disconnect power from Nexys Video")
    print("  3. Wait 10+ seconds")
    print("  4. Reconnect power")
    print("  5. Verify data is still present")
    print("="*70)
    
    print("\nSelect operation:")
    print("  1. WRITE test data (do this first)")
    print("  2. READ and verify (after power cycle)")
    print("  3. Full test (write, prompt to power cycle, then verify)")
    
    choice = input("\nSelect (1-3): ").strip()
    
    try:
        uart = MRAMUART(PORT, BAUDRATE)
        print("✓ Connected!\n")
        
        if choice == '1':
            # Write phase
            write_test_data(uart)
            print("\n" + "="*70)
            print("NEXT STEPS:")
            print("="*70)
            print("1. Disconnect power from Nexys Video (USB + power jack)")
            print("2. Wait at least 10 seconds")
            print("3. Reconnect power")
            print("4. Run this script again and select option 2")
            print("="*70 + "\n")
            
        elif choice == '2':
            # Verify phase
            verify_test_data(uart)
            
        elif choice == '3':
            # Full automated test
            test_data = write_test_data(uart)
            
            print("\n" + "="*70)
            print("POWER CYCLE REQUIRED")
            print("="*70)
            print("\nFollow these steps:")
            print("  1. Disconnect power from Nexys Video")
            print("  2. Wait 10 seconds")
            print("  3. Reconnect power")
            print("  4. Press ENTER to continue verification")
            print("="*70)
            
            input("\nPress ENTER after power cycle is complete...")
            
            print("\nReconnecting to device...")
            uart.close()
            time.sleep(2)
            uart = MRAMUART(PORT, BAUDRATE)
            print("✓ Reconnected!\n")
            
            verify_test_data(uart)
            
        else:
            print("Invalid choice.")
            
        uart.close()
        print("\n✓ Test complete\n")
        
    except serial.SerialException as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n\n✗ Interrupted by user")
        sys.exit(0)


if __name__ == "__main__":
    main()