################################################################################
# zsh config for macos
################################################################################

################################################################################
# individual app config
################################################################################

# arm build tools
ARM_TOOLCHAIN_DIR="$HOME/Applications/ArmGNUToolchain/14.3.rel1/arm-none-eabi/bin"
if [ -d "$ARM_TOOLCHAIN_DIR" ]; then
    export PATH="$ARM_TOOLCHAIN_DIR:$PATH"
fi
