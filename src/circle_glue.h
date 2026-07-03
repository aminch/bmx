#ifndef _bmc64_circle_glue_h
#define _bmc64_circle_glue_h

#include <circle/serial.h>

class CNetSubSystem;

#define MAX_BOOTSTAT_LINES 32
#define MAX_BOOTSTAT_FLEN 64

#define BOOTSTAT_WHAT_STAT 0
#define BOOTSTAT_WHAT_FAIL 1

void CGlueStdioInit(CSerialDevice *serial);

void CGlueStdioInitBootStat(int num,
                            int *bootStatWhat,
                            const char **bootStatFile,
                            int *bootStatSize);

void CGlueNetworkInit(CNetSubSystem &network);

#endif
