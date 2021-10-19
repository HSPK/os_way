all: boot copy2img start_bochs

boot: boot.asm
	nasm boot.asm
copy2img:
	dd if=boot of=boot.img seek=0 bs=512 count=1
start_bochs:
	bochs -q -rc pre_code
clean:
	rm boot
mount:
	sudo losetup /dev/loop0 boot.img
	sudo mount /dev/loop0 /mnt/floppy/
umount:
	sudo losetup -d /dev/loop0
	sudo umount /mnt/floppy/
.PHONY: clean mount umout
