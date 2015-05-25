/*
** Public domain (or any OSS license you want)
** https://github.com/nairol
** nairolf@online.de
*/

// How to compile:
// Get the latest DMD compiler from http://dlang.org/ (e.g. DMD v2.067.1)
// Open a cmd window in the folder where this file is. (e.g. in Explorer SHIFT+Right-click => "Open cmd window here")
// Command: dmd <ThisFileName>

import std.stdio : writeln, writefln;
import std.file : exists, read, write;
import std.conv : parse;
import std.typecons : tuple;
import std.bitmanip : littleEndianToNative;
import std.digest.crc : CRC32;
import std.path : stripExtension;

void main( string[] args )
{
	writeln();
	if( args.length < 3 )
	{
		writeln("Parameters: <lens separation in um> <Path to DK2 firmware>");
		return;
	}
	
	uint lensSeperation = args[1].parse!uint;
	if( lensSeperation > ushort.max )
	{
		writeln("Lens separation too big (max. 65535)");
		return;
	}
	ushort newValue = lensSeperation & ushort.max;
	
	string firmwarePath = args[2];
	if( firmwarePath.exists() == false )
	{
		writeln("Firmware path incorrect");
		return;
	}
	
	// Read the whole file into a buffer
	auto buf = cast(ubyte[]) firmwarePath.read();
	
	// Very simple check. I should do more validation with the data in the header...
	if( buf[0..4] != [0x4F, 0x56, 0x52, 0x46] )
	{
		writeln("This is not a valid Oculus firmware file.");
		return;
	}
	
	// This assumes that there is only one firmware image in the file and that the first one is the
	auto firmwareLength = buf[0x1D .. 0x21].littleEndianToNative!uint;
	if( firmwareLength + 33 > buf.length )
	{
		writeln("Image size in header wrong or file incomplete!");
		return;
	}
	
	auto fw = buf[0x21 .. 0x21+firmwareLength];
	
	writeln("Searching the default value...");
	
	auto offsets = fw.findOffsetsForMOVimm16( 63500 );
	if( offsets.length == 0 )
	{
		writeln("Could not find the default lens separation value in the firmware!");
		return;
	}
	if( offsets.length > 1 )
	{
		writeln("Found more than one possible addresses to patch:");
		foreach( offset; offsets )
		{
			writefln( "0x%.8X", offset );
		}
		return;
	}
	
	auto offset = offsets[0];
	auto mov = fw[offset..offset+4].decodeMOVimm16();
	writefln("Found default value at address 0x%.8X (register=%d)", offsets[0], mov.register);
	
	writefln("Changing lens separation value to %d (0x%.4X)", newValue, newValue);
	fw[offset..offset+4] = encodeMOVimm16(mov.register, newValue);
	
	writeln("Recalculating CRC32...");
	CRC32 crc;
	crc.put( buf[0x1B..0x21+firmwareLength] );
	auto crcResult = crc.finish();
	buf[0x17..0x1B] = crcResult;
	writefln("New CRC32 is %(%.2X%)", crcResult);
	
	string newFile = firmwarePath.stripExtension() ~ "_Fixed_Lens_Seperation.ovrf";
	writeln("Writing patched firmware image to ", newFile);
	write(newFile, buf);
	
	writeln("File saved. Use the official Oculus configuration tool to upload the new");
	writeln(" firmware file to your DK2.");
	writeln();
	writeln("USE THIS NEW FIRMWARE AT YOUR OWN RISK! Oculus does not support custom");
	writeln(" firmware on your device. If it breaks, you will have to fix it yourself.");
	writeln();
}

bool isMOVimm16( const ubyte[] instruction )
{
	// See https://web.eecs.umich.edu/~prabal/teaching/eecs373-f11/readings/ARMv7-M_ARM.pdf (p. 347)
	return ((instruction[0] & 0b11110000) == 0b01000000) &&
	       ((instruction[1] & 0b11111011) == 0b11110010) &&
	       ((instruction[3] & 0b10000000) == 0b00000000);
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

auto decodeMOVimm16( const ubyte[] instruction )
{
	// See https://web.eecs.umich.edu/~prabal/teaching/eecs373-f11/readings/ARMv7-M_ARM.pdf (p. 347)
	auto imm4 = (0b00001111 & instruction[0]);
	auto i    = (0b00000100 & instruction[1]) >> 2;
	auto imm8 = (0b11111111 & instruction[2]);
	auto imm3 = (0b01110000 & instruction[3]) >> 4;
	ubyte reg = (0b00001111 & instruction[3]);
	
	ushort val = ushort.max & ((imm4 << 12) | (i << 11) | (imm3 << 8) | imm8);
	return tuple!("register", "value")(reg, val);
}


// Find all offsets of MOV instructions with given 16-bit immediate operand
// Assumes the buffer is a firmware image and the image starts at a 2 byte aligned target address
uint[] findOffsetsForMOVimm16( const ubyte[] buffer, ushort operand )
{
	uint[] results = [];
	
	for( uint offset = 0; (offset+4)<buffer.length; offset+=2 )
	{
		auto slice = buffer[offset .. offset+4];
		
		if( slice.isMOVimm16() )
		{
			auto mov = decodeMOVimm16( slice );
			if( mov.value == operand )
			{
				results.length = results.length + 1;
				results[$-1] = offset;
			}
		}
	}
	return results;
}