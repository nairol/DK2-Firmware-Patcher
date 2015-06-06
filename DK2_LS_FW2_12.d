/*
** Public domain (or any OSS license you want)
** https://github.com/nairol
** nairolf@online.de
*/

// How to compile:
// Get the latest DMD compiler from http://dlang.org/ (e.g. DMD v2.067.1)
// Open a cmd window in the folder where this file is. (e.g. in Explorer SHIFT+Right-click => "Open cmd window here")
// Command: dmd <ThisFileName>

import std.stdio : writeln, readf;
import std.conv : parse;
import std.file : read, write;
import std.digest.crc : CRC32;
import std.bitmanip : littleEndianToNative, nativeToLittleEndian;

void main( string[] args )
{
	uint lensSeparation = 63500;
	
	if( args.length < 2 )
	{
		writeln("\nPlease enter the new lens separation in micrometers: (default=63500)");
		readf("%s", &lensSeparation);
	}
	else
	{
		lensSeparation = args[1].parse!uint();
	}
	
/* HERE COMES THE IMPORTANT PART ... */
	
	// Read the whole file into a buffer
	auto buf = cast(ubyte[]) read( "DK2Firmware_2_12.ovrf" );
	
	// Change the code and add the lens separation data
	buf[0x00B925..0x00B929] = [0x10, 0xF0, 0x76, 0xBB]; // B.W 0801FFF4
	buf[0x01C015..0x01C019] = [0xDF, 0xF8, 0x04, 0x00]; // LDR.W R0, [PC,#4]
	buf[0x01C019..0x01C01D] = [0xEF, 0xF7, 0x86, 0xBC]; // B.W 0800F908
	buf[0x01C01D..0x01C021] = lensSeparation.nativeToLittleEndian();
	
	// Calculate the CRC32 of the firmware image and its header
	// Start at file offset 0x1B and stop after the last byte of the file
	CRC32 crc;
	crc.put( buf[0x1B..$] );
	auto crcResult = crc.finish();
	
	// Replace the old CRC32 value (at file offset 0x17) with the new one
	buf[0x000017..0x00001B] = crcResult[];
	
	// Save the new file
	write("DK2Firmware_2_12.patched.ovrf", buf);
	
/* ... END OF THE IMPORTANT PART */
	
	writeln();
	writeln("Lens separation has been changed to ",
	        buf[0x01C01D..0x01C021].littleEndianToNative!uint,
	        " micrometers.");
	writeln();
	writeln("Patched firmware was saved as DK2Firmware_2_12.patched.ovrf");
	writeln();
	writeln("Use the official Oculus configuration tool to upload the new");
	writeln(" firmware file to your DK2.");
	writeln();
	writeln("USE THIS NEW FIRMWARE AT YOUR OWN RISK! Oculus does not support custom");
	writeln(" firmware on your device. If it breaks, you will have to fix it yourself.");
	writeln();
}
