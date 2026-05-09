#include "qemu/osdep.h"
#include "hw/core/boards.h"
#include "hw/arm/machines-qom.h"
#include "hw/core/qdev.h"
#include "hw/core/sysbus.h"
#include "system/address-spaces.h"
#include "system/memory.h"
#include "qapi/error.h"

#define UARTARM_RAM_BASE   0x80000000ULL
#define UARTARM_RAM_SIZE   (128 * 1024 * 1024ULL)

#define UARTARM_UART_BASE  0xff210000ULL
#define UARTARM_UART_SIZE  0x1000

static MemoryRegion uartarm_ram;

static void uartarm_soc_init(MachineState *machine)
{
    DeviceState *dev;
    SysBusDevice *sbd;

    printf("uartarm_soc_init called\n");

    memory_region_init_ram(&uartarm_ram, NULL, "uartarm.ram",
                           UARTARM_RAM_SIZE, &error_fatal);

    memory_region_add_subregion(get_system_memory(),
                                UARTARM_RAM_BASE, &uartarm_ram);

    printf("RAM mapped at 0x%08llx, size = %llu MB\n",
           (unsigned long long)UARTARM_RAM_BASE,
           (unsigned long long)(UARTARM_RAM_SIZE / (1024 * 1024)));

    dev = qdev_new("uart-stub");
    sbd = SYS_BUS_DEVICE(dev);

    sysbus_realize_and_unref(sbd, &error_fatal);
    sysbus_mmio_map(sbd, 0, UARTARM_UART_BASE);

    printf("UART stub mapped at 0x%08llx, size = 0x%llx\n",
           (unsigned long long)UARTARM_UART_BASE,
           (unsigned long long)UARTARM_UART_SIZE);
}

static void uartarm_soc_machine_init(MachineClass *mc)
{
    mc->desc = "Minimal ARM SoC for UART verification";
    mc->init = uartarm_soc_init;
    mc->max_cpus = 1;
}

DEFINE_MACHINE_ARM("uartarm-soc", uartarm_soc_machine_init)
