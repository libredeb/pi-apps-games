get_debian_arch() {
    local raw_arch=$(uname -m)

    case "$raw_arch" in
        x86_64)        echo "amd64" ;;
        i386|i686)     echo "i386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf)  echo "armhf" ;;
        armv6l|armel)  echo "armel" ;;
        powerpc64le)   echo "ppc64el" ;;
        riscv64)       echo "riscv64" ;;
        s390x)         echo "s390x" ;;
        *) 
            if command -v dpkg >/dev/null 2>&1; then
                dpkg --print-architecture
            else
                echo "unknown"
                return 1
            fi
            ;;
    esac
}