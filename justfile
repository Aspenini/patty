set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

# Show available recipes.
default:
    @just --list

# Install Crystal dependencies.
setup:
    shards install

# Run the complete test suite.
test:
    crystal spec

# Build optimized Patty binaries and compress supported platforms with UPX.
[windows]
build:
    New-Item -ItemType Directory -Force bin | Out-Null
    llvm-rc /FObin/patty.res windows/patty.rc
    $res = (Resolve-Path bin/patty.res).Path; crystal build src/patty.cr --release --no-debug -o bin/patty.exe --link-flags $res
    $res = (Resolve-Path bin/patty.res).Path; crystal build src/patty.cr --release --no-debug -D windows_gui -o bin/pattyw.exe --link-flags "$res /SUBSYSTEM:WINDOWS"
    upx --best --lzma bin/patty.exe bin/pattyw.exe
    $crystalDir = Split-Path (Get-Command crystal).Source; @("gc.dll", "iconv-2.dll", "libcrypto-3-x64.dll", "libssl-3-x64.dll", "pcre2-8.dll", "yaml.dll", "zlib1.dll") | ForEach-Object { Copy-Item (Join-Path $crystalDir $_) bin -Force }
    Remove-Item bin/patty.res

[linux]
build:
    shards build --release --no-debug
    command -v upx >/dev/null || { echo "UPX is required for Linux builds."; exit 1; }
    upx --best --lzma bin/patty

[macos]
build:
    shards build --release --no-debug

# Compile and run Patty directly from source.
dev:
    crystal run src/patty.cr -- run

# Build and run Patty.
[windows]
run: build
    bin/pattyw.exe

[unix]
run: build
    ./bin/patty run

# Remove build output and installed project dependencies.
[windows]
clean:
    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "$PWD\bin\*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Start-Sleep -Milliseconds 200
    @("bin", "dist", "lib", ".shards") | Where-Object { Test-Path $_ } | ForEach-Object { Remove-Item -LiteralPath $_ -Recurse -Force }

[unix]
clean:
    rm -rf bin dist lib .shards

alias b := build
alias r := run
alias t := test
