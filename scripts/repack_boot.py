#!/usr/bin/env python3
"""
Android Boot Image v2 Packer for Redmi K30 5G (picasso)
"""
import argparse
import math
import struct
import sys

def pad_to_page(data: bytes, page_size: int) -> bytes:
    pad = (page_size - (len(data) % page_size)) % page_size
    return data + (b"\x00" * pad)

def main():
    parser = argparse.ArgumentParser(description="Pack Android Boot Image v2")
    parser.add_argument("--kernel", required=True, help="Path to Image")
    parser.add_argument("--ramdisk", required=False, default="", help="Path to ramdisk.cpio/img")
    parser.add_argument("--dtb", required=False, default="", help="Path to dtb")
    parser.add_argument("--cmdline", default="console=ttyMSM0,115200n8 androidboot.hardware=qcom androidboot.console=ttyMSM0 androidboot.memcg=1 lpm_levels.sleep_disabled=1 msm_rtb.filter=0x237 service_locator.enable=1 androidboot.usbcontroller=a600000.dwc3 swiotlb=2048 loop.max_part=7 cgroup.memory=nokmem,nosocket reboot=panic_warm buildvariant=userdebug", help="Kernel cmdline")
    parser.add_argument("--output", required=True, help="Output boot.img path")
    args = parser.parse_args()

    page_size = 4096
    hdr_ver = 2

    with open(args.kernel, "rb") as f:
        kernel_data = f.read()

    ramdisk_data = b""
    if args.ramdisk:
        with open(args.ramdisk, "rb") as f:
            ramdisk_data = f.read()

    dtb_data = b""
    if args.dtb:
        with open(args.dtb, "rb") as f:
            dtb_data = f.read()

    k_sz = len(kernel_data)
    r_sz = len(ramdisk_data)
    dtb_sz = len(dtb_data)

    k_addr = 0x00008000
    r_addr = 0x01000000
    s_sz = 0
    s_addr = 0x00000000
    t_addr = 0x00000100
    os_ver = 0
    name = b""
    cmdline = args.cmdline.encode("latin1")[:512]
    extra_cmdline = b""
    rec_dtbo_sz = 0
    rec_dtbo_off = 0
    hdr_sz = 1660
    dtb_addr = 0x01f00000

    # Build 1660-byte header
    hdr = bytearray(1660)
    struct.pack_into("<8s9II", hdr, 0, b"ANDROID!", k_sz, k_addr, r_sz, r_addr, s_sz, s_addr, t_addr, page_size, hdr_ver, os_ver)
    hdr[48:48+len(name)] = name
    hdr[64:64+len(cmdline)] = cmdline
    hdr[608:608+len(extra_cmdline)] = extra_cmdline
    struct.pack_into("<IQIIQ", hdr, 1632, rec_dtbo_sz, rec_dtbo_off, hdr_sz, dtb_sz, dtb_addr)

    header_block = pad_to_page(bytes(hdr), page_size)
    kernel_block = pad_to_page(kernel_data, page_size)
    ramdisk_block = pad_to_page(ramdisk_data, page_size) if r_sz > 0 else b""
    dtb_block = pad_to_page(dtb_data, page_size) if dtb_sz > 0 else b""

    with open(args.output, "wb") as out:
        out.write(header_block)
        out.write(kernel_block)
        if ramdisk_block:
            out.write(ramdisk_block)
        if dtb_block:
            out.write(dtb_block)

    print(f"[+] Successfully generated boot.img at {args.output}")
    print(f"    Kernel: {k_sz} bytes | Ramdisk: {r_sz} bytes | DTB: {dtb_sz} bytes")

if __name__ == "__main__":
    main()
