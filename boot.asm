[BITS 16]
org 0x0

START:
    jmp LOADER_MAIN

OEM                 db  "DemonWay" ; 8 bytes
BytesPerSector:     dw  512
SectorsPerCluster:  db  1
ReservedSectorsCnt: dw  1
FatNumber:          db  2
RootDirEntries:     dw  224
SectorNumber:       dw  2880
MediaType:          db  0xf8
SectorPerFAT:       dw  9
SectorPerTrack:     dw  18
NumberOfHeads:      dw  2
DriveNumber:        db  0

; data section
_CurSector:          db  0x00
_CurHead:            db  0x00
_CurTrack:           db  0x00

FATSize:            dw  0x0000
FATDataSector:      dw  0x0000
RootDirSize:        dw  0xe
LoaderName:         db  "Loader  bin"
LoaderCluster:      dw  0x0000
LoaderNotFoundMsg:  db  "FATAL: Missing Loader Image", 0

TableLoadSegment:   dw  0x07c0
RootLoadOffset:     dw  0x0200

; arg -> pointer to null-terminated string
PRINT:
    push    bp
    mov     bp, sp
    push    bx
    mov     bx, [bp + 4]
.main:
    mov     al, [bx]
    or      al, al
    jz      .print_done
    mov     ah, 0x0e
    int     0x10
    inc     bx
    jmp     .main
.print_done:
    leave
    ret 2

_LOAD_ROOT:
    xchg    bx, bx
    push    bp
    mov     bp, sp
    push    bx
    push    dx

    ; skip reserved sector count
    mov     ax, word [ReservedSectorsCnt]
    xor     dx, dx
    ; skip FATs
    movzx   bx, byte [FatNumber]
    imul    bx, word [SectorPerFAT]
    add     ax, bx
    ; convert LBA to CHS
    push    ax
    call    _SET_CHS
    push    word [RootDirSize]  ; number of sectors to load
    push    word [RootLoadOffset]
    push    word [TableLoadSegment]
    call    _LOAD_SECTORS
    cmp     al, byte [RootDirSize]
    je      .success
.error:
    xor     ax, ax
.success:
    pop     dx
    pop     bx
    leave
    ret

_LOAD_SECTORS:
    push    bp
    mov     bp, sp
    push    bx
    push    cx
    push    dx

    mov     ah, 0x2 ; function 0x2
    mov     al, byte [bp + 0x8] ; amount
    mov     ch, byte [_CurTrack]
    mov     cl, byte [_CurSector]
    mov     dh, byte [_CurHead]
    mov     dl, byte [DriveNumber]
    push    es
    mov     bx, word [bp + 4]
    mov     es, bx
    mov     bx, word [bp + 6]
    int     0x13
    pop     es
    jc      .error
    movzx   ax, al
    jmp     .success
.error:
    xor     ax, ax
.success:
    pop     dx
    pop     cx
    pop     bx
    leave
    ret 6

_SET_CHS:
    push    bp
    mov     bp, sp
    push    dx
    mov     ax, word [bp + 4]
    xor     dx, dx
    div     word [SectorPerTrack]
    inc     dl
    mov     byte [_CurSector], dl
    xchg    bx, bx
    mov     bx, [NumberOfHeads]
    div     bx
    mov     byte [_CurHead], dl
    mov     byte [_CurTrack], al
    pop     dx
    leave
    ret 2

LOADER_MAIN:
    cli
    ; set segment to loc 0000:7c00
    mov     ax, 0x07c0
    mov     ds, ax
    mov     es, ax
    mov     fs, ax
    mov     gs, ax
    ; set up stack
    mov     ax, 0x0000
    mov     ss, ax
    mov     sp, 0xffff
    sti
    call _LOAD_ROOT
.fail:
    push    LoaderNotFoundMsg
    call    PRINT
    mov     ah, 0x00
    int     0x16
    int     0x19

times 510 - ($ - $$) db 0
dw  0xaa55