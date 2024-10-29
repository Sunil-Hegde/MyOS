#include<stdio.h>
#include<stdint.h>
#include<stdlib.h>
#include<string.h>
#include<ctype.h>

typedef uint8_t bool;
#define true 1
#define false 0

// Bootsector Structure
typedef struct{
    uint8_t bootJumpInstruction[3];
    uint8_t oemIdentifier[8];
    uint16_t bytesPerSector;
    uint8_t sectorsPerCluster;
    uint16_t reservedSectors;
    uint8_t fatCount;
    uint16_t dirEntriesCount;
    uint16_t totalSectors;
    uint8_t mediaDescriptorType;
    uint16_t sectorsPerFat;
    uint16_t sectorsPerTrack;
    uint16_t heads;
    uint32_t hiddenSectors;
    uint32_t largeSectorCount;

    // Extended boot record
    uint8_t driveNumber;
    uint8_t reserved;
    uint8_t signature;
    uint32_t volumeID;
    uint8_t volumelabel[11];
    uint8_t systemID[8];
} __attribute__((packed)) BootSector;

// Director Entry Structure
typedef struct{
    uint8_t Name[11];
    uint8_t attributes;
    uint8_t reserved;
    uint8_t createdTimeTenths;
    uint16_t createdTime;
    uint16_t createdDate;
    uint16_t accessedDate;
    uint16_t firstClusterHigh;
    uint16_t modifiedTime;
    uint16_t modifiedDate;
    uint16_t firstClusterLow;
    uint32_t size;

} __attribute__((packed)) DirectoryEntry;

// Global Variables
BootSector g_BootSector; // Holds boot sector data
uint8_t* g_Fat = NULL; // Stores the File Allocation Table
DirectoryEntry* g_RootDirectory = NULL; // Points to the root directory contents
uint32_t g_RootDirectoryEnd; // Marks the end of the root directory’s location on disk

//Reads the boot sector from the disk image
bool readBootSector(FILE* disk){
    return fread(&g_BootSector, sizeof(g_BootSector), 1, disk) > 0;
}

//Reads count sectors starting from lba (logical block address) into bufferOut
bool readSectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut){
    bool ok = true;
    ok = ok && (fseek(disk, lba * g_BootSector.bytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, g_BootSector.bytesPerSector, count, disk)==count);
    return ok;
}

// Allocates memory for g_Fat and loads the FAT table from the disk
bool readFat(FILE* disk){
    g_Fat = (uint8_t*)malloc(g_BootSector.sectorsPerFat * g_BootSector.bytesPerSector);
    return readSectors(disk, g_BootSector.reservedSectors, g_BootSector.sectorsPerFat, g_Fat);
}

// Reads the root directory into g_RootDirectory. 
// Calculates the root directory's starting sector and size, 
// and stores the data into g_RootDirectory
bool readRootDirectory(FILE* disk){
    uint32_t lba = g_BootSector.reservedSectors + g_BootSector.sectorsPerFat * g_BootSector.fatCount;
    uint32_t size = sizeof(DirectoryEntry) * g_BootSector.dirEntriesCount;
    uint32_t sectors = (size / g_BootSector.bytesPerSector);
    if(size % g_BootSector.bytesPerSector > 0){
        sectors++;
    }
    g_RootDirectoryEnd = lba + sectors;
    g_RootDirectory = (DirectoryEntry*)malloc(sectors * g_BootSector.bytesPerSector);
    return readSectors(disk, lba, sectors, g_RootDirectory);
}

// Searches for a file by name within the root directory
DirectoryEntry* findFile(const char* name){
    for(uint32_t i = 0; i < g_BootSector.dirEntriesCount; i++){
        if (memcmp(name, g_RootDirectory[i].Name, 11) == 0){
            return &g_RootDirectory[i];
        }
    }
    return NULL; 
}

//Reads the file’s contents from disk based on the cluster chain found in the FAT
bool readFile(DirectoryEntry* fileEntry, FILE* disk, uint8_t* outputBuffer){
    bool ok = true;
    uint16_t currentCluster = fileEntry->firstClusterLow;
    do{
        uint32_t lba = g_RootDirectoryEnd + (currentCluster - 2) * g_BootSector.sectorsPerCluster;
        ok = ok && readSectors(disk, lba, g_BootSector.sectorsPerCluster, outputBuffer);
        outputBuffer += g_BootSector.sectorsPerCluster * g_BootSector.bytesPerSector;

        uint32_t fatIndex = currentCluster * 3/2;
        if (currentCluster % 2 == 0){
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) & 0x0fff;
        } else {
            currentCluster = (*(uint16_t*)(g_Fat + fatIndex)) >> 4;
        }
    } while(ok && currentCluster < 0x0ff8);
    return ok;
}

int main(int argc, char **argv){
    if(argc < 3){
        printf("Syntax: %s <disk_image> <file_name>\n", argv[0]);
        return -1;
    }
    FILE* disk = fopen(argv[1], "rb"); // Initialise disk image, and read binary
    if(!disk){
        fprintf(stderr, "Cannot open disk image %s!\n", argv[1]);
        return -1;
    }

    if(!readBootSector(disk)){
        fprintf(stderr, "Could not read bootsector!\n");
        return -2;
    }

    if(!readFat(disk)){
        fprintf(stderr, "Could not read FAT!\n");
        free(g_Fat);
        return -3;
    }

    if(!readRootDirectory(disk)){
        fprintf(stderr, "Could not read Root Directory!\n");
        free(g_Fat);
        free(g_RootDirectory);
        return -4;
    }

    DirectoryEntry* fileEntry = findFile(argv[2]); // Find required file
    if(!fileEntry){
        fprintf(stderr, "Could not find file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        return -5;
    }

    uint8_t* buffer = (uint8_t*)malloc(fileEntry->size + g_BootSector.bytesPerSector);
    if (!readFile(fileEntry, disk, buffer)){
        fprintf(stderr, "Could not read file %s!\n", argv[2]);
        free(g_Fat);
        free(g_RootDirectory);
        free(buffer);
        return -5;
    }

    for(size_t i = 0; i < fileEntry->size; i++){
        if(isprint(buffer[i])) fputc(buffer[i], stdout);
        else printf("<%02x>", buffer[i]);
    }
    
    printf("\n");
    free(buffer);
    free(g_Fat);
    free(g_RootDirectory);
    return 0;
}

