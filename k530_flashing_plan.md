# Redragon K530 Draconic PRO Automated Bring-up and Recovery Plan

## Current decision: NO-GO

Do not upload custom firmware yet. The first deliverable is an automated,
tested stock-recovery path. Custom firmware remains blocked until that recovery
path works using only normal USB operations and keyboard actions available to a
non-technical operator.

This is an evidence-gated plan. A phase passes only when scripts can verify its
artifacts and results. An LLM may analyze firmware, generate code, interpret
logs, and guide testing, but safety-critical decisions must be enforced by
deterministic programs rather than natural-language judgment.

## Operator model

The human operator may:

- connect or disconnect the USB cable when prompted;
- set the keyboard's normal mode switches;
- hold or press named keys when prompted;
- confirm that LEDs or keys behave as requested; and
- type an explicit confirmation before an erase/write.

The process must not require the operator to:

- open the keyboard;
- identify PCB pads or chip pins;
- solder, probe voltages, or use a logic analyzer;
- use an external MCU programmer;
- construct firmware commands or choose flash addresses; or
- diagnose raw tool output.

All setup, USB identification, backup, hashing, disassembly, build, validation,
logging, recovery, and failure handling must be scripted.

## Hard safety boundary

Without an external programmer there is one unavoidable limitation:

> Software can restore the application only while the factory ISP bootloader is
> intact and can be entered without relying on working application firmware.

No LLM or Linux script can recover a damaged bootloader, damaged code options,
or electrically failed hardware when the device exposes no USB recovery mode.
The software-only plan therefore depends on all of the following:

1. The factory bootloader is never written.
2. Code options are never written.
3. The flashing tool is restricted to the 61,440-byte application region.
4. A keyboard-only factory-ISP entry sequence works after complete power
   removal, even when the application is assumed dead.
5. `recover_k530.sh` can restore and verify the captured stock application from
   that factory ISP state.

The official `sinowisp` implementation states that normal writes erase the
application but not the bootloader. It also states that reads can program the
enable-firmware opcode and that reset-vector bytes are logically redirected.
Those behaviors must be verified against the pinned local source and accounted
for in every backup and comparison:

https://github.com/carlossless/sinowisp

If item 4 cannot be demonstrated using only keyboard controls, this project is
not safely feasible under the operator model. Stop before the first
application erase rather than quietly weakening the requirement.

## Project goals

### Goal 1 - Automated stock recovery

Create `recover_k530.sh` at the repository root. Given a unit-specific,
hash-locked manifest, it must:

- identify the correct keyboard;
- guide the operator into factory ISP when needed;
- validate every tool and stock-image hash;
- restore only the stock application region;
- verify the write and independent read-back;
- reboot and run a guided stock behavior test; and
- produce a machine-readable recovery report.

Goal 1 is complete only after a controlled stock-to-stock restore succeeds from
both normal stock mode and the independent keyboard-only factory-ISP entry.

### Goal 2 - Recovery monitor

The first custom image is a minimal recovery monitor, not a keyboard firmware.
It must enumerate over USB, expose a recovery/status protocol, and jump into the
factory ISP bootloader. It must not scan keys, drive LEDs, use wireless, or
write persistent flash.

### Goal 3 - Configurable wired firmware

After recovery is proven, add wired matrix support, a bounded vendor-HID
configuration protocol, a Linux CLI, runtime key/layer remapping, read-back,
and interruption-safe persistent storage.

RGB, 2.4 GHz, Bluetooth, and a graphical configurator are later increments.

## Known local evidence

The following was observed in the current environment and must be re-verified
by the automated workflow:

| Item | Current observation |
| --- | --- |
| Normal USB identity | `258a:0049` |
| Reported MCU family | SH68F90A / BYK916 |
| Current tool | `sinowisp 2.0.0` at `/home/sridhar/.cargo/bin/sinowisp` |
| Current tool SHA-256 | `a42881403a319d5b90de2f1a8fe99657a4c5b7c941d9a980480d0b2c8029ce16` |
| Legacy tool | `sinowealth-kb-tool 1.0.1` at `/home/sridhar/.cargo/bin/sinowealth-kb-tool` |
| Legacy tool SHA-256 | `28eb68ac96e38977567ead6f536ad4b500584389237654792c8b729ef36b5fbe` |
| K530 device profile | Present in both installed tools |
| Listed K530 bootloader MD5 | `cfc8661da8c9d7e351b36c0a763426aa` |
| Listed application size | 61,440 bytes (`0x0000-0xEFFF`) |
| Listed bootloader size | 4,096 bytes (`0xF000-0xFFFF`) |

The K530 device profile is not strong identity evidence. Its normal VID/PID and
generic SH68F90 parameters are shared by several unrelated keyboards.

`sinowisp 2.0.0` is the provisional recovery implementation because its source
and separate flasher orchestration have been inspected. The legacy
`sinowealth-kb-tool` binary remains installed for current Meson compatibility,
but it must not be used for writes unless the plan explicitly switches the
pinned implementation and regenerates all tool hashes and tests.

## Repository risks to remove

1. `setup_sinowisp_k530.sh` installs a latest tool and immediately performs one
   application read. Do not run it in its current form.
2. Meson searches for `sinowealth-kb-tool` and creates flash targets using
   `--force`. Merely configuring a build therefore makes an unsafe command
   available. K530 work must remove or hard-disable that flash target before a
   K530 build target is added.
3. `sinowisp read` is not strictly passive. Version 2.0.0 sends
   `enable_firmware`, which may program `0xEFFB`.
4. The ISP redirects reset-target bytes between `0x0001-0x0002` and
   `0xEFFC-0xEFFD`. An ISP backup is the correct ISP restore payload but not a
   literal raw-flash image.
5. Default reads exclude the bootloader. Application, bootloader, and full
   forensic reads are separate artifacts.
6. SMK assumes code below `0xEC00`, settings at `0xEC00-0xEDFF`, reset redirect
   near `0xEFFB-0xEFFF`, and bootloader at `0xF000-0xFFFF`. The K530 stock image
   and bootloader must confirm those boundaries.
7. SMK has no dynamic-keymap protocol. Keymaps are currently compiled constants.
8. The existing persistent-settings record has a one-byte length and is not
   suitable for an arbitrary multi-layer keymap.

## Automation rules

- One top-level workflow owns the state. Ad hoc destructive commands are
  forbidden.
- Each phase writes a signed/hash-linked JSON result containing inputs, tool
  versions, command results, and the next permitted phase.
- A phase cannot be marked passed by an LLM response or operator assertion.
- The workflow is resumable after host crashes and rechecks every input hash.
- The operator receives one physical action at a time.
- Device writes always require an explicit typed confirmation.
- No script accepts arbitrary firmware paths, flash sizes, addresses, device
  profiles, or `--force`.
- Only one writable tool implementation is enabled in the recovery environment.
- A failure never triggers an automatic second erase/write.
- Logs must not contain unrelated environment variables or secrets.
- Stock binaries stay outside Git. Schemas, hashes, tests, and analysis may be
  committed.

## Private artifact directory

The workflow creates a unit-specific private directory:

```sh
export K530_WORKDIR="$HOME/k530-bringup/<unit-id>"
mkdir -p "$K530_WORKDIR"/{baseline,isp,analysis,logs,manifests,state}
chmod 700 "$K530_WORKDIR"
```

The `<unit-id>` is generated from stable available USB descriptors plus an
operator-visible label. It must not be inferred from VID/PID alone.

## Phase 0 - Freeze tools and capture the normal baseline

This phase does not enter ISP and does not access flash.

### Automated work

1. Record both installed tool paths, versions, hashes, package sources, and
   relevant source files.
2. Select exactly one pinned tool for recovery. Remove the other from the
   recovery script's `PATH` and refuse unexpected hashes.
3. Audit and test the selected implementation's:
   - K530 device profile;
   - normal and ISP USB matching;
   - interface and report IDs;
   - application/page/bootloader sizes;
   - read side effects;
   - erase command;
   - page-write loop;
   - reset-vector transformation;
   - read-back verification; and
   - reboot handling.
4. Capture `lsusb`, full descriptors, HID report descriptors, interfaces,
   endpoints, strings, and physical USB topology.
5. Verify exactly one eligible `258a:0049` device is present.
6. Run a guided baseline test for:
   - every key and Fn chord;
   - all mode switches;
   - all stock RGB modes;
   - wired mode;
   - 2.4 GHz;
   - every Bluetooth slot;
   - charging indication;
   - sleep and wake; and
   - current pairing behavior.
7. Store all results in `baseline.json`.

### Operator actions

- Connect only the K530 under test.
- Set the requested mode switch position.
- Press keys when the key tester highlights them.
- Confirm visible LED and wireless behavior.

### Gate 0

PASS only when tool hashes are frozen, one keyboard is unambiguously isolated
on USB, descriptors are archived, and every stock baseline test passes.

STOP if multiple matching devices exist, USB identity changes unexpectedly, or
the keyboard is already malfunctioning.

## Phase 1 - Capture stock images and prove keyboard-only factory ISP

This is the software-only feasibility gate. It contains state transitions and
the documented read side effect, but no erase/write command.

### Backup sequence

The commands below document the required semantics. The automated workflow must
invoke the frozen absolute executable path after verifying its SHA-256; the
operator does not run these commands manually.

1. Use the stock firmware's HID command to enter ISP.
2. Confirm the ISP VID/PID and protocol variant.
3. Capture two application restore payloads:

   ```sh
   sinowisp read -d redragon-k530-draconic-pro \
     "$K530_WORKDIR/isp/stock-application-a.bin"
   sinowisp read -d redragon-k530-draconic-pro \
     "$K530_WORKDIR/isp/stock-application-b.bin"
   ```

4. Capture two bootloader-only dumps:

   ```sh
   sinowisp read -d redragon-k530-draconic-pro -s bootloader \
     "$K530_WORKDIR/isp/stock-bootloader-a.bin"
   sinowisp read -d redragon-k530-draconic-pro -s bootloader \
     "$K530_WORKDIR/isp/stock-bootloader-b.bin"
   ```

5. Capture two full forensic dumps:

   ```sh
   sinowisp read -d redragon-k530-draconic-pro -s full \
     "$K530_WORKDIR/isp/stock-full-a.bin"
   sinowisp read -d redragon-k530-draconic-pro -s full \
     "$K530_WORKDIR/isp/stock-full-b.bin"
   ```

6. Verify exact sizes:
   - application: 61,440 bytes;
   - bootloader: 4,096 bytes;
   - full: 65,536 bytes.
7. Require byte-identical repeated dumps and record SHA-256 for each.
8. Require the bootloader-only dump to equal the full dump's final 4,096 bytes.
9. Compare the bootloader MD5 with the listed K530 value. A match is
   corroboration, not unit identity.
10. Detect all-zero/all-`0xFF` pages, invalid vectors, unexpected entropy
    changes, and unexplained differences.
11. Preserve two copies on separate storage.

### Bootloader analysis

Automate MCS-51 disassembly of the bootloader and enough of the stock
application to determine:

- reset flow and the meaning of `0xEFFB-0xEFFF`;
- every condition that keeps the factory bootloader active;
- whether entry checks GPIO pins, a key matrix state, USB state, watchdog,
  reset timing, or another flag;
- whether any entry condition is reachable by holding normal keyboard keys or
  switches during USB connection;
- behavior after incomplete application erase/write; and
- whether code options influence an inaccessible entry pin.

Create candidate keyboard-only recovery sequences from direct disassembly
evidence. Do not brute-force undocumented flash commands.

### Guided factory-ISP test

For each evidence-backed candidate, the automation:

1. asks the operator to disconnect USB;
2. displays the exact keys/switch position to hold;
3. asks the operator to reconnect USB while holding them;
4. detects whether ISP USB appears without first sending the stock HID ISP
   command;
5. exits ISP without writing; and
6. repeats after a full power removal.

The successful sequence must work at least five consecutive times and after the
host process has been restarted.

### Gate 1

PASS only when:

- all duplicate backups match and pass structural checks;
- the stock baseline still passes after all reads;
- bootloader entry logic is explained from disassembly; and
- a keyboard-only, application-independent ISP sequence succeeds five times.

STOP THE PROJECT before any erase if no such sequence exists. Under the stated
operator model, a recovery script would otherwise depend on the firmware it is
supposed to recover from.

## Phase 2 - Implement `recover_k530.sh`

This is Goal 1 and the first repository deliverable. This phase does not write
to the real keyboard.

The script is generic and contains no stock binary. A private JSON manifest
binds it to the exact unit and backups.

### Interface

```sh
./recover_k530.sh check \
  --manifest "$K530_WORKDIR/manifests/stock.json"

./recover_k530.sh enter-isp \
  --manifest "$K530_WORKDIR/manifests/stock.json"

./recover_k530.sh restore \
  --manifest "$K530_WORKDIR/manifests/stock.json"

./recover_k530.sh verify-stock \
  --manifest "$K530_WORKDIR/manifests/stock.json"
```

With no action, the script runs `check`. Only `restore` may erase/write.

### Manifest

The schema includes:

- schema version and unit ID;
- normal and ISP USB descriptors/topology;
- the proven keyboard-only factory-ISP sequence;
- pinned tool absolute path, version, source ID, and executable SHA-256;
- stock application absolute path, exact size, and SHA-256;
- bootloader and full-dump paths, sizes, and SHA-256;
- reset-vector transformation metadata;
- expected stock baseline artifact hash; and
- operation-log directory.

Use a schema-validating parser. Never `source` the JSON or use `eval`.

### Script requirements

1. Use `set -euo pipefail`, `umask 077`, absolute resolved paths, and `flock`.
2. Default to non-mutating checks.
3. Verify manifest schema, permissions, every file size/hash, and the pinned
   executable hash before device access.
4. Accept only the manifest's exact 61,440-byte application payload.
5. Reject full/bootloader dumps, all-zero/all-`0xFF` images, arbitrary paths,
   custom sizes, custom addresses, custom profiles, and `--force`.
6. Require exactly one eligible device and no competing normal or ISP device.
7. If the normal application does not respond, guide the operator through the
   proven keyboard-only factory-ISP sequence and verify ISP USB automatically.
8. Display unit ID, USB path, image hash, and operation before mutation.
9. Require the operator to type the unit ID and `RESTORE STOCK`.
10. Invoke only the pinned tool using fixed arguments.
11. Require the tool's internal write/read-back verification.
12. Perform a separate application read-back and compare it after applying only
    the documented reset-vector normalization.
13. Reboot, invoke the guided stock baseline, and produce `recovery-report.json`.
14. Never retry a write automatically. On failure, preserve state and show one
    deterministic next action.
15. Never write the bootloader or code options.

### Failure-path tests

Use fake USB enumeration and fake tool binaries to test:

- check-only success with zero writes;
- missing or malformed manifests;
- malicious manifest strings;
- wrong tool path/version/hash;
- wrong unit, topology, descriptors, or number of devices;
- missing, modified, short, long, zero, and `0xFF` images;
- accidental full/bootloader-image selection;
- declined or incorrect confirmation;
- failure entering ISP;
- disconnect before erase;
- disconnect during erase/write/verify;
- host signal or crash at every script state;
- write failure and independent read-back mismatch;
- lock contention;
- stale state from a previous run; and
- proof that no error path launches a second write.

Run `shellcheck` plus the repository test suite. Generate a machine-readable
coverage matrix linking every failure state to its tested response.

### Gate 2

PASS only when all off-device tests pass, `check` and `enter-isp` work against
the real stock keyboard, and no failure path can broaden the write target or
automatically retry.

## Phase 3 - Controlled stock-to-stock recovery rehearsal

This is the first application erase/write. It is allowed only after Gate 1
proves application-independent factory ISP and Gate 2 proves the script.

### Sequence

1. Run `recover_k530.sh check`.
2. Enter factory ISP using only the proven keys/switches and reconnect action.
3. Run `recover_k530.sh restore`.
4. Require internal verification, independent read-back, and successful reboot.
5. Remove all power.
6. Reconnect normally and run `recover_k530.sh verify-stock`.
7. Repeat every Phase 0 key, RGB, switch, wireless, pairing, sleep, wake, and
   charging test.
8. Repeat the restore starting from normal stock mode to exercise software ISP
   entry.
9. Freeze the manifest and stock payload that passed both rehearsals.

Do not intentionally interrupt real-device power during erase/write. Power-loss
behavior is tested using the tool simulator and source audit. The real operator
is instructed to keep the cable stable.

### Gate 3

PASS only when both entry paths restore exactly the frozen stock behavior and
the script produces complete verified reports.

STOP all custom work if any descriptor, pairing state, key, LED, wireless mode,
hash, or recovery step differs after the rehearsal.

## Phase 4 - Automated stock disassembly and K530 gap map

Use the ISP application payload for restore analysis and a normalized analysis
copy for physical-address disassembly. Account explicitly for `0xEFFB` and
reset-vector redirection.

The automated analysis must recover:

- reset and interrupt vectors;
- clock, LDO, watchdog, and USB initialization;
- all startup SFR and GPIO writes;
- application, settings, reset-redirect, and bootloader boundaries;
- matrix dimensions, GPIOs, polarity, idle state, and logical layout;
- USB descriptors and stock ISP HID report;
- switches and mode-selection GPIOs;
- RGB topology and current-control registers;
- wireless-controller interface and safe disabled state;
- stock settings, pairing, calibration, checksums, and counters; and
- every unresolved assumption relevant to the first custom image.

Create `docs/keyboards/k530.md` with evidence, confidence, and source addresses.
Unknown optional hardware remains disabled. No opening, continuity probing, or
manual electronics work is part of this plan.

### Gate 4

PASS only when every SFR/GPIO touched by the first custom image is supported by
stock disassembly or existing tested SH68F90A platform code, and every other pin
remains in its reset/high-impedance state.

STOP if minimal USB and ISP operation would require an unexplained hardware
assumption.

## Phase 5 - Implement the minimal recovery monitor

The first custom image is intentionally not a keyboard.

### Required behavior

- initialize only the proven clock/LDO/USB path;
- enumerate with a distinct development product string;
- expose status/version over a bounded vendor-HID report;
- accept a confirmed command that jumps to factory ISP at `0xFF00` with the
  required register handshake;
- remain in recovery mode rather than jumping to unimplemented keyboard code;
- use watchdog recovery only after watchdog behavior is proven;
- drive no matrix, RGB, wireless, switch, battery, or unknown GPIO;
- perform no self-programming or persistent flash write; and
- contain no bootloader/code-option write path.

### Build safety

1. Disable/remove Meson's legacy `--force` flash target.
2. Separate build, validate, and write into different commands.
3. Add a canonical image validator that rejects:
   - any byte outside `0x0000-0xEBFF`;
   - reserved settings/reset/bootloader records;
   - invalid reset and interrupt vectors;
   - missing ISP jump/handshake;
   - unexpected USB identity;
   - unexplained SFR/GPIO writes;
   - non-reproducible builds; and
   - image or target mismatch.
4. Disassemble the final binary and compare it to the reviewed source.
5. Run simulator tests for USB enumeration, malformed HID requests, ISP jump,
   wrong confirmation, watchdog behavior, and all interrupt vectors.

### Gate 5

PASS only with a reproducible image, zero failed/skipped safety tests, a clean
validator result, and no unexplained hardware access in final disassembly.

## Phase 6 - First custom write and mandatory stock restore

### Preflight

- [ ] Gates 0 through 5 pass in the workflow state.
- [ ] `recover_k530.sh check` passes in this session.
- [ ] Keyboard-only factory ISP has just been demonstrated again.
- [ ] Frozen stock payload and independent copy have matching hashes.
- [ ] Recovery instructions are visible on another screen.
- [ ] Only one matching keyboard is connected.
- [ ] Host suspend and USB autosuspend are disabled.
- [ ] Stable direct USB cable is used.
- [ ] Recovery-monitor image hash matches the reviewed artifact.

### Sequence

1. The workflow displays the exact image hash and asks for explicit GO.
2. A restricted candidate-write helper writes the recovery-monitor application.
   It cannot accept a different path, target, size, or `--force`.
3. Require tool write/read-back verification and reboot.
4. Detect recovery-monitor USB automatically.
5. Test its status protocol and software ISP command immediately.
6. If the monitor does not enumerate, guide the operator through the proven
   keyboard-only factory-ISP sequence.
7. Run `recover_k530.sh restore`.
8. Remove power, reconnect, and run the full stock verification.
9. Archive the complete report before any second custom write.

### Gate 6

PASS only when the minimal monitor works, both monitor-driven and
keyboard-only factory ISP entry work, and `recover_k530.sh` returns the keyboard
to the frozen stock baseline.

STOP permanently on this unit if stock behavior or factory-ISP reliability
changes.

## Phase 7 - Resilient custom-firmware architecture

After Gate 6, reinstall the recovery monitor and add a separately validated main
firmware region.

The monitor should:

- execute first on every boot;
- provide a short host recovery window before launching main firmware;
- validate main firmware length, target, version, and CRC;
- remain in recovery when main firmware is missing or invalid;
- use a watchdog/reset counter to catch crash loops;
- expose only bounded update operations for the main region;
- never erase or rewrite itself, the factory reset redirect, or bootloader;
- reject host-provided raw addresses; and
- always retain the factory-ISP jump.

If flash capacity permits, use A/B main images. If it does not, keep one
immutable monitor plus one replaceable main image. The capacity decision is
made from measured firmware sizes, not assumed.

The factory ISP path remains the stock-restore mechanism. Normal custom updates
must go through the monitor so later application bugs cannot overwrite the
monitor.

### Gate 7

PASS only when simulated power loss at every update step leaves either a valid
main image or the monitor in recovery, and malformed update requests cannot
address the monitor or bootloader.

## Phase 8 - Add wired keyboard behavior incrementally

Each increment gets a separate build, binary review, simulator run, write,
recovery test, and operator key test:

1. matrix pins initialized but scanning disabled;
2. one evidence-backed matrix line;
3. one row/column intersection with guided key testing;
4. complete matrix scan;
5. compiled-in recovery keymap;
6. layers and Fn behavior; and
7. mode switches.

Test monitor recovery and factory ISP first after every image. Unknown RGB,
wireless, and battery pins remain untouched.

### Gate 8

PASS when all wired keys match the physical layout, no phantom/stuck keys occur,
and a long-running automated key/report test shows no USB, watchdog, or recovery
regression.

## Phase 9 - Add Linux runtime configuration

### Vendor-HID protocol

Implement a bounded protocol with:

- protocol and capability query;
- firmware and board identity;
- complete keymap/layer read-back;
- staged RAM changes;
- atomic apply or reject;
- revert to compiled-in recovery defaults;
- explicit save;
- configuration export/import; and
- confirmed recovery-monitor/factory-ISP entry.

Use fixed command IDs, sequence numbers, bounded lengths, transaction IDs, and
checksums. Validate every layer index and keycode. Never expose arbitrary RAM,
SFR, or flash operations.

### Linux CLI

Create `k530ctl` with:

- `status`;
- `keymap export`;
- `keymap import`;
- individual key/layer inspection and update;
- `apply`;
- `revert`;
- `factory-defaults`;
- `save`; and
- `enter-recovery`.

Every mutation is read back and compared. Produce machine-readable output so an
LLM workflow and later GUI can use the same interface.

### Persistent configuration

The current one-byte-length settings record is insufficient. Reserve dedicated
sectors only after the measured linker map permits it.

Use versioned A/B records containing magic, schema version, length, generation,
payload CRC, and record CRC. Write and verify the inactive record before making
it current. On any corruption or interruption, boot with the compiled recovery
keymap and keep USB/recovery available.

Flash writes occur only after explicit `k530ctl save`. Test interrupted writes
at every modeled byte/sector boundary.

### Gate 9

PASS only when:

- all keys/layers can be changed, read back, exported, and restored on Linux;
- malformed requests cannot escape protocol bounds;
- failed persistence always retains one valid record or safe defaults;
- recovery monitor and factory ISP remain reachable; and
- `recover_k530.sh` still restores the frozen stock state.

## Phase 10 - Optional RGB and wireless

Add one subsystem per independently recoverable image:

1. one measured status LED;
2. complete RGB scanning/current control;
3. Linux RGB controls;
4. wireless-controller power/reset;
5. 2.4 GHz protocol; and
6. Bluetooth and pairing persistence.

No optional subsystem is required for the configurable wired-firmware goal.
Unknown or unverified subsystems remain disabled.

## Failure decision table

| Detected state | Automated response | Operator action |
| --- | --- | --- |
| Stock/custom USB works | Request factory ISP, validate ISP identity, offer stock restore | Confirm restore |
| Recovery monitor works, main firmware fails | Keep monitor active; reject main boot; offer main update or stock restore | Confirm selected action |
| Normal USB absent, factory ISP present | Validate frozen manifest and offer stock restore | Confirm restore |
| Normal USB absent, factory ISP absent | Guide the proven power-off/key-hold sequence and poll USB | Hold displayed keys and reconnect |
| Restore preflight fails | Refuse all writes and identify exact failed check | Correct connection only if prompted |
| Write verification fails but ISP remains | Preserve logs and offer one stock restore | Confirm once |
| Host crashes before erase | Resume at preflight; no device mutation assumed | Re-run workflow |
| Host/power fails during erase/write | Re-enter factory ISP with proven keyboard sequence, revalidate manifest, offer stock restore | Hold keys/reconnect, then confirm |
| Factory ISP cannot be entered after repeated proven sequence | Stop; no software-only recovery exists under this operator model | Do not attempt guesses |
| Bootloader/code options appear changed | Stop; normal workflow has violated its safety boundary | Do not continue |

## Completion criteria

The project is ready for hobby use only when:

- no external programmer or electronics work is required for tested failures;
- keyboard-only factory ISP entry is proven independently of application code;
- `recover_k530.sh` restores the frozen stock image after custom firmware;
- every destructive action is manifest-locked and deterministic;
- simulated failures cover every workflow state and flash-update boundary;
- the recovery monitor survives every supported main-firmware failure;
- wired key/layer configuration works and reads back on Linux;
- corrupt persistent configuration falls back to safe defaults;
- all USB, key, recovery, and stock-baseline tests are repeatable; and
- optional features are clearly separated from the wired configurable goal.

The remaining accepted risk must be stated plainly: a factory-bootloader defect,
bootloader/code-option corruption outside the allowed command set, or hardware
failure cannot be repaired by software alone. The workflow prevents itself from
targeting those regions; it does not claim to make physically impossible
recovery possible.
