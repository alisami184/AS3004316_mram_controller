#!/usr/bin/env python3
"""
MRAM Interactive Terminal
Simple read/write interface for MRAM testing
"""

import serial
import time
import sys

class MRAMTerminal:
    def __init__(self, port: str, baudrate: int = 115200):
        """Initialize connection to MRAM controller"""
        try:
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
            print(f"✓ Connected to {port} at {baudrate} baud")
        except serial.SerialException as e:
            print(f"✗ Failed to connect: {e}")
            sys.exit(1)
    
    def write_mram(self, addr: int, data: int):
        """Write 16-bit data to MRAM address"""
        # Décomposer l'adresse en 3 bytes
        addr_h = (addr >> 16) & 0x03
        addr_m = (addr >> 8) & 0xFF
        addr_l = addr & 0xFF
        
        # Décomposer la donnée en 2 bytes
        data_h = (data >> 8) & 0xFF
        data_l = data & 0xFF
        
        # Envoyer la commande WRITE
        cmd = bytes([0x57, addr_h, addr_m, addr_l, data_h, data_l])
        self.ser.write(cmd)
        time.sleep(0.05)
        
        # Nettoyer le buffer
        self.ser.reset_input_buffer()
        
        print(f"  → Wrote 0x{data:04X} to address 0x{addr:05X}")
    
    def read_mram(self, addr: int) -> int:
        """Read 16-bit data from MRAM address"""
        # Décomposer l'adresse en 3 bytes
        addr_h = (addr >> 16) & 0x03
        addr_m = (addr >> 8) & 0xFF
        addr_l = addr & 0xFF
        
        # Envoyer la commande READ
        cmd = bytes([0x52, addr_h, addr_m, addr_l])
        self.ser.reset_input_buffer()
        self.ser.write(cmd)
        
        # Attendre la réponse
        time.sleep(0.1)
        
        if self.ser.in_waiting >= 2:
            response = self.ser.read(2)
            data = (response[0] << 8) | response[1]
            print(f"  → Read 0x{data:04X} from address 0x{addr:05X}")
            return data
        else:
            print(f"  ✗ No response from MRAM")
            return None
    
    def parse_number(self, s: str) -> int:
        """Parse a number from string (supports hex with 0x prefix)"""
        s = s.strip()
        if s.startswith('0x') or s.startswith('0X'):
            return int(s, 16)
        else:
            # Si pas de préfixe 0x, essayer hex quand même puis décimal
            try:
                return int(s, 16)
            except ValueError:
                return int(s, 10)
    
    def show_help(self):
        """Display available commands"""
        print("\n" + "="*60)
        print("MRAM TERMINAL - Available Commands")
        print("="*60)
        print("  w <addr> <data>  - Write data to address")
        print("                     Example: w 0x100 0xAA55")
        print("                     Example: w 100 AA55")
        print("")
        print("  r <addr>         - Read data from address")
        print("                     Example: r 0x100")
        print("                     Example: r 100")
        print("")
        print("  help             - Show this help message")
        print("  quit / exit      - Exit the terminal")
        print("="*60)
        print("Note: Addresses can be 0x00000 to 0x3FFFF (18-bit)")
        print("      Data values can be 0x0000 to 0xFFFF (16-bit)")
        print("="*60 + "\n")
    
    def run(self):
        """Main interactive loop"""
        print("\n" + "="*60)
        print("MRAM INTERACTIVE TERMINAL")
        print("="*60)
        print("Type 'help' for available commands")
        print("="*60 + "\n")
        
        while True:
            try:
                # Lire la commande de l'utilisateur
                cmd = input("mram> ").strip()
                
                if not cmd:
                    continue
                
                # Séparer la commande et les arguments
                parts = cmd.split()
                command = parts[0].lower()
                
                # Traiter la commande
                if command in ['quit', 'exit', 'q']:
                    print("\n✓ Goodbye!")
                    break
                
                elif command in ['help', 'h', '?']:
                    self.show_help()
                
                elif command in ['w', 'write']:
                    if len(parts) != 3:
                        print("  ✗ Usage: w <addr> <data>")
                        continue
                    
                    try:
                        addr = self.parse_number(parts[1])
                        data = self.parse_number(parts[2])
                        
                        # Vérifier les limites
                        if addr < 0 or addr > 0x3FFFF:
                            print(f"  ✗ Address out of range (must be 0x00000-0x3FFFF)")
                            continue
                        
                        if data < 0 or data > 0xFFFF:
                            print(f"  ✗ Data out of range (must be 0x0000-0xFFFF)")
                            continue
                        
                        self.write_mram(addr, data)
                    
                    except ValueError:
                        print("  ✗ Invalid number format")
                
                elif command in ['r', 'read']:
                    if len(parts) != 2:
                        print("  ✗ Usage: r <addr>")
                        continue
                    
                    try:
                        addr = self.parse_number(parts[1])
                        
                        # Vérifier les limites
                        if addr < 0 or addr > 0x3FFFF:
                            print(f"  ✗ Address out of range (must be 0x00000-0x3FFFF)")
                            continue
                        
                        self.read_mram(addr)
                    
                    except ValueError:
                        print("  ✗ Invalid number format")
                
                else:
                    print(f"  ✗ Unknown command: '{command}'")
                    print("  Type 'help' for available commands")
            
            except KeyboardInterrupt:
                print("\n\n✓ Interrupted by user. Type 'quit' to exit.")
                continue
            
            except Exception as e:
                print(f"  ✗ Error: {e}")
    
    def close(self):
        """Close serial connection"""
        if self.ser and self.ser.is_open:
            self.ser.close()


def main():
    PORT = '/dev/ttyUSB0'  # Change selon ton système
    BAUDRATE = 115200
    
    terminal = MRAMTerminal(PORT, BAUDRATE)
    
    try:
        terminal.run()
    finally:
        terminal.close()


if __name__ == "__main__":
    main()