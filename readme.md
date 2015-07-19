# Lens Separation Adjuster for DK2 Firmware

---

**Patching the firmware is no longer required. Oculus have added support for overriding the lens seperation distance to the official Runtime. [More information here.](https://www.reddit.com/r/oculus/comments/3dugxj/thank_you_oculus_sdk_0601_now_supports_lens/)**

---

---

---

**I do NOT own a DK2 and have NOT tested the firmware files that this program produces. Use at your own risk!**  
I **have** checked firmware files produced by this tool in a disassembler and they look good.

There are two programs: **DK2_LS_FW** and **DK2_LS_FW2_12**

If you want to understand how patching the firmware works and how patching a newer firmware version than 2.12 would work you should have a look at **DK2_LS_FW**. This program tries to find the CPU instruction that sets the lens separation value and modifies it by injecting own instructions.

If you just want to change the lens separation value in the original DK2 firmware 2.12 you should use **DK2_LS_FW2_12**. It's the quick and dirty version of the other program and works just for this specific firmware version.

## Command line arguments for DK2_LS_FW:  
    DK2_LS_FW <Lens separation value in micrometers> <Path to firmware file>

## Command line arguments for DK2_LS_FW2_12:  
    DK2_LS_FW2_12 [Lens separation value in micrometers]  
If you don't specify the lens separation on the command line, the program will ask for it.  
The program must be in the same directory as *DK2Firmware_2_12.ovrf*.

## [Download links](https://github.com/nairol/DK2-Firmware-Patcher/releases)
