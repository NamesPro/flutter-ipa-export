// injector.m
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <libproc.h>

int find_pattern_in_memory(int pid, const unsigned char* pattern, int patternLen, uint64_t** results, int* count) {
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"Failed to get task for PID %d", pid);
        return -1;
    }
    
    mach_vm_address_t address = 0;
    mach_vm_size_t size = 0;
    vm_region_basic_info_data_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
    mach_port_t object_name;
    
    uint64_t* found = malloc(sizeof(uint64_t) * 1000);
    int foundCount = 0;
    
    while (mach_vm_region(task, &address, &size, VM_REGION_BASIC_INFO,
                         (vm_region_info_t)&info, &info_count,
                         &object_name) == KERN_SUCCESS) {
        
        if (info.protection & VM_PROT_WRITE) {
            mach_vm_address_t curAddr = address;
            while (curAddr < address + size) {
                uint8_t buffer[4096];
                mach_vm_size_t bytesRead;
                kr = mach_vm_read_overwrite(task, curAddr, sizeof(buffer),
                                           (vm_address_t)buffer, &bytesRead);
                if (kr != KERN_SUCCESS) break;
                
                for (int i = 0; i <= bytesRead - patternLen; i++) {
                    if (memcmp(buffer + i, pattern, patternLen) == 0) {
                        uint32_t value;
                        mach_vm_size_t readBytes;
                        kr = mach_vm_read_overwrite(task, curAddr + i, 4,
                                                   (vm_address_t)&value, &readBytes);
                        if (kr == KERN_SUCCESS && readBytes == 4) {
                            uint32_t expectedID = *(uint32_t*)pattern;
                            if (value == expectedID) {
                                found[foundCount++] = curAddr + i;
                                if (foundCount >= 1000) break;
                            }
                        }
                    }
                }
                curAddr += bytesRead;
            }
        }
        
        address += size;
        size = 0;
        info_count = VM_REGION_BASIC_INFO_COUNT;
    }
    
    *results = found;
    *count = foundCount;
    return 0;
}

int write_memory(int pid, uint64_t address, const unsigned char* data, int dataLen) {
    task_t task;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    kr = mach_vm_write(task, address, (vm_address_t)data, dataLen);
    if (kr != KERN_SUCCESS) {
        return -2;
    }
    
    return 0;
}
