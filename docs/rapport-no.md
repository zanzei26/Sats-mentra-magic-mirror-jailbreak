# Fra låst kiosk til selvstendig Android 13: SATS Mentra Rflex-speil (RK3399)

*Erfaringsrapport for forum. Alt er gjort på ett enkelt eksemplar av et utgått treningsspeil, over én lang økt (2026-11-04). Serienumre, brukernavn og stier er anonymisert. Bruk på eget ansvar: flere av stegene skriver direkte til eMMC, og partisjonsoffsetene under er **spesifikke for dette speilet** – les dem på din egen enhet, ikke kopier dem blindt.*

---

## 0. Kort fortalt (TL;DR)

| Mål | Utfall |
|---|---|
| Fjerne kiosk/device-owner-låsen ([FS] Launcher, `com.mentra.launcher`) | ✅ Fjernet, og kommer ikke tilbake |
| Appbutikk på speilet | ✅ Aurora Store (anonym innlogging) |
| Nyere Android som kjører selvstendig | ✅ Android 13 (GSI, `TQ3A.230805.001.A3`) permanent installert i `super`, booter på ~66 s uten DSU |
| Skjerm av så glasset fungerer som speil, trykk for å bruke | ✅ Skjermtidsavbrudd 60 s + liten «touch-to-wake»-tjeneste |
| Maskinvarevideo | ❌ Bevisst avslått (krasjer kjernen på VP9, gir søppel på A13). Programvaredekoding i stedet |
| Google Play-tjenester (GMS), YouTube-appen | ❌ Finnes ikke i en ren AOSP-GSI. YouTube går i nettleser |

Det viktigste vi lærte:

1. **Å nullstille `userdata` fjerner ikke låsen.** Mentra-appen ligger på den skrivebeskyttede `odm`-partisjonen og setter seg selv opp som device owner på nytt (bygget har `su`). Antakelsen «utgått produkt = ingen re-provisjonering» var feil.
2. **Android-versjoner kan testes uten å flashe noe** med *Dynamic System Updates* (DSU) og Googles offisielle GSI-er, takket være at speilet har ulåst bootloader og Treble-vendor.
3. **Vendor-delen (Android 10, kjerne 4.19) kan beholdes** og kombineres med en GSI hvis du tar noen grep (SELinux, ext4-features, HWUI-flagg). Det er vendor-laget som eier panel, touch, Wi-Fi, lyd osv.
4. **Maskinvare-videodekoderen (rkvdec/mpp) er ubrukelig** sammen med denne kjernen: VP9 gir IOMMU-sidefeil → kernel panic, også på original Android 10.
5. **Alt tilbakerullbart** så lenge du har full eMMC-backup + maskrom. Vi tok backup før vi skrev noe, verifiserte den mot enheten, og la den permanente installasjonen i ledig plass i `super` slik at kun én gammel region og metadataene ble overskrevet.

---

## 1. Utstyr og utgangspunkt

- **Speil:** SATS Mentra Rflex (utgått). SoC Rockchip **RK3399**, ~3,9 GB RAM, 59 GB Samsung-eMMC, USB-touchskjerm (eGalax), Mali-T860.
- **Programvare fra fabrikk:** Android 10, kjerne **4.19.111** (BSP), Treble (VNDK 29, FCM-nivå 4), *dynamic partitions* (`super`), `vbmeta` med verifisering avslått (`flags=2`), **ulåst bootloader** (verified boot «orange»).
- **Låsen:** appen **[FS] Launcher** (`com.mentra.launcher`) er satt som *device owner* og kjører kiosk/lock-task. ADB er av og blokkert via policy (`DISALLOW_DEBUGGING_FEATURES`). Den skjulte servicemenyen i launcheren bruker en tidsbasert TOTP vi ikke har nøkkelen til. Det fantes ingen myk vei inn.
- **Vei inn:** én recessed knapp på baksiden = **Rockchip maskrom**. Hold knappen inne mens strøm settes på → svart skjerm, enheten dukker opp som «Rockusb Device» (VID `2207`, PID `330C`).
- **PC:** Windows 11 (+ WSL2). Verktøy: RKDevTool v2.86, Rockchip DriverAssistant v5.14, `adb` (platform-tools), loaderen `rk3399_loader_v1.30.130.bin`.

> Rockchip-loaderen lastes til RAM (`db`) og skriver ikke flash. Maskrom er alltid tilgjengelig, uansett hva som ligger i flash, så enheten er i praksis ikke mursteinbar så lenge du har backup.

---

## 2. Første hindre: USB og verktøy

| Problem | Løsning |
|---|---|
| Maskrom ustabil («device descriptor request failed») på PC med kun USB-3-porter | Riktig kabel + **USB-2.0-hub** mellom PC og speil. Bruk kombinasjonen som gir en stabil «Rockusb Device» i Enhetsbehandling |
| `rkdeveloptool` i WSL via `usbipd` | `db`, `rfi` og `ppt` hang gjentatte ganger (USB/IP er for ustabilt for Rockusb). Oppgitt |
| RKDevTool **v3.37** | Krasjer. **v2.86 fungerer** (sett `config.ini` til engelsk) |
| RKDevTool v2.86 er et GUI | Vi drev det med Windows UI Automation/Win32 (`BM_CLICK`) mot fanen *Advanced Function*: **Read Flash Info**, **Export Image** (leser en LBA-region til fil), **Erase LBA**, **Reset Device**. Vi la en hvitliste av tillatte knapper i skriptet for å unngå utilsiktede skriv |
| Modal dialog «idbloader did not find match partition» blokkerer vinduet | Lukkes med `BM_CLICK` på OK (kan komme forsinket) |

---

## 3. Partisjonskart (lest, ikke endret)

Lest med RKDevTool v2.86. Totalt **120 832 000 sektorer × 512 B = 61 865 984 000 byte**, GPT med backup-GPT i de siste 33 sektorene.

| # | LBA (hex) | Størrelse (hex) | Navn | Størrelse |
|---|---|---|---|---|
| 01 | 0x4000 | 0x2000 | uboot | 4 MiB |
| 02 | 0x6000 | 0x2000 | trust | 4 MiB |
| 03 | 0x8000 | 0x2000 | misc | 4 MiB |
| 04 | 0xa000 | 0x2000 | dtb | 4 MiB |
| 05 | 0xc000 | 0x2000 | dtbo | 4 MiB |
| 06 | 0xe000 | 0x800 | vbmeta | 1 MiB |
| 07 | 0xe800 | 0x10000 | boot | 32 MiB |
| 08 | 0x1e800 | 0x2000 | security | 4 MiB |
| 09 | 0x20800 | 0x30000 | recovery | 96 MiB |
| 10 | 0x50800 | 0x38000 | backup | 112 MiB |
| 11 | 0x88800 | 0xc0000 | cache | 384 MiB |
| 12 | 0x148800 | 0x8000 | metadata | 16 MiB |
| 13 | 0x150800 | 0x400 | frp | 512 KiB |
| 14 | **0x150c00** | 0x614000 | **super** | 3112 MiB (system + vendor + product + odm) |
| 15 | 0x764c00 | 0x6bd73df | userdata | ~53,9 GiB |

Kontroll: `userdata`-slutt = 7 752 704 + 113 079 263 = 120 831 967 = totalt − 33 (backup-GPT).

Arbeidsregler vi satte oss (de reddet oss flere ganger):

- **Aldri** generisk RK3399-firmware: panelets innstillinger ligger i speilets egen software → svart skjerm.
- **Aldri** `EraseAll` / skriv til hele flashen.
- **Ingenting skrives før full backup er tatt, verifisert og kopiert bort.**
- Rør ikke `uboot`/`trust`/`parameter`/`boot`.
- Usikker på offset? Stopp.

---

## 4. Full backup (før alt annet)

- Hele eMMC (61 865 984 000 byte) ble lest i biter med *Export Image* og satt sammen til én fil. Verifisert på størrelse (`total_sektorer × 512`) og SHA-256, og kopiert til en andre disk.
- Feil underveis: skriptet som skulle oppdage «bit ferdig» telte linjer i loggvinduet, men RKDevTool **tømmer loggen for hver eksport**. Rettet til å se etter *Success*-linjen **og** at filstørrelsen er riktig.
- Småting: en PowerShell-funksjon kalt `H` kolliderte med et alias; en parameter `$Gz` og variabel `$gz` er samme variabel (PowerShell er ikke case-sensitiv).
- Før den permanente flashen i kapittel 11 sammenlignet vi i tillegg **den levende `system`-regionen på enheten byte-for-byte mot backupen** (samme SHA-256) – dermed vet vi at backupen faktisk representerer enheten, ikke bare at filen er lesbar.

---

## 5. Det første forsøket og den feilen vi lærte mest av

**Plan (fra overtakelsesdokumentet):** device owner ligger i `/data` (`device_owner*.xml`, `device_policies.xml`) → null ut `userdata` → låsen er borte, og siden produktet er utgått finnes ingen server som setter den opp igjen.

**Hva som skjedde:** speilet startet på nytt på ren `/data`, men viste igjen oppsettet av Mentra-speilet i [FS] Launcher. **Låsen kom tilbake.**

**Årsak:** [FS] Launcher er ikke bare en app i `/data`. APK-en (≈19 MB) ligger i `/odm/bundled_uninstall_back-app/com.mentra.launcher/`, på en skrivebeskyttet partisjon som en `userdata`-sletting ikke berører. Android 10-bygget fra Rockchip/leverandør installerer den ved første oppstart, og siden bygget har `su` (userdebug-aktig) setter appen seg selv opp som device owner – ingen server involvert.

**Rett fremgangsmåte på original Android 10 (gjort, med eierens godkjenning):**

1. Etter `userdata`-sletting var ADB (med root) tilgjengelig. Vi hentet ut `device_owner_2.xml`, `device_policies.xml`, `package-restrictions.xml` og `settings_global.xml` for å forstå tilstanden.
2. Fjernet device-owner/policy-filene i `/data/system/`, og merket pakken som avinstallert for bruker 0 i `package-restrictions.xml`.
3. **Skjulte APK-en permanent** med en overlayfs: `adb remount` lager en `scratch`-partisjon i ledig `super`-plass, og i overlayen lages en *whiteout* over `com.mentra.launcher` i `/odm`. Da kan den ikke installeres på nytt ved neste oppstart.
4. Resultat: ordinær Android-launcher, ingen device owner. (Mentra-logoen i oppstarten er et eget kosmetisk tema; den er byttet ut senere – se 10.2.)

> **Korrigert antakelse:** «userdata-wipe fjerner låsen» – nei, kun hvis appen som setter den ikke kommer tilbake. Sjekk alltid hvor kiosk-appen *installeres fra*.

(Dette er den eneste delen som trengs om du bare vil bli kvitt låsen og beholde Android 10. Resten av rapporten handler om å gå videre til Android 13.)

---

## 6. Kartlegging av maskinvaren (hva er egentlig i dette speilet?)

For å vurdere hvor langt opp i Android-versjon vi kunne gå, leste vi systemet på enheten:

- Treble-vendor (VNDK 29), `ro.boot.dynamic_partitions`, vbmeta uten verifisering, ulåst bootloader → **GSI-er kan kjøre oppå vendor**.
- Kjerne 4.19.111: Android 13 støtter 4.19, men vendor-HAL-ene (Mali r18p0-blob, rkvdec, Wi-Fi/BT, lyd) er bygget mot Android 10.
- FCM-nivå 4 (Android 10) → nyere Android-versjoner kjører i «kompatibilitetsmodus» mot vendor. Det er det som gjør dette mulig, og det er også kilden til alle problemene under.
- Chrome 156 har `minSdk 32` (Android 12L+). Det er et konkret argument for A13 i stedet for A11.

---

## 7. Test uten å flashe: DSU + Googles GSI-er

**DSU (Dynamic System Updates)** installerer et system-image i en egen dynamisk partisjon (`system_gsi`) og et eget `userdata_gsi`-image **som filer i `/data/gsi`**. Neste oppstart er *one-shot*: boots den ikke, eller starter du på nytt, er du tilbake på original Android. Ingenting i `super` røres, og `vendor`/`odm` fra speilet gjenbrukes.

- Android 10 har DSU men skjuler UI-et bak et feature flag (`persist.sys.fflag.override.settings_dynamic_system`); installasjonen kan også startes mot `dynsystem`-tjenesten. (Dagens A13 viser «DSU Loader» under Utviklervalg.)
- Vi lastet ned **offisielle Google GSI-er**: Android 11 (`RP1A`), 12 (`SQ3A`), 13 (`TQ3A`), `arm64`, `A/B`-varianten, pakket ut til rå `system.img` og gzip-et til `system_raw.gz`.

Resultater:

| GSI | Resultat |
|---|---|
| **Android 11** | Starter. HWUI krasjer med `EGL_BAD_ACCESS` mot Mali-blobben. Løst med `debug.hwui.use_partial_updates=false`, `debug.hwui.use_buffer_age=false` |
| **Android 12** | Hang/loopet ved oppstart (logoen forble). Årsak **ikke** fastslått; sannsynlige kandidater er de som senere ble løst på A13 (SELinux-mismatch, ext4-features, `seclabel`-krav) |
| **Android 13** | Starter og kjører etter modifikasjonene under |

### Modifikasjoner som skulle til for at A13 skulle kjøre på Android 10-vendor

Alt gjøres i en **modifisert kopi** av `system.img` (rå ext4, `shared_blocks`) som vi bygde om til et vanlig skrivbart ext4:

1. **Gjenoppbygg ext4 med kjernevennlig feature-sett** for 4.19: `mke2fs -d <utpakket gsi> -O ^has_journal,^resize_inode,^64bit,^metadata_csum,^orphan_file,^flex_bg,uninit_bg`. Nyere `e2fsprogs` på PC slår på funksjoner (`orphan_file`, `metadata_csum`) som kjerne 4.19 ikke kan montere. Bevar `security.selinux`-xattrs (`os.getxattr`/`setxattr`), ellers blir filene umerkede.
   *Feil vi gjorde:* første image ble 2304 MB – for lite, siden `mke2fs -d` kopierer ut det `shared_blocks` delte. Måtte til 3072 MB.
2. **`build.prop`:** `ro.secure=0`, `ro.adb.secure=0`, `ro.debuggable=1`, `persist.sys.usb.config=adb`, `service.adb.root=1`, `debug.hwui.use_partial_updates=false`, `debug.hwui.use_buffer_age=false`, `debug.renderengine.backend=gles` (A13 bruker Skia-RenderEngine som standard; GLES-backend går bedre mot den gamle Mali-blobben).
3. **SELinux:** Android 13-plattformpolicy og Android 10-vendorpolicy passer ikke sammen. Vi la til `(typepermissive <type>)` for alle ~1820 typer i `plat_sepolicy.cil` (inkludert vendor-typene). Globalt står `getenforce` fortsatt «Enforcing», men alle domener er i praksis permissive: **brudd logges, blokkeres ikke**. Vendorens `precompiled_sepolicy` har feil hash mot den nye plattformen, så init kompilerer fra CIL ved boot (litt tregere, men det virker).
4. **Init-gotcha:** `init` nekter å starte en service som ikke kan gjøre domenebytte, *selv om* domenet er permissive. Egne services må ha `seclabel u:r:shell:s0` (eller annet eksisterende domene).
5. **Boot-diagnostikk:** en egen service skrev `dmesg`, `getprop` og `logcat` til `/metadata/dbg` (uten kryptering, leselig fra en annen Android-versjon etterpå), og en vaktbikkje startet maskinen på nytt hvis `boot_completed` ikke kom. Dette var avgjørende for å forstå krasjer; `pstore/ramoops` ga oss panic-logg for videokrasjene.

Fallgruver underveis (alle selvforskyldt, alle lærerike):
- PowerShell ekspanderer `$(...)` lokalt før `adb shell` ser det. **Skriv skriptene til fil og `adb push` dem** i stedet for å sitere komplekse kommandoer.
- WSL2-VM-en stenger seg når den er «inaktiv» og dropper loop-mounts. Hold den i live (`wsl ... sleep 10800`) og mount i selve skriptet.
- Et `service call dynamic_system 5` fjernet en ferdig installert DSU-image. Husk at DSU-kommandoer er ødeleggende; sjekk `gsi_tool status` først.

---

## 8. Appbutikk, Chrome og nettleser

- **Aurora Store** (open source Play-klient, APK fra GitHub/F-Droid-kilden) med **anonym innlogging** via Aurora-dispenseren. Ingen Google-konto er logget inn på speilet.
- **Chrome** fra Aurora. Krever Android 12L+ (`minSdk 32`) – et konkret krav til at vi valgte A13.
- **YouTube-appen** krever Google Play-tjenester (GMS) og fungerer ikke på en ren GSI. YouTube i Chrome virker, men tungt (se neste kapittel).

---

## 9. Video: hva som virker, og hvorfor maskinvaredekoding er skrudd av

Brukeren opplevde at YouTube i Chrome «virket dårlig» og spurte om maskinvaren er sterk nok, og om det skyldes at A13 kjører oppå A10. Svaret er «begge deler».

**Funn:**

- **Dekoder-stakken:** vendorens `OMX.rk.video_decoder.*` (via `omx_vdec`/`mpp`/`rkvdec`) er skrevet for Android 10-rammeverket. Android 13 bruker `ACodec` med `DynamicANWBuffer`/`-1010`-feil mot den → **korrupt bilde** på H.264/HEVC med maskinvaredekoding.
- **VP9:** IOMMU-sidefeil i `rkvdec` → **kernel panic**. Dette skjer **også på original Android 10**, så det er et kjerne/driver-problem og ikke noe GSI-en gjør.
- **CPU:** RK3399 = 2×Cortex-A72 + 4×A53. Programvaredekoding av 1080p H.264 gjør begge A72-kjernene ~98 % opptatt; 1080p VP9 ligger rundt 65 %. Det går, men 1080p-YouTube er på grensen. 720p er behagelig.

**Løsning:** gjør maskinvaredekoderen utilgjengelig for alt unntatt kamera-tjenesten (se 9.1 for hvorfor «alt unntatt root» ikke holdt). I `init`-rc:

```
on boot
    chmod 0600 /dev/mpp_service
    chown cameraserver root /dev/mpp_service
```

Da feiler `MediaCodec` på OMX-komponenten (åpning av `/dev/mpp_service` mislykkes), og Chrome faller tilbake til programvaredekoding. **Verifisert** på både H.264 1080p (Chrome, `OMX.rk.video_decoder.avc` → «Failed to get input buffer», fallback til programvare) og VP9 1080p (`OMX.rk.video_decoder.vp9` → fallback), begge uten kjernefeil.

I tillegg legger oppstartsskriptet `/data/local/chrome-command-line` med `_ --disable-accelerated-video-decode`, slik at Chrome ikke engang prøver (merk: Chrome leser den filen bare på «debuggable» Android, og vår build har `ro.build.type=user`, så effekten av akkurat denne filen er *ikke* bekreftet; blokkeringen av noden er det som faktisk gjør jobben).

**Begrensning:** andre apper som bruker `MediaCodec` direkte uten fallback (f.eks. enkelte spillere) kan feile i stedet for å falle tilbake. En mer fullstendig løsning er å fjerne `OMX.rk.video_decoder.*` fra vendorens `media_codecs*.xml` – det har vi ikke gjort, for da måtte `vendor` endres.

---

### 9.1 Bivirkning: kamerabildet ble grønt (og hvorfor)

Første versjon av blokkeringen var `chmod 0000` + `chown root root`. Rett etterpå viste kamera-appen **bare grønt bilde**, og kamera-leverandørprosessen døde med `signal 13`/`CAMERA_ERROR`. Loggen sa det rett ut:

```
ExtCamDevSsn@3.4: failed to prepare JPEG decoder
HAL_JPEG_VDPU2:   hal_jpegd_vdpu2_init mpp_dev_init failed. ret: -1
```

**Forklaring:** speilets kamera er et vanlig USB-webkamera (UVC, `RGB Camera`) som leverer **MJPEG**. Den eksterne kamera-HAL-en dekoder MJPEG med **samme VPU (`/dev/mpp_service`)** som videodekoderen. Blokkerte vi noden, ble bufferne aldri skrevet – og nullede YUV-buffere vises som grønt.

**Rettelse (to forsøk):**

1. `chmod 0660` + gruppe `cameraserver` → fungerte **ikke** ved kaldoppstart: leverandørprosessen kjører som bruker `cameraserver`, men med primærgruppe fra sin `group`-linje (`audio camera input drmrpc`), ikke `cameraserver`. (Det midlertidige testet med `chown cameraserver:cameraserver` + `0600` hadde fungert fordi det ga *eierskap*.)
2. **Endelig:** `chown cameraserver root` + `chmod 0600`. Kun *brukeren* `cameraserver` (og root) kan åpne noden; `mediacodec` (videodekoding) kan ikke → fortsatt programvaredekoding av video. Verifisert etter kaldoppstart: ingen `failed to prepare JPEG decoder`, `HAL_JPEG_VDPU2` kjører, bildet er ekte.

> Lærdom: en «sikker» blokkering av en delt enhetsnode må testes mot *alle* brukere som legitimt trenger den. Her var det kamera som var avhengig av videomaskinvaren – ikke noe man gjetter seg til.

---

## 10. Speil-funksjonen: skjerm av + trykk for å bruke

Mål: glasset skal være et speil (skjermen svart/av) til noen trykker.

- **Skjermtidsavbrudd:** `settings put system screen_off_timeout 60000` (60 s) og `cmd lock_settings set-disabled true` (ingen låseskjerm). Kjøres én gang ved første oppstart.
- **Touch-to-wake:** Android 13 vekker ikke skjermen på berøring selv. Prøvd og **ikke virksomt:** IDC-fil med `touch.wake=1` for eGalax-berøringsskjermen (effekten finnes ikke i denne input-stakken).
- **Løsning:** en liten tjeneste som leser rå evdev-hendelser fra touch-noden og kaller `input keyevent 224` (WAKEUP) hvis skjermen ikke er våken:

```sh
#!/system/bin/sh
# Touch-to-wake helper for the SATS mirror
DEV=/dev/input/$(grep -A8 -i 'eGalax' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
while true; do
  # block until the touchscreen reports an event, then wake the display if it's off
  getevent -c 1 "$DEV" > /dev/null 2>&1 || { sleep 2; continue; }
  if ! dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake'; then
    input keyevent 224
  fi
  sleep 1
done
```

- **Feil vi gjorde to ganger her:**
  1. Vi tolket et «gjenkjent trykk» som at berøring vekket skjermen, men det var eieren som hadde rørt både skjerm og tastatur; *tastaturet* vekket den. Rå berøring vekker ikke av seg selv.
  2. Første versjon sjekket `mWakefulness=Asleep`. Etter `sleep` går Android gjennom **`Dozing` (≈2 s) → `Asleep`**, og et trykk i `Dozing`-vinduet ble ignorert. Riktig test er «ikke `Awake`».
- Testet med **syntetiske berøringshendelser** (`sendevent` mot touch-noden, samme vei som ekte trykk). Ekte fingertrykk på det ferdige systemet er testet av eier der dette gjelder; se «Ikke verifisert» sist.

---

### 10.1 UI-størrelse og hastighet (justert etter at systemet var oppe)

Eieren syntes alt var for stort og at maskinen var treg.

- **Skjermstørrelse:** panelet er 1080×1920 med `ro.sf.lcd_density=240` (≈ «150 % zoom» i Windows-språk; 160 dpi = 100 %). `wm density 180` (≈ 112 %) ga mer plass og er et rent Android-innstillingsvalg (`wm density reset` angrer; overlever omstart og påvirker ikke systemimaget). Skal det mindre/større: `wm density 160`/`200`.
- **Hastighet:** målt tilstand: CPU-governor `interactive` (A53 408–1416 MHz, A72 408–1800 MHz), GPU `simple_ondemand` som **hviler på 200 MHz** (Mali-T860, 200–800 MHz), DDR `dmc_ondemand` på maks. Fordi vi kjører med `debug.hwui.use_partial_updates=false` tegnes hele 1080×1920 på nytt hver ramme, og GPU-en bruker for lang tid på å klatre. Tiltak: animasjonsskalaer 0,5 (`window/transition/animator`), **GPU min 400 MHz**, **CPU-gulv 816 MHz** på begge klyngene. Temperatur i hvile ~43–47 °C, så det er god margin. Ingen støy fra SELinux-logging (avc-linjene vokste ikke i hvile).
- **Gjør tuning varig uten å flashe systemet på nytt:** systemimaget er skrivebeskyttet, så `mirror_setup.sh` fikk en krok: `[ -f /data/local/mirror_local.sh ] && sh /data/local/mirror_local.sh`. Alt som skal justeres (GPU-/CPU-frekvenser, governor, osv.) ligger i den filen på `/data` og kan redigeres over `adb` uten ny flash.
- **Hvordan krok-endringen kom inn i et ferdig installert system:** *same-length single-block patch*. For små filer (< 4 KiB) der filstørrelsen ikke endres, bruker vi `debugfs bmap` til å finne filsystemblokken, regner ut hvilken `super`-blokk den ligger i (extent A eller B), lager en ny 4 KiB-blokk med nytt innhold polstret med en kommentarlinje til nøyaktig samme lengde, og skriver kun den blokken med `dd` etter å ha sjekket at nåværende blokk har forventet hash. Inoden røres ikke, `e2fsck` er fortsatt ren. Merk: dette forutsetter at filen bare bruker én blokk, og endringen gjelder fra neste oppstart.

---

### 10.2 Boot-logoen (Mentra → «Magic Mirror»)

Under oppstart vises først U-Boots logo og deretter kjernens logo. Android-fasen (bootanimation) er bare vanlig «android»-tekst på A13 (vi sjekket ved å kjøre `start bootanim` på det kjørende systemet; `/odm/media/bootanimation.zip` med Mentras «Loader-Symbol» brukes ikke av A13).

**Hvor ligger logoen?** Ikke i en egen `resource`-partisjon: `dtb`-partisjonen er tom. I stedet ligger et Rockchip **resource-bilde** (`RSCE`) som «second»-delen av `boot`-partisjonen (offset 27 025 408 byte). Det har tre oppføringer:

| Oppføring | Innhold |
|---|---|
| `rk-kernel.dtb` | enhetstreet (rører vi ikke – her ligger panelinnstillingene) |
| `logo.bmp` | U-Boot-logoen: **240×240, 8 bit, ukomprimert, 42-fargers palett, 57 822 byte** |
| `logo_kernel.bmp` | kjerne-logoen: byte-identisk kopi av `logo.bmp` |

Strukturen er `RSCE`-header (blokk à 512 B) + 512-byte oppføringer (`ENTR`, 256-byte sti, `offset` og `size` i blokker/byte). Noe annet enn logo-oppføringene trenger altså ikke å røres, og **det finnes ingen sjekksum over ressursbildet** som vi kunne se (og `vbmeta` har verifisering av, `flags=2`).

**Fremgangsmåte – bytt innholdet i filen, ikke strukturen:**

1. Tegn en 240×240-logo (vi brukte `System.Drawing` på Windows: oval speilramme, to «glint»-streker, tre små stjerner og teksten «MAGIC MIRROR», hvit på sort).
2. Kvantiser til **42 gråtoner** (palettplassen i originalen) og skriv en BMP med **nøyaktig samme header** som originalen (samme høyde-fortegn = bunn-opp, samme pixel-offset 222, samme `biClrUsed`=42), slik at filstørrelsen blir identisk (57 822 byte). Slik trengs ingen ompakking og ingen offsets endres.
3. Hver fil opptar 113 sektorer (57 822 byte + 34 byte polstring). De to regionene ligger rett etter hverandre (`logo.bmp` @ sektor 53 004, `logo_kernel.bmp` @ sektor 53 117), så det er **én skriving på 226 sektorer** med originalens polstringsbyte beholdt.
4. På enheten: avbryt om (a) regionen ikke er identisk med originalen, (b) hele 32 MiB-`boot`-partisjonen ikke har samme SHA-256 som backupen, (c) patch-filen har feil hash. Skriv med `dd`, les tilbake regionen, og sjekk til slutt at **hele `boot`-partisjonen = original + kun logo-patchen** (forhåndsberegnet hash). Alt gikk grønt.

Rollback: skriv tilbake de samme 226 sektorene fra `boot`-backupen (eller hele `boot`-partisjonen).

> Merk: vi har valgt å *ikke* bytte filene i ressursbildet med en ompakker (`resource_tool`), fordi en ompakking flytter offsets og krever at hele `boot`-partisjonen skrives på nytt. Same-size-bytte er mye mindre risikabelt.

**Resultat:** første versjon (tegnet oppreist) ble vist **90° feil vei** på panelet. Etter at bitmapet ble **rotert 90° med klokka** før skriving (piksel `(x, y)` → `(239−y, x)`; samme skriveprosedyre, nå med hash-sjekk mot forrige skrevne tilstand i stedet for originalen) står logoen riktig, bekreftet av eier ved kaldoppstart. Lærdom: panelet er fysisk et portrettpanel som drives i en annen orientering under U-Boot/kjerne, så bilder i ressursbildet må **forhåndsroteres** – ikke lagres slik de skal se ut. Hvis du bytter logo på en annen enhet: forvent å måtte teste én rotasjon, og hold backupen av de 226 sektorene klar.

---

## 11. Permanent installasjon av Android 13 i `super`

Eier valgte «Permanent Android 13» etter å ha fått beskjed om at dette er en reell flash-endring.

### 11.1 Hvorfor det er enklere enn det høres ut

- `super` er et **LP-metadata-område (første 1 MiB) + dm-linear-extents**. System = én liste av extents. Vi trenger ikke flytte `vendor`/`odm`/`product` – de ligger fast på sine sektorer.
- Android 13-GSI-en har `/product` og `/system_ext` *inni* system-imaget og en `skip_mount.cfg` (`/product`, `/system_ext`) som får første-stage-init til **ikke** å montere speilets egen `product`-partisjon. Den kan ligge urørt (Android 10-innhold, ubrukt, men fortsatt i metadataene).
- GSI-en ignorerer `/odm/bundled_uninstall_back-app` (en leverandør-mappe som bare Rockchips Android 10-rammeverk skanner). **Mentra er derfor ikke i det hele tatt synlig for A13**, uten at vi trenger overlayen (`scratch`) lenger. Verifisert: ingen `com.mentra.*`, ingen device owner.

### 11.2 Layout

Det ferdige systemet ble **2 377,7 MiB** (4 869 440 sektorer; krymp med `resize2fs -M` + 64 MiB slark). Den gamle `system`-regionen er bare 896 MiB, så systemet får **to extents**:

| Extent | Sektorer (512 B) | Fysisk start i `super` | Merknad |
|---|---|---|---|
| A | 1 834 952 | 2048 | den gamle systemregionen (overskrives) |
| B | 3 034 488 | 2 930 688 | ledig hale i `super` (1 MiB-justert) |

`vendor` (467 312 @ 1 837 056), `product` (580 864 @ 2 306 048) og `odm` (40 408 @ 2 887 680) er **uendret**. Gruppestørrelsen er 5 958 024 sektorer (2909,2 MiB) av maks 3108 MiB.

### 11.3 LP-metadata – skrevet selv, validert av AOSP

Vi skrev en minimal parser/omskriver for `liblp`-formatet i Python (vedlegg A): leser geometri + metadata, endrer partisjons- og extent-tabellene, regner SHA-256 for header og tabeller på nytt, og skriver primær + backup for slot 0. Valideringskjede:

1. Egen parser leser original metadata fra backupen **og** live-metadata fra enheten (inkl. `scratch`) – matcher `lpdump` fra enheten.
2. Den nye metadataen leses av **enhetens egen AOSP-`lpdump`** (`lpdump <fil>`) uten feil, og viser nøyaktig forventet layout.
3. Etter skriving leses den ekte `super` på enheten med `lpdump`.
4. Før metadata ble skrevet bygde vi et `dm-linear`-device (`dmctl create`) med nøyaktig samme tabell som første-stage-init vil lage, leste hele enheten tilbake og sammenlignet SHA-256 med PC-imaget, og monterte den read-only (`ro.build.version.release=13`).

### 11.4 Rekkefølge og verifikasjon (fra kjørende DSU-gjest)

1. `system_final.img` (2 493 153 280 B) ble gzip-et, `adb push`-et til gjestens `/data`, dekomprimert på enheten, og hash-sjekket (`40ad3720…`).
2. Forhånds-sjekker i skriptet: image-hash, **live LP-metadata er det vi forventer**, størrelse på `super`.
3. Skriv **extent B** (fri plass) → les tilbake → SHA-256 lik.
4. Skriv **extent A** (her overskrives original `system`) → les tilbake → SHA-256 lik.
5. `dm-linear`-test av den nye layouten (punkt 4 over).
6. Skriv **LP-metadata** (første 1 MiB) → les tilbake → `lpdump`.
7. Kontroll: `vendor`/`product`/`odm`-regionene er fortsatt **byte-identiske med backupen**.
8. `misc`: bootloader_message `boot-recovery` + `recovery\n--wipe_data\n` → `reboot recovery`. Speilets egen Android 10-recovery formaterte `/data` (≈48 s) og startet på nytt. (Dette var også nødvendig fordi DSU-imagene bor i `userdata`.)

Hele skrivefasen (B + A + verifikasjon) tok ca. 1,5 minutt med `dd` (60–70 MB/s).

> Merk: filsystemet er montert read-only fra `dm-0` mens vi senere patchet et enkelt 4 KiB-datablokk (touch-wake-skriptet) direkte på blokkenheten, med blokk-hash for og etter. Det er trygt for en fil på én blokk når filstørrelsen er uendret (inoden røres ikke), og endringen trer i kraft ved neste oppstart.

### 11.5 Rollback (forberedt, ikke brukt)

- **Rollback-slice** (`super`-sektor 0–1 837 000 fra den verifiserte backupen = original LP-metadata + original system-region; hash-sjekket mot enheten) skrives tilbake til LBA `0x150c00` (maskrom + RKDevTool, eller `dd` fra Android hvis den kommer opp). Original `system` blir da gyldig igjen sammen med original metadata.
- Extent B ligger i tidligere ledig plass, så det trengs ikke å gjenopprettes.
- Det som **ikke** kan rulles tilbake slik: `scratch`-overlayen som skjulte Mentra på original Android 10 (overskrevet). Etter rollback til original Android 10 må Mentra-skjulingen gjøres på nytt (kapittel 5).
- Full backup av hele eMMC finnes som siste utvei (`wl 0 eMMC_full_backup.img`).

---

## 12. Resultat

Verifisert på det permanente systemet (to oppstarter, den siste uten datasletting):

- Rot-fs er `dm-0` = LP-partisjonen `system` (4 869 440 sektorer), `vendor`/`odm` fra speilet, `/data` er den ekte `userdata` (ext4). `gsi_tool status` = «normal» (ingen DSU).
- `ro.build.version.release=13`, SDK 33, `sys.boot_completed=1` ca. **66 s** etter oppstart. Ingen kjernefeil, ingen tombstones/ANR.
- `/dev/mpp_service` er `c---------` (blokkert); `tw_daemon`-tjenesten kjører fra init; skjermtidsavbrudd 60000 ms.
- Skjerm av → syntetisk berøring → **skjermen våkner** (med patchet vaktbikkje).
- Ingen Mentra-pakker, ingen device owner.
- Aurora Store sideloadet; speilet er på Wi-Fi (satt opp av eier på skjermen – vi taster aldri inn passord for eier).

---

## 13. Begrensninger, risiko og sikkerhet (vær ærlig mot deg selv)

- **ADB er root og uten autentisering** (`ro.adb.secure=0`). Det er bevisst (ingen fysisk adgang til USB når speilet henger på veggen), men betyr at **trådløs feilsøking på et nett du ikke kontrollerer, er en åpen dør**. Slå den av når du er ferdig.
- **SELinux er i praksis av** (alle typer permissive). Bruk ikke dette til noe sikkerhetskritisk.
- **Ulåst bootloader** (`orange`), `vbmeta` uten verifisering. Ingen verified boot.
- **Ingen OTA.** Oppdatering av systemet = ny GSI + ny skriving. Sikkerhetsoppdateringene er de samme som den GSI-en du lastet.
- **Ingen GMS.** Ingen Play Store, ingen YouTube-app, ingen Google-pålogging; Aurora bruker anonym konto og kan bli rate-begrenset.
- **Vendor er fortsatt Android 10**, og vil forbli det. Det kan dukke opp ukjente HAL-problemer (kamera, lyd/mikrofon er ikke testet grundig her).
- **Boot-logoen** (U-Boot + kjerne) ligger i `boot`-partisjonens ressursbilde og er byttet ut med en egen «Magic Mirror»-logo (10.2). Den som tester dette på en annen enhet bør regne med at bilde-orientering/plassering kan avvike.
- Bytte av maskinvare (annen panel-/touch-variant) kan gjøre at partisjonene/oppsettet ikke passer; **les din egen partisjonstabell**.

### Ikke verifisert / uavklart

- Ekte fingertrykk på det *ferdige* systemet vekker skjermen (testet syntetisk, og tidligere manuelt på DSU-gjesten bare med tastatur).
- Hvorfor Android 12 hang ved oppstart (vi gikk videre til 13).
- Om `/data/local/chrome-command-line` leses av Chrome på «user»-bygg (blokkering av `/dev/mpp_service` er det som sikrer fallback).
- Lyd/mikrofon er ikke gjennomtestet etter bytte til A13. **Kamera virker** (webkamera via ekstern HAL, VPU-JPEG-dekoding), etter rettelsen i 9.1.
- Rollback-slicen er hash-sjekket, men ikke skrevet tilbake.

---

## 14. Feil og korrigerte antakelser – oppsummert

1. «Wipe av userdata fjerner låsen» → nei, Mentra re-provisjonerer fra `/odm`.
2. «`rkdeveloptool` + `usbipd` fungerer» → nei, hang. Bruk RKDevTool v2.86.
3. Fullføringsdeteksjon i backup-løkke via logg-antall → RKDevTool tømmer loggen; bruk *Success* + filstørrelse.
4. PowerShell-kvotering av komplekse `adb shell`-kommandoer → skriv `.sh`-filer og `adb push`.
5. Første `mke2fs` til 2304 MB var for lite → 3072 MB.
6. WSL2-VM stenger og dropper loop-mounts → hold den i live og mount i skriptet.
7. `init` krever `seclabel` på services selv med permissive SELinux.
8. IDC `touch.wake` virker ikke her → egen watcher.
9. Vi tolket manuelle berøringer som «ekte test» → eier påpekte at *de* hadde trykket; bare tastaturet vekket.
10. Watcheren ignorerte `Dozing` → test «ikke Awake».
11. Tilfeldig `service call dynamic_system 5` slettet en DSU-installasjon.
12. «Vi må bygge en egen `product`-partisjon og beholde `scratch`» → unødvendig: GSI-en hopper over `product`, og A13 ser ikke Mentra.
13. «A13 på A10-vendor gir dårlig video fordi maskinen er svak» → delvis; stor del er dekodermismatch + kjernebug.
14. «Å blokkere VPU-noden for alle er trygt» → nei: webkameraets MJPEG-dekoding bruker samme VPU. Resultat: grønt kamerabilde.
15. Første rettelse brukte *gruppe* `cameraserver`; prosessen har en annen primærgruppe. Bruk *eierskap* (bruker) i stedet, og test etter kaldoppstart – ikke bare med en midlertidig `chown` som tilfeldigvis dekket det.
16. `su <uid>` finnes ikke i denne bygget (adb kjører som root direkte) – tilgangstest per bruker må gjøres på andre måter, eller utledes av eier/modus.
17. PowerShell + `adb shell "..."` med innebygde `$(…)`/anførselstegn feilet igjen (tredje gang): skriv alltid skriptet som `.sh`.
18. Boot-logoen ble først skrevet oppreist og vistes 90° feil → rotér bitmapet 90° med klokka (se 10.2).
19. Et søkefelt i launcheren ble forsøkt fjernet med lang-trykk/dra (virket ikke: det er launcherens innebygde søkeboks, ikke en vanlig widget). Forsøkt løsning: slå av søke-appen `com.android.quicksearchbox` (`pm disable-user --user 0`). **Dette fjernet ikke feltet** – etter omstart av launcheren vises en tom «Søk»-boks fortsatt øverst på startskjermen. Uløst (se `docs/taskbar-volume-button.md`). Samtidig kom `input`-trykk i veien for eierens egen bruk av skjermen – ikke styr UI mens noen holder på.

---

## Vedlegg A – LP-metadata-verktøy (Python 3, `lp_tool.py`)

Bruk: `python3 lp_tool.py dump <super_første_MiB.bin>` og  
`python3 lp_tool.py build <original_første_MiB.bin> <ut.bin> --system-sectors <N> --extent-b-start <S>`.  
Valider alltid resultatet med enhetens egen `lpdump <ut.bin>` før du skriver noe.

```python
#!/usr/bin/env python3
"""Minimal liblp (Android dynamic partitions) metadata parser / rewriter for the SATS mirror super partition.
Usage:
  lp_tool.py dump  <super_head.bin>
  lp_tool.py build <stock_super_head.bin> <out.bin> --system-sectors N --extent-b-start S
"""
import hashlib, struct, sys

GEOM_FMT = '<II32sIII'              # magic, struct_size, checksum, metadata_max_size, slot_count, logical_block_size
GEOM_MAGIC = 0x616c4467
HDR_FMT = '<IHHI32sI32s'            # magic, major, minor, header_size, header_checksum, tables_size, tables_checksum
HDR_MAGIC = 0x414C5030
DESC_FMT = '<III'                   # offset, num_entries, entry_size
PART_FMT = '<36sIIII'               # name, attributes, first_extent_index, num_extents, group_index
EXT_FMT = '<QIQI'                   # num_sectors, target_type, target_data, target_source
GRP_FMT = '<36sIQ'                  # name, flags, maximum_size
BDEV_FMT = '<QIIQ36sI'              # first_logical_sector, alignment, alignment_offset, size, name, flags
RES = 4096
GSZ = 4096


def cstr(b):
    return b.split(b'\0', 1)[0].decode()


def parse_geometry(buf, off):
    magic, ssz, ck, max_size, slots, lbs = struct.unpack_from(GEOM_FMT, buf, off)
    assert magic == GEOM_MAGIC, hex(magic)
    raw = bytearray(buf[off:off + ssz]); raw[8:40] = b'\0' * 32
    assert hashlib.sha256(raw).digest() == ck, 'geometry checksum'
    return dict(struct_size=ssz, max_size=max_size, slots=slots, lbs=lbs)


def parse_metadata(buf, off):
    magic, major, minor, hsz, hck, tsz, tck = struct.unpack_from(HDR_FMT, buf, off)
    assert magic == HDR_MAGIC, hex(magic)
    hdr = bytearray(buf[off:off + hsz]); hdr[12:44] = b'\0' * 32
    assert hashlib.sha256(hdr).digest() == hck, 'header checksum'
    p = off + struct.calcsize(HDR_FMT)
    descs = []
    for _ in range(4):
        descs.append(struct.unpack_from(DESC_FMT, buf, p)); p += 12
    flags = struct.unpack_from('<I', buf, p)[0] if hsz >= p - off + 4 else 0
    tables = bytes(buf[off + hsz: off + hsz + tsz])
    assert hashlib.sha256(tables).digest() == tck, 'tables checksum'
    def ents(d, fmt):
        o, n, sz = d
        assert sz == struct.calcsize(fmt), (sz, fmt)
        return [struct.unpack_from(fmt, tables, o + i * sz) for i in range(n)]
    parts = [dict(name=cstr(a), attr=b, first=c, n=d, group=e) for a, b, c, d, e in ents(descs[0], PART_FMT)]
    exts = [dict(sectors=a, ttype=b, data=c, src=d) for a, b, c, d in ents(descs[1], EXT_FMT)]
    grps = [dict(name=cstr(a), flags=b, max=c) for a, b, c in ents(descs[2], GRP_FMT)]
    bdevs = [dict(first=a, align=b, align_off=c, size=d, name=cstr(e), flags=f) for a, b, c, d, e, f in ents(descs[3], BDEV_FMT)]
    return dict(major=major, minor=minor, hsz=hsz, flags=flags, parts=parts, exts=exts, grps=grps, bdevs=bdevs,
                raw_header=bytes(buf[off:off + hsz]))


def read_all(path):
    buf = open(path, 'rb').read()
    g = parse_geometry(buf, RES)
    g2 = parse_geometry(buf, RES + GSZ)
    assert g == g2, 'primary/backup geometry differ'
    prim = RES + 2 * GSZ
    back = prim + g['max_size'] * g['slots']
    slots = []
    for s in range(g['slots']):
        a = parse_metadata(buf, prim + s * g['max_size'])
        try:
            b = parse_metadata(buf, back + s * g['max_size'])
        except AssertionError as e:
            b = None
        slots.append((a, b))
    return buf, g, slots


def dump(path):
    buf, g, slots = read_all(path)
    print(f'geometry: {g}')
    for s, (a, b) in enumerate(slots):
        print(f'--- slot {s}: v{a["major"]}.{a["minor"]} header_size={a["hsz"]} flags={a["flags"]} backup_equal={b is not None and a["parts"]==b["parts"] and a["exts"]==b["exts"]}')
        for bd in a['bdevs']: print('  block device', bd)
        for gr in a['grps']: print('  group', gr)
        tot = 0
        for p in a['parts']:
            es = a['exts'][p['first']:p['first'] + p['n']]
            sec = sum(e['sectors'] for e in es); tot += sec
            print(f'  part {p["name"]:10s} attr={p["attr"]} group={p["group"]} sectors={sec} ({sec*512/1048576:.1f} MiB)')
            for e in es: print(f'      extent {e["sectors"]:>9d} sectors  type={e["ttype"]} phys_sector={e["data"]} dev={e["src"]}')
        print('  total partition sectors', tot)


def pack_tables(parts, exts, grps, bdevs):
    pt = b''.join(struct.pack(PART_FMT, p['name'].encode().ljust(36, b'\0'), p['attr'], p['first'], p['n'], p['group']) for p in parts)
    et = b''.join(struct.pack(EXT_FMT, e['sectors'], e['ttype'], e['data'], e['src']) for e in exts)
    gt = b''.join(struct.pack(GRP_FMT, g['name'].encode().ljust(36, b'\0'), g['flags'], g['max']) for g in grps)
    bt = b''.join(struct.pack(BDEV_FMT, d['first'], d['align'], d['align_off'], d['size'], d['name'].encode().ljust(36, b'\0'), d['flags']) for d in bdevs)
    offs = []; o = 0
    for t in (pt, et, gt, bt): offs.append(o); o += len(t)
    tables = pt + et + gt + bt
    descs = [(offs[0], len(parts), struct.calcsize(PART_FMT)), (offs[1], len(exts), struct.calcsize(EXT_FMT)),
             (offs[2], len(grps), struct.calcsize(GRP_FMT)), (offs[3], len(bdevs), struct.calcsize(BDEV_FMT))]
    return tables, descs


def build(stock_path, out_path, system_sectors, b_start):
    buf, g, slots = read_all(stock_path)
    a, _ = slots[0]
    assert a['major'] == 10
    bdev = a['bdevs'][0]
    byname = {p['name']: p for p in a['parts']}
    assert set(byname) >= {'system', 'vendor', 'product', 'odm'}, list(byname)
    sys_ext = a['exts'][byname['system']['first']:byname['system']['first'] + byname['system']['n']]
    assert len(sys_ext) == 1 and sys_ext[0]['ttype'] == 0
    A = sys_ext[0]
    extB_sectors = system_sectors - A['sectors']
    assert extB_sectors > 0 and extB_sectors % 8 == 0 and b_start % 8 == 0
    dev_sectors = bdev['size'] // 512
    assert b_start + extB_sectors <= dev_sectors, 'extent B beyond super'
    # B must not overlap any other partition extent
    others = []
    for n in ('vendor', 'product', 'odm'):
        p = byname[n]
        for e in a['exts'][p['first']:p['first'] + p['n']]:
            others.append((e['data'], e['data'] + e['sectors'], n))
    for lo, hi, n in others:
        assert b_start >= hi or b_start + extB_sectors <= lo, f'extent B overlaps {n}'
    new_parts, new_exts = [], []
    for name in ('system', 'vendor', 'product', 'odm'):
        p = dict(byname[name])
        es = [dict(e) for e in a['exts'][p['first']:p['first'] + p['n']]]
        if name == 'system':
            es.append(dict(sectors=extB_sectors, ttype=0, data=b_start, src=A['src']))
        p['first'] = len(new_exts); p['n'] = len(es)
        new_exts += es; new_parts.append(p)
    grp = a['grps'][1] if len(a['grps']) > 1 else a['grps'][0]
    total = sum(e['sectors'] for e in new_exts)
    gi = new_parts[0]['group']
    assert total * 512 <= a['grps'][gi]['max'], f'group max exceeded: {total*512} > {a["grps"][gi]["max"]}'
    tables, descs = pack_tables(new_parts, new_exts, a['grps'], a['bdevs'])
    # header: keep stock header layout (version, header_size, flags), recompute descriptors/size/checksums
    hsz = a['hsz']
    hdr = bytearray(a['raw_header'])
    struct.pack_into('<I', hdr, 44, len(tables))
    struct.pack_into('<32s', hdr, 48, hashlib.sha256(tables).digest())
    p = 80
    for d in descs:
        struct.pack_into(DESC_FMT, hdr, p, *d); p += 12
    hdr[12:44] = b'\0' * 32
    struct.pack_into('<32s', hdr, 12, hashlib.sha256(bytes(hdr)).digest())
    blob = bytes(hdr) + tables
    assert len(blob) <= g['max_size'], 'metadata does not fit'
    out = bytearray(buf)
    prim = RES + 2 * GSZ
    back = prim + g['max_size'] * g['slots']
    pad = blob + b'\0' * (g['max_size'] - len(blob))
    out[prim:prim + g['max_size']] = pad            # slot 0 primary
    out[back:back + g['max_size']] = pad            # slot 0 backup
    open(out_path, 'wb').write(bytes(out))
    print(f'built {out_path}: system {system_sectors} sectors = A {A["sectors"]}@{A["data"]} + B {extB_sectors}@{b_start}; '
          f'group total {total} sectors ({total*512/1048576:.1f} MiB) of max {a["grps"][gi]["max"]/1048576:.1f} MiB; blob {len(blob)} of {g["max_size"]} bytes')


if __name__ == '__main__':
    if sys.argv[1] == 'dump':
        dump(sys.argv[2])
    elif sys.argv[1] == 'build':
        args = dict(zip(sys.argv[4::2], sys.argv[5::2]))
        build(sys.argv[2], sys.argv[3], int(args['--system-sectors']), int(args['--extent-b-start']))
```

## Vedlegg B – init-rc og hjelpeskript

`/system/etc/init/zz_dbg.rc`:

```
# SATS mirror (RK3399, vendor Android 10 + Android 13 GSI): diagnostics, hardware-decoder block, touch-to-wake, defaults
on early-init
    mkdir /metadata/dbg 0777 root system
    start dbg_log

on property:logd.ready=true
    start dbg_logcat

# The vendor VPU driver (rkvdec/mpp, kernel 4.19) page-faults the whole kernel on VP9 and renders garbage with the
# Android 13 framework: keep media codecs out. Only the camera provider (webcam MJPEG decode) may open the node.
on boot
    chmod 0600 /dev/mpp_service
    chown cameraserver root /dev/mpp_service

on property:sys.boot_completed=1
    start mirror_setup
    start tw_daemon

service dbg_log /system/bin/sh /system/etc/dbg_log.sh
    user root
    group root system log shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service dbg_logcat /system/bin/logcat -b all -v threadtime -f /metadata/dbg/logcat.txt -r 1024 -n 3
    user root
    group root system log shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service mirror_setup /system/bin/sh /system/etc/mirror_setup.sh
    user root
    group root system shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service tw_daemon /system/bin/sh /system/etc/tw_daemon.sh
    user root
    group root input shell
    seclabel u:r:shell:s0
    disabled
```

`/system/etc/mirror_setup.sh`:

```sh
#!/system/bin/sh
# runs once per boot after boot_completed (idempotent)
chmod 0600 /dev/mpp_service 2>/dev/null
mkdir -p /data/local 2>/dev/null
echo '_ --disable-accelerated-video-decode' > /data/local/chrome-command-line
chmod 0644 /data/local/chrome-command-line
F=/data/local/.mirror_defaults_done
if [ ! -e $F ]; then
  settings put system screen_off_timeout 60000
  settings put global stay_on_while_plugged_in 0
  cmd lock_settings set-disabled true >/dev/null 2>&1
  touch $F
fi
# local tuning hook (editable over adb, no reflash): GPU/CPU frequencies etc.
[ -f /data/local/mirror_local.sh ] && sh /data/local/mirror_local.sh
# stop the boot-time log capture after 10 minutes (avoids constant flash writes)
sleep 600
stop dbg_logcat
```

(Den *installerte* utgaven er en komprimert variant av dette uten kommentarer, polstret til samme filstørrelse – se 10.1.)

`/data/local/mirror_local.sh` (eksempel, det vi bruker):

```sh
echo 400000000 > /sys/class/devfreq/ff9a0000.gpu/min_freq
echo 816000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
echo 816000 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
```

`dbg_log.sh` (kort): loggfører `dmesg`/`getprop` til `/metadata/dbg` de første ~10 minuttene, og har en vaktbikkje: hvis `sys.boot_completed` ikke er 1 etter 420 s, lagres tilstand og enheten starter på nytt – **maks to ganger på rad**, deretter holder den seg unna (en evig omstartsløkke på en permanent installasjon er verre enn et hengt system).

## Vedlegg C – skriveskript (fra kjørende DSU-gjest)

```sh
#!/system/bin/sh
# STAGE 1 of the permanent Android 13 install: write system extents into super and verify them by hash.
# Order: extent B (free tail) first, then extent A (the old stock system region). LP metadata is written in stage 2.
SUPER=/dev/block/by-name/super
IMG=/data/local/tmp/system_final.img
LOG=/data/local/tmp/flash-stage1.log
exec > $LOG 2>&1
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "ABORT: $*"; echo "STAGE1_FAILED" ; exit 1; }

EXP_IMG=40ad372086fe195334988d7b892a6c3d56ffb75ede22a912e5ae808450aeabd4
EXP_A=8f836b60c3f1fac12e628c816e55c10ab0ea3fec91ee53e91ab240b76dacd3dd
EXP_B=5958c46d7f00501905443740846fef0c049be4370f299b3b181a2caf4a9d7bae
EXP_HEAD_LIVE=1114605a4e2ec83a24666ec799602f106686f4d956e9c0d68c37a512aa8b37e7

say "pre-checks"
[ "$(sha256sum $IMG | cut -d' ' -f1)" = "$EXP_IMG" ] || die "image hash mismatch"
[ "$(dd if=$SUPER bs=4096 count=256 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$EXP_HEAD_LIVE" ] || die "live LP metadata is not what I expected"
[ "$(blockdev --getsize64 $SUPER)" = "3263168512" ] || die "super size unexpected"
say "pre-checks ok"

say "WRITE extent B: image 4K-blocks 229369..608679 -> super 4K-block 366336 (sector 2930688), 379311 blocks"
dd if=$IMG of=$SUPER bs=4096 skip=229369 seek=366336 count=379311 || die "dd B failed"
sync
echo 3 > /proc/sys/vm/drop_caches
H=$(dd if=$SUPER bs=4096 skip=366336 count=379311 2>/dev/null | sha256sum | cut -d' ' -f1)
say "extent B readback: $H"
[ "$H" = "$EXP_B" ] || die "extent B verify FAILED"
say "extent B verified"

say "WRITE extent A: image 4K-blocks 0..229368 -> super 4K-block 256 (sector 2048), 229369 blocks  [stock system is overwritten from here]"
dd if=$IMG of=$SUPER bs=4096 skip=0 seek=256 count=229369 || die "dd A failed"
sync
echo 3 > /proc/sys/vm/drop_caches
H=$(dd if=$SUPER bs=4096 skip=256 count=229369 2>/dev/null | sha256sum | cut -d' ' -f1)
say "extent A readback: $H"
[ "$H" = "$EXP_A" ] || die "extent A verify FAILED"
say "extent A verified"

say "dm-linear mapping test with the NEW layout (what first-stage init will build from the metadata)"
dmctl delete sysnew >/dev/null 2>&1
dmctl create sysnew -ro linear 0 1834952 $SUPER 2048 linear 1834952 3034488 $SUPER 2930688 || die "dmctl create failed"
P=$(dmctl getpath sysnew); say "mapped at $P"
echo 3 > /proc/sys/vm/drop_caches
H=$(sha256sum $P | cut -d' ' -f1)
say "mapped device sha256: $H"
[ "$H" = "$EXP_IMG" ] || { dmctl delete sysnew; die "mapped device hash mismatch"; }
mkdir -p /mnt/sysnew
mount -t ext4 -o ro $P /mnt/sysnew && { say "mounted ro OK:"; ls /mnt/sysnew | tr '\n' ' '; echo; ls /mnt/sysnew/system | head -5 | tr '\n' ' '; echo; grep -E '^ro.build.version.release=' /mnt/sysnew/system/build.prop; umount /mnt/sysnew; } || say "WARN: ro mount test failed"
dmctl delete sysnew
say "STAGE1_OK"
echo STAGE1_OK
```

Metadata ble skrevet i et eget kort skript (`dd` av de første 1 MiB, hash-sjekk, `lpdump`).

---

*Rapporten er skrevet etter at jobben var ferdig. Alle tall, hasher og utskrifter over er hentet fra loggene til selve kjøringen. Delene merket «ikke verifisert» er ærlig ment.*
