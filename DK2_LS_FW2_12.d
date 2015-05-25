/*
** Public domain (or any OSS license you want)
** https://github.com/nairol
** nairolf@online.de
*/

// How to compile:
// Get the latest DMD compiler from http://dlang.org/ (e.g. DMD v2.067.1)
// Open a cmd window in the folder where this file is. (e.g. in Explorer SHIFT+Right-click => "Open cmd window here")
// Command: dmd <ThisFileName>

import std.stdio : writeln;
import std.conv : parse;
import std.file : read, write;
import std.digest.crc : CRC32;

enum offset = 0x0000B904; // ONLY FOR DK2 FIRMWARE VERSION 2.12 !!!
enum register = 0x0000;   // ONLY FOR DK2 FIRMWARE VERSION 2.12 !!!

void main( string[] args )
{
	if( args.length < 2 )
	{
		writeln("\nNo lens separation specified on command line! (default=63500 | max=65535)\n");
		return;
	}
	auto maybeNewValue = args[1].parse!uint;
	if( maybeNewValue > ushort.max )
	{
		writeln("\nLens separation value too big! (max=65535)\n");
		return;
	}
	ushort newValue = maybeNewValue & ushort.max;

	// Read the whole file into a buffer
	auto buf = cast(ubyte[]) read( "DK2Firmware_2_12.ovrf" );
	
	// Use slicing to get only the firmware image without headers (starting at file offset 0x21)
	auto fw = buf[0x21 .. $];
	
	// Calculate the ARM instruction that replaces the default "MOVW R0, #63500"
	auto newInstruction = encodeMOVimm16(register, newValue);
	
	// Replace the old instruction with the new one
	fw[offset..offset+4] = newInstruction;
	
	// Calculate the CRC32 of the firmware image and its header
	// Start at file offset 0x1B and stop after the last byte of the file
	CRC32 crc;
	crc.put( buf[0x1B..$] );
	auto crcResult = crc.finish();
	
	// Replace the old CRC32 value (at file offset 0x17) with the new one
	buf[0x17..0x1B] = crcResult;
	
	// Save the new file
	write("DK2Firmware_2_12.patched.ovrf", buf);
}

ubyte[4] encodeMOVimm16( ubyte register, ushort value )
{
	// See https://web.eecs.umich.edu/~prabal/teaching/eecs373-f11/readings/ARMv7-M_ARM.pdf (p. 347)
	auto imm4 = (0b1111000000000000 & value) >> 12;
	auto i    = (0b0000100000000000 & value) >> 11;
	auto imm3 = (0b0000011100000000 & value) >>  8;
	auto imm8 = (0b0000000011111111 & value);
	
	ubyte[4] result;
	result[0] = 0xFF & (0b01000000 | imm4);
	result[1] = 0xFF & (0b11110010 | (i << 2));
	result[2] = 0xFF & imm8;
	result[3] = 0xFF & ((imm3 << 4) | (register & 0b00001111));
	return result;
}
