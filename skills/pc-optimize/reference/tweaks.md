# Tweaks: safe / depends / not recommended (Windows 11 24H2-26H2, desktop)

## Safe & recommended (measurable)
| Item | Why |
|---|---|
| Max refresh rate on the monitor | Frame interval 16.7 ms (60 Hz) -> 4.2 ms (240 Hz) |
| XMP/EXPO (then stress-test RAM) | Higher FPS and 1% lows in CPU-bound games |
| Vendor chipset INF / Serial IO / MEI / LAN drivers | Removes Code 28 devices, fixes DPC spikes and old inbox drivers |
| Current GPU driver (clean, INF-based for NVIDIA if scripted) | Fixes, Reflex support, lower DPC spikes |
| GPU in the CPU-attached x16 slot | Full PCIe bandwidth, no DMI sharing |
| Mouse acceleration off; mouse polling 1000 Hz | Consistent aim; 125 Hz adds up to 8 ms |
| NVIDIA Reflex On (+Boost) in supporting games | Largest in-game latency reduction |
| NVIDIA Low Latency Mode On (max pre-rendered frames 1) for non-Reflex games | Smaller render queue |
| Windows "Optimizations for windowed games" | Flip model for DX10/11 borderless = fullscreen-like latency |
| G-SYNC/FreeSync + V-Sync in driver + FPS cap ~3% below refresh (if the user wants VRR) | Tear-free with near-zero added latency |
| Keep Game Mode + HAGS on (defaults) | Neutral to positive; HAGS needed for frame generation |
| Unplug the install USB, uninstall driver updaters/boosters | Fewer background services, no non-vendor drivers |

## Depends on use case
| Item | Trade-off |
|---|---|
| High performance / Ultimate power plan | Tiny latency gain on some CPUs, more idle power. Measure with Measure-Dpc first |
| Uncapped FPS without VRR (competitive) | Lowest latency, but tearing |
| Disable VBS/Memory Integrity | 0-5% FPS in some games vs. real kernel-attack protection. Only on explicit request |
| Disable Fast Startup | Cleaner boots/driver state, slightly slower cold boot |
| Disable unused onboard devices in BIOS (audio, extra LAN) | Removes a driver; only if truly unused |
| Intel Platform License Manager / vendor helper services -> Manual | Cosmetic boot-time win |

## Not recommended (placebo or harmful)
| Tweak | Reason |
|---|---|
| Debloat scripts / tweak packs | Break Store, Windows Update, features; not reversible |
| Driver updaters (Driver Easy, Booster) | Non-vendor drivers, wrong versions |
| bcdedit useplatformclock / disabledynamictick / tscsyncpolicy | Usually worse timer behaviour on modern CPUs |
| Disabling HPET in Device Manager | No benefit on Win10/11 |
| "Timer resolution" tools | Windows 11 handles per-process timer resolution |
| Network "gaming" registry tweaks (TcpAckFrequency, NetworkThrottlingIndex) | No measurable effect on modern stacks |
| Disabling CPU C-states globally / Core Isolation as "FPS boost" | More heat/power, little or no gain, less security |
| Disabling fullscreen optimizations globally | Flip-model borderless already matches exclusive fullscreen |
| Prefer maximum performance (NVIDIA power) globally | Higher idle power; no latency gain with modern boost |
| Disabling Defender / Windows Update for "performance" | Security risk; negligible gain |
| Third-party antivirus "game modes" | Defender is sufficient and has lowest overhead |
