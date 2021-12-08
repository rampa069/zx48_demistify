#include "diskimg.h"

const char *bootvhd_name="ZX48    VHD";
const char *bootrom_name="ZX48    ROM";

char *autoboot()
{
        char *result=0;
        diskimg_mount(bootvhd_name,0);
        LoadROM(bootrom_name);
        return(result);
}
