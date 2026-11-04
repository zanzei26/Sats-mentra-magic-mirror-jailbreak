# Hurtigguide: fjern kiosk-låsen fra SATS Mentra Rflex (og behold Android 10)

Minimumsvarianten – bli kvitt **[FS] Launcher** (device owner / kiosk) og få vanlig Android 10. Vil du videre til Android 13 med appbutikk, speilfunksjon osv., se den fulle erfaringsrapporten.

> ⚠️ **Advarsel:** flere steg skriver direkte til eMMC. **Ta full backup først.** Partisjonsoffsets er enhetsspesifikke – les din egen enhet, ikke kopier tall blindt. Bruk på eget ansvar.

## Du trenger
- Windows-PC. **USB-2.0-hub** (viktig – maskrom feiler ofte på USB-3-porter med «device descriptor request failed»). En god USB-**datakabel**. Et tynt verktøy til maskrom-knappen.
- **RKDevTool v2.86** (v3.37 krasjer; sett `config.ini` til engelsk), **Rockchip DriverAssistant v5.14**, loaderen **`rk3399_loader_v1.30.130.bin`**, og `adb` (platform-tools).

## Steg
1. **Maskrom:** hold den recessed svarte knappen på baksiden inne mens du setter på strøm → svart skjerm. PC-en skal vise **«Rockusb Device»** (VID 2207, PID 330C). Installer DriverAssistant hvis Windows viser feil på enheten. Får du «descriptor failed», sett en **USB-2.0-hub** mellom PC og speil.
2. **Les partisjonstabellen** i RKDevTool v2.86 (*Advanced Function* → Read Flash Info / GPT). Finn `userdata` og `misc`.
3. **FULL eMMC-backup FØRST** (*Advanced Function* → *Export Image*, hele eMMC). Verifiser filstørrelse (sektorer × 512) + SHA-256, og **kopier backupen til et annet sted**. Ikke gå videre før dette er gjort.
4. **Fjern låsen – og merk fellen:** *bare å nullstille `userdata` holder IKKE.* [FS] Launcher (`com.mentra.launcher`) ligger på skrivebeskyttet **`/odm`** og setter seg selv opp som device owner igjen ved neste oppstart (bygget har root). Riktig fremgangsmåte:
   1. **Få ADB (root):** trigg en factory reset – skriv en bootloader_message til `misc` (`command = boot-recovery`, `recovery = recovery\n--wipe_data\n`) og `reboot recovery` (eller bruk RKDevTool til å slette `userdata`). Etter reset er `adb root` tilgjengelig på dette bygget.
   2. **Slett device-owner-filene:** fjern `/data/system/device_owner_2.xml` og `/data/system/device_policies.xml` (sjekk eksakte navn på din enhet), og merk `com.mentra.launcher` avinstallert for bruker 0 i `package-restrictions.xml`.
   3. **Skjul APK-en permanent:** `adb remount` lager en `scratch`-overlay i ledig `super`-plass. Lag en *whiteout* over `com.mentra.launcher` i `/odm`, så den ikke kan reinstalleres ved oppstart.
5. **Reboot.** Resultat: vanlig Android 10-launcher, ingen device owner, ingen kiosk.

## Sikkerhet / ikke-mur
- **Aldri** generell RK3399-firmware (panelinnstillingene ligger i speilets egen software → svart skjerm). **Aldri** EraseAll / skriv hele flashen. Rør ikke `uboot`/`trust`/`parameter`/`boot`.
- Backup + maskrom = i praksis ikke-murbar. Gjenoppretting: skriv hele backupen tilbake med `wl 0 eMMC_full_backup.img`.

---

*Basert på den fulle erfaringsrapporten (SATS Mentra Rflex, RK3399). For videre: permanent Android 13-GSI, Aurora Store, touch-to-wake og egen boot-logo – se full rapport.*
