"""App stylesheet + the global [fps] error hook, injected once."""

"""Inject the app stylesheet once (idempotent via the element id)."""
def:pub ensure_styles {
    # Global error hook: the jac runtime's error reporter masks the real
    # error (it reads .message of an undefined). Capture the genuine error +
    # stack here, prefixed [fps], before the reporter runs. Installed once.
    ew: any = window;
    if not ew.__fps_errhook {
        ew.__fps_errhook = True;
        ew.addEventListener(
            "error",
            lambda (e: any) { console.log(
                "[fps] ERROR:", e.message, "@", e.filename, e.lineno, e.error
            ); }
        );
        ew.addEventListener(
            "unhandledrejection",
            lambda (e: any) { console.log("[fps] REJECTION:", e.reason); }
        );
    }
    existing: any = document.getElementById("fps-styles");
    if existing {
        return;
    }
    css = """
    body { margin: 0; background: #0b0e16; overflow: hidden; }
    #page { min-height: 100vh; box-sizing: border-box; color: #cdd6e6;
            font: 13px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace;
            display: flex; flex-direction: column; align-items: center;
            justify-content: center; gap: 8px; padding: 12px; }
    .screen { display: flex; flex-direction: column; align-items: center;
              gap: 14px; padding: 28px 40px; background: #0f121c;
              border: 1px solid #232a3d; border-radius: 12px; min-width: 360px; }
    .logo { font-size: 44px; font-weight: 800; letter-spacing: 2px; color: #e8f0ff; }
    .logo .accent { color: #f5c451; }
    .logo.win { color: #6ee7a8; } .logo.lose { color: #ff6b6b; }
    .tag, .ver, .note { opacity: 0.6; font-size: 12px; }
    .hs { margin-top: 6px; } .hs b, .logo .accent { color: #f5c451; }
    .btn { font: inherit; cursor: pointer; padding: 10px 22px; border-radius: 8px;
           border: 1px solid #2c3550; background: #161b2b; color: #cdd6e6; }
    .btn:hover { border-color: #3a4566; background: #1c2336; }
    .btn.primary { background: #f5c451; color: #1a1205; border-color: #f5c451; font-weight: 700; }
    .btn.big { font-size: 16px; padding: 12px 30px; min-width: 200px; }
    .btnrow { display: flex; gap: 10px; margin-top: 8px; }
    .row { display: flex; align-items: center; gap: 12px; width: 360px; }
    .row > span:first-child { width: 120px; } .row b { width: 36px; text-align: right; color: #f5c451; }
    .row input[type=range] { flex: 1; }
    .chip { font: inherit; cursor: pointer; padding: 5px 14px; border-radius: 6px;
            border: 1px solid #2c3550; background: #161b2b; color: #cdd6e6; }
    .chip.on { background: #f5c451; color: #1a1205; border-color: #f5c451; }
    .stats { display: flex; gap: 26px; margin: 6px 0; }
    .stat { display: flex; flex-direction: column; align-items: center; }
    .stat b { font-size: 30px; color: #f5c451; } .stat span { opacity: 0.6; font-size: 12px; }
    #wrap { position: relative; }
    #glcanvas { background: #0f121c; border: 1px solid #232a3d;
                border-radius: 6px; display: block; cursor: crosshair; }
    #cross { position: absolute; left: 50%; top: 50%; width: 18px; height: 18px;
             transform: translate(-50%, -50%); pointer-events: none; }
    #cross::before, #cross::after { content: ""; position: absolute;
             background: #e8f0ff; opacity: 0.85; }
    #cross::before { left: 50%; top: 0; width: 2px; height: 100%; transform: translateX(-50%); }
    #cross::after { top: 50%; left: 0; height: 2px; width: 100%; transform: translateY(-50%); }
    #hud { position: absolute; left: 12px; bottom: 10px; pointer-events: none;
           text-shadow: 0 1px 2px #000; font-size: 15px; }
    #hud b { color: #f5c451; }
    #stat { position: absolute; right: 12px; top: 10px; text-align: right;
            pointer-events: none; text-shadow: 0 1px 2px #000; }
    #hitmark { position: absolute; left: 50%; top: 50%; transform: translate(-50%,-50%);
               color: #ff5a5a; font-size: 22px; font-weight: 700; opacity: 0;
               pointer-events: none; transition: opacity 0.08s; }
    #hint { position: absolute; left: 50%; top: -26px; transform: translateX(-50%);
            white-space: nowrap; opacity: 0.6; }
    #hud-root { position: absolute; inset: 0; pointer-events: none; overflow: hidden;
                border-radius: 6px; }
    #cross.hot::before, #cross.hot::after { background: #ff5a5a; opacity: 1; }
    #feed { position: absolute; left: 12px; top: 36px; display: flex;
            flex-direction: column; gap: 3px; align-items: flex-start; }
    .feeditem { background: rgba(0,0,0,0.45); padding: 2px 9px; border-radius: 4px;
                font-size: 12px; color: #e8f0ff; animation: feedin 0.15s ease-out; }
    @keyframes feedin { from { opacity: 0; transform: translateX(-8px); } to { opacity: 1; } }
    #hpbar { width: 170px; height: 11px; background: rgba(255,255,255,0.14);
             border-radius: 6px; overflow: hidden; margin-bottom: 5px; }
    #hpfill { height: 100%; background: linear-gradient(90deg, #ff5a5a, #f5c451, #6ee7a8);
              transition: width 0.12s linear; }
    #ammo { font-size: 18px; font-weight: 700; color: #e8f0ff;
            text-shadow: 0 1px 2px #000; }
    #ammo.low { color: #ff6b6b; }
    #gun { font-size: 12px; letter-spacing: 1px; text-transform: uppercase;
           color: #f5c451; opacity: 0.85; margin-bottom: 1px; }
    #clock { position: absolute; left: 50%; top: 10px; transform: translateX(-50%);
             font-size: 26px; font-weight: 700; color: #e8f0ff; pointer-events: none;
             text-shadow: 0 1px 3px #000; font-variant-numeric: tabular-nums; }
    #clock.low { color: #ff6b6b; }
    #prompt { position: absolute; left: 50%; top: 58%; transform: translateX(-50%);
              white-space: nowrap; pointer-events: none; font-size: 14px;
              color: #e8f0ff; background: rgba(0,0,0,0.5); padding: 4px 12px;
              border-radius: 6px; text-shadow: 0 1px 2px #000; }
    .row.modes, .row.guns { width: auto; justify-content: center; flex-wrap: wrap; }
    .loadout { display: flex; flex-direction: column; align-items: center; gap: 6px;
               padding: 10px 14px; border: 1px solid #232a3d; border-radius: 8px;
               background: #0c0f18; }
    .lolabel { font-size: 11px; letter-spacing: 1px; text-transform: uppercase;
               opacity: 0.55; }
    .loadout .note { max-width: 320px; text-align: center; }
    #vignette { position: absolute; inset: 0;
                box-shadow: inset 0 0 120px 36px rgba(190,20,20,0.6);
                animation: vignflash 0.45s ease-out forwards; }
    @keyframes vignflash { from { opacity: 1; } to { opacity: 0; } }
    #death { position: absolute; inset: 0; display: flex; align-items: center;
             justify-content: center; flex-direction: column; gap: 6px;
             background: rgba(120,12,12,0.32); color: #ffd7d7; font-size: 26px;
             font-weight: 700; }
    """;
    st: any = document.createElement("style");
    st.id = "fps-styles";
    st.textContent = css;
    head: any = document.head;
    head.appendChild(st);
}
