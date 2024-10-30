org 0x7C00             ; Set origin address to 0x7C00, the standard memory location for the bootloader
bits 16                ; 16-bit mode (real mode)

%define ENDL 0x0D, 0x0A ; Define line ending for strings (carriage return + newline)

jmp short start         ; Jump to start of the bootloader code
nop                     ; No operation (padding for alignment)

; Boot Sector
bdb_oem:                    db 'MSWIN4.1'            ; OEM Name
bdb_bytes_per_sector:       dw 512                   ; Bytes per sector
bdb_sectors_per_cluster:    db 1                     ; Sectors per cluster
bdb_reserved_sectors:       dw 1                     ; Number of reserved sectors
bdb_fat_count:              db 2                     ; Number of FAT tables
bdb_dir_entries_count:      dw 0E0h                  ; Max number of root directory entries
bdb_total_sectors:          dw 2880                  ; Total sector count for 1.44 MB floppy
bdb_media_descriptor_type:  db 0F0h                  ; Media descriptor byte
bdb_sectors_per_fat:        dw 9                     ; Sectors per FAT
bdb_sectors_per_track:      dw 18                    ; Sectors per track (18 for floppy)
bdb_heads:                  dw 2                     ; Number of heads (2 for floppy)
bdb_hidden_sectors:         dd 0                     ; Hidden sectors (not used for floppy)
bdb_large_sector_count:     dd 0                     ; Large sector count (unused here)

; Extended Boot Record
ebr_drive_number:           db 0                    ; Drive number (usually 0)
                            db 0                    ; Reserved byte
ebr_signature:              db 29h                  ; Extended boot record signature
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; Volume ID (randomly generated)
ebr_volume_label:           db 'NANOBYTE OS'        ; Volume label
ebr_system_id:              db 'FAT12   '           ; File system type

; Program entry point
start:
    mov ax, 0               ; Initialize data segment and extra segment
    mov ds, ax
    mov es, ax
    mov ss, ax              ; Initialize stack segment and pointer
    mov sp, 0x7C00
    push es
    push word .after        ; Call far jump to .after
    retf

.after:
    mov [ebr_drive_number], dl  ; Store boot drive number in ebr_drive_number
    ; Display loading message
    mov si, msg_loading
    call puts

    push es
    mov ah, 08h
    int 13h                ; BIOS interrupt to get disk parameters
    jc floppy_error        ; If carry flag set, jump to floppy error handler
    pop es

    ; Get sectors per track and number of heads
    and cl, 0x3f
    xor ch, ch
    mov [bdb_sectors_per_track], cx
    inc dh
    mov [bdb_heads], dh

    ; Calculate FAT area start
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax

    ; Calculate root directory size in sectors
    mov ax, [bdb_dir_entries_count]
    shl ax, 5
    xor dx, dx
    div word [bdb_bytes_per_sector]
    test dx, dx
    jz .root_dir_after
    inc ax

.root_dir_after:
    mov cl, al
    pop ax
    mov dl, [ebr_drive_number]
    mov bx, buffer
    call disk_read
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, file_kernel_bin
    mov cx, 11
    push di
    repe cmpsb                ; Compare string for filename match
    pop di
    je .found_kernel          ; Jump if kernel file found
    add di, 32                ; Move to next directory entry
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel         ; Loop until all entries are checked
    jmp kernel_not_found_error

.found_kernel:
    ; Load starting cluster of kernel
    mov ax, [di + 26]
    mov [kernel_cluster], ax

    ; Read FAT into buffer
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; Set up kernel load address
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    ; Read kernel sectors cluster by cluster
    mov ax, [kernel_cluster]
    add ax, 31
    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read
    add bx, [bdb_bytes_per_sector]

    ; Read next cluster number
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx
    mov si, buffer
    add si, ax
    mov ax, [ds:si]
    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0fff

.next_cluster_after:
    cmp ax, 0x0ff8
    jae .read_finish
    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    ; Final jump to loaded kernel
    mov dl, [ebr_drive_number]
    mov ax, KERNEL_LOAD_SEGMENT
    mov ds, ax
    mov es, ax
    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET
    jmp wait_key_and_reboot  ; Reboot on error

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found_error:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h               ; Wait for key press
    jmp 0FFFFh:0          ; Reboot by jumping to BIOS

puts:
    push si
    push ax
    push bx

.loop:
    lodsb                  ; Load byte from string into AL
    or al, al
    jz .done               ; End of string
    mov ah, 0x0E           ; BIOS teletype function for printing
    mov bh, 0
    int 0x10
    jmp .loop

.done:
    pop bx
    pop ax
    pop si    
    ret

; Converts LBA to CHS address
lba_to_chs:
    push ax
    push dx
    xor dx, dx
    div word [bdb_sectors_per_track]
    inc dx
    mov cx, dx
    xor dx, dx
    div word [bdb_heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah
    pop ax
    mov dl, al
    pop ax
    ret

disk_read:
    ; Reads sector from disk using LBA to CHS
    push ax
    push bx
    push cx
    push dx
    push cx
    call lba_to_chs
    pop ax
    mov ah, 02h
    mov di, 3

.retry:
    pusha
    stc
    int 13h
    jnc .done              ; Success if carry flag not set
    popa
    call disk_reset
    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.done:
    popa
    pop dx
    pop cx
    pop bx
    pop ax
    ret

disk_reset:
    ; Resets the disk drive
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

msg_read_failed:        db 'Read from disk failed!', ENDL, 0
msg_loading:            db 'Loading...', ENDL, 0
msg_kernel_not_found:   db 'STAGE2.BIN file not found!', ENDL, 0
file_kernel_bin:        db 'STAGE2  BIN'
kernel_cluster:         dw 0

KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0

times 510-($-$$) db 0    ; Fill remaining bytes with 0s to make it 512 bytes
dw 0xAA55                ; Boot sector signature

buffer:                  ; Buffer for disk reads
