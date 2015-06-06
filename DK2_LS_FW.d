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
import std.bitmanip : littleEndianToNative, nativeToLittleEndian;
import std.digest.crc : CRC32;
import std.path : stripExtension;
import std.algorithm : any;
import std.math: abs;

enum fileHeaderLength = 23;
enum imageHeaderLength = 10;
enum firmwareFileOffset = fileHeaderLength + imageHeaderLength;

enum baseAddressFlash = 0x08004000;
enum defaultLensSeparation = 63500;

void main( string[] args )
{
	writeln();
	if( args.length < 3 )
	{
		writeln("Parameters: <lens separation in um> <Path to DK2 firmware>");
		return;
	}
	
	auto lensSeparation = args[1].parse!uint;
	
	string firmwarePath = args[2];
	if( firmwarePath.exists() == false )
	{
		writeln("Error: Firmware path incorrect");
		return;
	}
	
	// Read the whole file into a buffer
	auto buf = cast(ubyte[]) firmwarePath.read();
	
	// Very simple check. I should do more validation with the data in the header...
	if( buf[0..4] != ['O', 'V', 'R', 'F'] )
	{
		writeln("Error: This is not a valid Oculus firmware file.");
		return;
	}
	
	// This assumes that there is only one firmware image in the file and that it is for the DK2
	auto firmwareLength = buf[0x1D .. 0x21].littleEndianToNative!uint;
	if( firmwareLength + firmwareFileOffset > buf.length )
	{
		writeln("Error: Image size in header wrong or file incomplete!");
		return;
	}
	
	// Get the slice of the file that only contains the firmware image
	auto fw = buf[0x21 .. 0x21+firmwareLength];
	
	writeln("Searching the default lens separation value in the file...");
	
	auto offsets = fw.findOffsetsFor_MOV_imm_T3( defaultLensSeparation );
	if( offsets.length == 0 )
	{
		writeln("Error: Could not find the default lens separation value in the firmware!");
		return;
	}
	if( offsets.length > 1 )
	{
		writeln("Error: Found more than one possible addresses to patch:");
		foreach( offset; offsets )
		{
			writefln( "0x%.8X", offset );
		}
		return;
	}
	
	auto originalOffset = offsets[0];
	auto mov = fw[originalOffset..originalOffset+4].decode_MOV_imm_T3();
	writefln("Found at file offset 0x%.8X (address 0x%.8X): MOVW R%d, #%d",
	         firmwareFileOffset+originalOffset, baseAddressFlash+originalOffset,
	         mov.register, mov.value);
	
	writeln();
	writeln("Checking if there is free space for the detour function...");
	if( fw[$-256..$].any() )
	{
		writefln("Error: There is data or code in the last 256 bytes! Too risky to patch.");
		return;
	}
	writeln("The last 256 bytes contain only zeros. They are assumed to be free space.");
	writeln();
	writefln("Changing lens separation to %d micrometers (0x%.8X)...", lensSeparation, lensSeparation);
	writeln();
	writeln("The following changes have been made:");
	writeln();
	writeln("File Offset | Address  | Data        | Decoded Data");
	writeln("------------+----------+-------------+------------------");
	
	auto detourFuncOffset = fw.length - 12; // Detour function will be in the last 12 bytes of flash
	auto detourFuncAddress = baseAddressFlash + detourFuncOffset;
	
	// Replace the 32 bit MOV instruction with a unconditional branch (jump) to the detour
	//  function that will be written later to the very top of flash memory.
	auto branchForwardDifference = detourFuncOffset - (originalOffset+4);
	auto branchForwardInstruction = encode_B_T4( branchForwardDifference );
	fw[originalOffset..originalOffset+4] = branchForwardInstruction[];
	writefln(" %.8X   | %.8X | %.4X %.4X   | B.W %.8X",
	         firmwareFileOffset+originalOffset,
	         baseAddressFlash+originalOffset,
	         branchForwardInstruction[0..2].littleEndianToNative!ushort,
	         branchForwardInstruction[2..4].littleEndianToNative!ushort,
	         detourFuncAddress);
	
	// First detour function instruction: Load the 32 bit lens separation value
	// The parameter addressDifference (4) means that the data is loaded from (PC+4).
	// PC (program counter) is the address of the next instruction.
	auto detourFunc = fw[detourFuncOffset .. $]; // Get a slice of the last 12 bytes of flash memory
	detourFunc[0..4] = encode_LDR_literal_T2( mov.register, 4); // Instr: Load word from (here + 8)
	writefln(" %.8X   | %.8X | %.4X %.4X   | LDR.W R%d, [PC,#%d]",
	         firmwareFileOffset+detourFuncOffset,
	         detourFuncAddress,
	         detourFunc[0..2].littleEndianToNative!ushort,
	         detourFunc[2..4].littleEndianToNative!ushort,
	         mov.register, 4);
	
	// Second detour function instruction: Branch (jump) back into the original function
	// Destination is the next instruction after the MOV (that has been replaced by our branch)
	auto branchBackDifference = (originalOffset+4) - (detourFuncOffset+8);
	detourFunc[4..8] = encode_B_T4( branchBackDifference ); // Instr: Jump to next original instruction
	writefln(" %.8X   | %.8X | %.4X %.4X   | B.W %.8X",
	         firmwareFileOffset+detourFuncOffset+4,
	         detourFuncAddress+4,
	         detourFunc[4..6].littleEndianToNative!ushort,
	         detourFunc[6..8].littleEndianToNative!ushort,
	         baseAddressFlash+originalOffset+4);
	
	// Lens separation value, 32 bit, unsigned(?), little-endian (LSB first)
	// This will be loaded by the first detour function instruction
	detourFunc[8..12] = lensSeparation.nativeToLittleEndian;
	writefln(" %.8X   | %.8X | %.8X    | Lens separation value: %d",
	         firmwareFileOffset+detourFuncOffset+8,
	         detourFuncAddress+8,
	         detourFunc[8..12].littleEndianToNative!uint,
	         detourFunc[8..12].littleEndianToNative!uint);
	
	// Update the firmware header + image CRC32 value
	CRC32 crc;
	crc.put( buf[0x1B..0x21+firmwareLength] );
	auto crcResult = crc.finish();
	buf[0x17..0x1B] = crcResult;
	writefln(" %.8X   |   n/a    | %.2X %.2X %.2X %.2X | New firmware CRC32 value",
	         0x17, buf[0x17], buf[0x18], buf[0x19], buf[0x1A]);
	
	writeln();
	
	string newFile = firmwarePath.stripExtension() ~ ".patched.ovrf";
	writeln("Writing patched firmware image to ", newFile);
	write(newFile, buf);
	
	writeln("File saved. Use the official Oculus configuration tool to upload the new");
	writeln(" firmware file to your DK2.");
	writeln();
	writeln("USE THIS NEW FIRMWARE AT YOUR OWN RISK! Oculus does not support custom");
	writeln(" firmware on your device. If it breaks, you will have to fix it yourself.");
	writeln();
}

bool is_MOV_imm_T3( const ubyte[] instruction )
{
	// See https://web.eecs.umich.edu/~prabal/teaching/eecs373-f11/readings/ARMv7-M_ARM.pdf (p. 347)
	return ((instruction[0] & 0b11110000) == 0b01000000) &&
	       ((instruction[1] & 0b11111011) == 0b11110010) &&
	       ((instruction[3] & 0b10000000) == 0b00000000);
}

auto decode_MOV_imm_T3( const ubyte[] instruction )
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
uint[] findOffsetsFor_MOV_imm_T3( const ubyte[] buffer, ushort operand )
{
	uint[] results = [];
	
	for( uint offset = 0; (offset+4)<buffer.length; offset+=2 )
	{
		auto slice = buffer[offset .. offset+4];
		
		if( slice.is_MOV_imm_T3() )
		{
			auto mov = decode_MOV_imm_T3( slice );
			if( mov.value == operand )
			{
				results.length = results.length + 1;
				results[$-1] = offset;
			}
		}
	}
	return results;
}

ubyte[4] encode_B_T4( int addressDifference )
{
	// See https://web.eecs.umich.edu/~prabal/teaching/eecs373-f11/readings/ARMv7-M_ARM.pdf (p. 239)
	if( addressDifference % 2 != 0 )
	{
		throw new Exception("encode_B_T4: Address difference LSB set! (Instruction or target unaligned)");
	}
	enum MIN = -(2^^24)  ; // -16777216
	enum MAX =  (2^^24)-1; //  16777215
	
	if( addressDifference > MAX || addressDifference < MIN )
	{
		throw new Exception("encode_B_T4: Address difference too big to encode in T4!");
	}
	
	auto imm24 = cast(uint) addressDifference;
	imm24 = (imm24 >> 1) & 0x00FFFFFF;
	
	auto S     = (0b10000000_00000000_00000000 & imm24) >> 23;
	auto I1    = (0b01000000_00000000_00000000 & imm24) >> 22;
	auto I2    = (0b00100000_00000000_00000000 & imm24) >> 21;
	auto imm10 = (0b00011111_11111000_00000000 & imm24) >> 11;
	auto imm11 = (0b00000000_00000111_11111111 & imm24);
	
	auto J1 = ~(I1 ^ S) & 0b00000001;
	auto J2 = ~(I2 ^ S) & 0b00000001;
	
	ubyte[4] result;
	result[0] = 0xFF & imm10;
	result[1] = 0xFF & (0b11110000 | (S << 2) | (imm10 >> 8));
	result[2] = 0xFF & imm11;
	result[3] = 0xFF & (0b10010000 | (J1 << 5) | (J2 << 3) | (imm11 >> 8));
	
	return result;
}

ubyte[4] encode_LDR_literal_T2( ubyte register, short addressDifference )
{
	// See https://web.eecs.umich.edu/~prabal/teaching/eecs373-f11/readings/ARMv7-M_ARM.pdf (p. 289)
	if( register > 0b1111 )
	{
		throw new Exception("encode_LDR_literal_T2: register invalid");
	}
	
	auto offset = abs( addressDifference );
	if( offset > 0xFFF )
	{
		throw new Exception("encode_LDR_literal_T2: addressDifference too big (max = +-4095)");
	}
	
	ubyte[4] result;
	result[0] = (addressDifference >= 0) ? 0b11011111 : 0b01011111;
	result[1] = 0b11111000;
	result[2] = 0xFF & offset;
	result[3] = 0xFF & (( register << 4) | (offset >> 8));
	
	return result;
}
