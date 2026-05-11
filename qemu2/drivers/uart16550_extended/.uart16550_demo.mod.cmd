savedcmd_uart16550_demo.mod := printf '%s\n'   uart16550_demo.o | awk '!x[$$0]++ { print("./"$$0) }' > uart16550_demo.mod
