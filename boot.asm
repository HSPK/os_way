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

LoaderName:         db  "DEMONWAYTXT"
LoaderNotFoundMsg:  db  "ERR", 0
RootDirSize         equ  0xe
LoaderSegment       equ  0x0050
TableLoadSegment    equ  0x07c0
FATLoadOffset       equ  0x0200
RootLoadOffset      equ  0x0200

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
    ; skip reserved sector count
    ; mov     ax, [ReservedSectorsCnt]
    ; xor     dx, dx
    ; ; skip FATs
    ; movzx   bx, byte [FatNumber]
    ; imul    bx, word [SectorPerFAT]
    ; add     ax, bx
    mov     ax, 19
    ; convert LBA to CHS
    push    ax
    call    _SET_CHS
    push    RootDirSize              ; number of sectors to load
    push    RootLoadOffset
    push    TableLoadSegment
    call    _LOAD_SECTORS
    cmp     al, RootDirSize
    je      .success
.error:
    xor     ax, ax
.success:
    ret

; load sectors to CHS position
; arg0 -> segment
; arg1 -> offset
; arg2 -> amount
_LOAD_SECTORS:
    push    bp
    mov     bp, sp
    push    bx
    push    cx
    push    dx
    push    es

    mov     ah, 0x2                 ; function 0x2
    mov     al, byte [bp + 0x8]     ; amount
    mov     ch, byte [_CurTrack]
    mov     cl, byte [_CurSector]
    mov     dh, byte [_CurHead]
    mov     dl, byte [DriveNumber]
    mov     bx, word [bp + 4]
    mov     es, bx
    mov     bx, word [bp + 6]
    int     0x13
    jc      .error
    movzx   ax, al
    jmp     .success
.error:
    xor     ax, ax
.success:
    pop     es
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
    xor     dx, dx
    div     word [NumberOfHeads]
    mov     byte [_CurHead], dl
    mov     byte [_CurTrack], al
    pop     dx
    leave
    ret 2

_FIND_FILE:
    push    bp
    mov     bp, sp
    push    cx
    push    di
    mov     cx, [RootDirEntries]
    mov     di, RootLoadOffset
.loop:
    push    cx
    mov     cx, 11
    push    di
    mov     si, [bp + 4]
    rep     cmpsb
    pop     di
    je      .found
    pop     cx
    add     di, 32
    loop    .loop
.not_found:
    xor     ax, ax
    jmp     .return
.found:
    mov     ax, word [di + 0x1a]
.return:
    pop     di
    pop     cx
    leave
    ret 2

_LOAD_FATS:
    push    word [ReservedSectorsCnt]
    call    _SET_CHS
    push    word [SectorPerFAT]
    push    FATLoadOffset
    push    TableLoadSegment
    call    _LOAD_SECTORS
    cmp     ax, word [SectorPerFAT]
    je      .success
.error:
    xor     ax, ax
.success:
    ret

; get FAT table entry value by cluster id
; arg -> cluster id
; FAT addr = FAT_BASE_Addr + CN / 2 * 3, if CN is even
;            FAT_BASE_Addr + CN / 2 * 3 + 1, if CN is odd
_GET_FAT_ENTRY:
    push    bp
    mov     bp, sp
    push    di
    mov     di, [bp + 4]
    mov     ax, di
    shr     di, 1               ; CN / 2
    add     di, ax              ; (CN / 2) * 3 + 1
    add     di, FATLoadOffset
    and     ax, 0x1
    mov     ax, [di]
    jz      .even
    shr     ax, 4
    jmp     .return
.even:
    and     ax, 0x0fff
.return:
    pop     di
    leave
    ret 2

; load file clusters using FAT index
; arg0 -> file FAT index
; arg1 -> segment
; arg2 -> offset
; return -> #sectors loaded
_LOAD_FILE:
    push    bp
    mov     bp, sp
    push    cx
    push    dx
    push    si
    push    di
    xor     bx, bx
    xor     cx, cx
    mov     dx, word [bp + 4]
.loop_main:
    push    dx
    call    _GET_FAT_ENTRY
    mov     si, ax
    inc     cx
    jno     .no_overflow
    inc     bx
.no_overflow:
    add     dx, 31      ; CN to LSN
    push    dx
    call    _SET_CHS    ; LSN to CHS
    push    word [SectorsPerCluster]
    push    word [bp + 8]
    push    word [bp + 6]
    call    _LOAD_SECTORS
    test    ax, ax
    jz      .error
    cmp     si, 0xff8
    jae     .return
    cmp     si, 0xff0
    jae      .error
    cmp     si, 0x00
    jz      .error
    mov     dx, si
    mov     di, word [BytesPerSector]
    add     word [bp + 8], di
    jnc     .loop_main
    add     word [bp + 6], 0x1000
    jmp     .loop_main  
.error:
    xor     bx, bx
    xor     cx, cx
.return:
    mov     ax, cx
    pop     di
    pop     si
    pop     dx
    pop     cx
    leave
    ret 6

; arg0 -> filename
; arg1 -> segment
; arg2 -> offset
; return -> file size in ax/bx, or 0 if not found/error
LOAD_FILE:
    push    bp
    mov     bp, sp
    push    si

    ; load root dir
    call    _LOAD_ROOT
    or      ax, ax
    je      .error

    ; get file's FAT index
    push    word [bp + 4]
    call    _FIND_FILE
    test    ax, ax
    je      .error
    mov     si, ax

    ; load FAT
    call    _LOAD_FATS
    or      ax, ax
    je      .error

    ; load actual file
    push    word [bp + 8]
    push    word [bp + 6]
    push    si
    call    _LOAD_FILE
    or      ax, ax
    jne     .success
    or      bx, bx
    jne     .success

.error:
    xor     ax, ax
    xor     bx, bx
.success:
    pop     si
    leave
    ret 6

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
    push    0x0000
    push    LoaderSegment
    push    LoaderName
    call    LOAD_FILE
    xchg    bx, bx
    test    ax, ax
    jz      .fail

    push    LoaderSegment     ; jump to loader
    push    0x0000
    retf

.fail:
    push    LoaderNotFoundMsg
    call    PRINT
.return:
    mov     ah, 0x00
    int     0x16
    int     0x19

times 510 - ($ - $$) db 0
dw  0xaa55