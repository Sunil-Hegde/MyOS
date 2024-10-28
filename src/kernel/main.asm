org 0x7C00
bits 16
%define ENDL 0x0D, 0x0A

start: 
    jmp main

; Printing a string on the screen
; ds:si points to string
puts:
    ; Saving registers that we will modify
    push si
    push ax

.loop:
    lodsb                   ; Load the byte at DS:SI into AL and increment SI
    or al, al               ; Check if AL is zero (end of string)
    jz .done
    mov ah, 0x0e            ; BIOS teletype function
    int 0x10                ; BIOS interrupt to print character in AL
    jmp .loop               ; Repeat for the next character

.done:
    pop ax
    pop si
    ret

main:
    ; Setting-up data segments
    mov ax, 0
    mov ds, ax
    mov es, ax
    ; Setting-up stack segment
    mov ss, ax
    mov sp, 0x7C00
    mov si, msg_hello
    call puts
    hlt

.halt:
    jmp .halt

msg_hello: db 'Hello world!', ENDL, 0

times 510-($-$$) db 0
dw 0xAA55
