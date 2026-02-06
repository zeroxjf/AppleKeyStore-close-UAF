# AppleKeyStoreUserClient close() UAF

By [@zeroxjf](https://x.com/zeroxjf)

**This will kernel panic your device. Save your work.**

Tested on iOS 26.2.1 (23C71). Patched in iOS 26.3 RC (23D125).

## Trigger

`IOServiceClose` calls `terminate()` synchronously but keeps the Mach port alive. The workloop then runs `close()` asynchronously, freeing the gate. Meanwhile, racer threads flood `IOConnectCallMethod` through the still-alive port — their `externalMethod()` calls dereference the freed gate on separate MIG threads.

```
Racers (32 threads):                Trigger:
  IOConnectCallMethod(conn, 10)     IOServiceClose(conn)
  IOConnectCallMethod(conn, 10)       -> terminate() [sync]
  IOConnectCallMethod(conn, 10)       -> returns to userland
    |
    | port still alive              Workloop (async):
    |                                 close() -> frees gate
    v                                 this+272 dangles
  externalMethod()
    -> *(this+272) -> FAULT         Finalization (later):
                                      port mapping removed
```

## Panic

```
panic(cpu 1 caller 0xfffffe00503c08e0): Kernel tag check fault
  (expected tagged address: 0xf6fffe205d518d88)
  at pc 0xfffffe00502c34e0, lr 0xfffffe00502c3418

Panicked task: pid 17598: UAFTester
Kernel Extensions in backtrace:
  com.apple.driver.AppleSEPKeyStore(2.0)
```

## Build & Run

1. Open `PoC/UAFTester.xcodeproj` in Xcode
2. Select your iOS device (requires iOS <26.3 RC)
3. Build and run
4. Tap the button
