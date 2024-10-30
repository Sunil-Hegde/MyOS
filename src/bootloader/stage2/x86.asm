bits 16

section _TEXT class=CODE

global _x86_Video_WriteCharTeletype
_x86_Video_WriteCharTeletype:
    ; Make new call frame
    push bp             ; Save old call frame
    mov bp, sp          ; Initialise new call frame

    ; Save bx
    push bx

    mov ah, 0eh
    mov al, [bp + 4]
    mov bh, [bp + 6]

    int 10h

    pop bx

    mov sp, bp
    pop bp
    ret