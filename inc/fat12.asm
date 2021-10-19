; fat12 dirver

BytesPerSector:     dw  512
SectorsPerCluster:  db  1
ReservedSectorsCnt: dw  1
FatNumber:          db  2
RootDirEntries:     dw  0xe0
RootDirSize:        dw  0xe
SectorNumber:       dw  2880
SectorPerFAT:       dw  9
SectorPerTrack:     dw  18
NumberOfHeads:      dw  2
LastClusterVal:     dw  0xff8
DriveNumber:        db  0

TableLoadSegment:   dw 0x9800
RootLoadOffset:     dw 0x0
FATLoadOffset:      dw 0x1c00

; LBA 向 CHS转换时使用
_CurHead:           db 0
_CurTrack:          db 0
_CurSector:         db 0

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
    cmp     ax, -1
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


_LOAD_ROOT:
    push    bp
    mov     bp, sp
    push    bx
    push    dx

    ; skip reserved sector count
    mov     ax, 1
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
    mov     ch, word [_CurTrack]
    mov     cl, word [_CurSector]
    mov     dh, word [_CurHead]
    mov     dl, word [DriveNumber]
    push    es
    mov     es, byte [bp + 4]
    mov     bx, byte [bp + 6]
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
    push    ax
    push    bx
    mov     bx, word [bp + 4]

    ; calc head
    xor     dx, dx
    mov     ax, bx
    div     word [SectorPerTrack]
    xor     dx, dx
    div     word [NumberOfHeads]
    mov     word [_CurHead], dx
    ; calc track
    push    cx
    mov     ax, word [SectorPerTrack]
    mul     word [NumberOfHeads]
    mov     cx, ax
    xor     dx, dx
    mov     ax, bx
    div     cx
    mov     word [_CurTrack], ax
    pop     cx

    ; calc sectors
    mov     ax, bx
    xor     dx, dx
    div     word [SectorPerTrack]
    inc     dx
    mov     word [_CurSector], dx
    pop     bx
    pop     ax
    leave
    ret 2