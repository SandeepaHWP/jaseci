"""React HUD overlay: health, ammo, score, crosshair, kill feed, death overlay."""

import from .guns { GUN_NAMES }

# ── React HUD overlay (driven by the shim each frame via window.__fps_hud) ──
def:pub Hud -> JsxElement {
    has hp: int = 100,
        mag: int = 30,
        ammo: int = 90,
        kills: int = 0,
        deaths: int = 0,
        fps: int = 0,
        hit: bool = False,
        alive: bool = True,
        reloading: bool = False,
        low: bool = False,
        vig: int = 0,
        gun: int = 1,
        tleft: int = 0,
        mode: int = 0,
        prompt: int = -1,
        feed: list = [];

    can with entry {
        w: any = window;
        # The shim's on_tick pushes already-converted values here each frame.
        # This lambda only WRITES state (never reads it), so there is no React
        # stale-closure hazard; the diff logic lives in on_tick instead.
        w.__fps_hud = lambda (
            nhp: int,
            nmag: int,
            nammo: int,
            nkills: int,
            ndeaths: int,
            nfps: int,
            nhit: bool,
            nalive: bool,
            nreload: bool,
            nlow: bool,
            nvig: int,
            ngun: int,
            ntleft: int,
            nmode: int,
            nprompt: int,
            nfeed: list
        ) {
            hp = nhp;
            mag = nmag;
            ammo = nammo;
            kills = nkills;
            deaths = ndeaths;
            fps = nfps;
            hit = nhit;
            alive = nalive;
            reloading = nreload;
            low = nlow;
            vig = nvig;
            gun = ngun;
            tleft = ntleft;
            mode = nmode;
            prompt = nprompt;
            feed = nfeed;
        };
    }
    hpw: str = f"{hp}%";
    ammo_txt: str = "RELOADING" if reloading else f"{mag} / {ammo}";
    gun_txt: str = f"{GUN_NAMES[gun]}" if gun >= 0 and gun < 5 else "?";
    # mm:ss for the time-attack clock; ffa (mode 0) has no clock to show
    mins: int = tleft // 60;
    secs: int = tleft % 60;
    clock_txt: str = f"{mins}:0{secs}" if secs < 10 else f"{mins}:{secs}";
    # prompt is the gun id F would swap to, or -1 when nothing is in reach
    swap_txt: str = f"[F] Swap for {GUN_NAMES[prompt]}"
        if prompt >= 0 and prompt < 5
        else "";
    return
        <div id="hud-root">
            <div id="cross" className={"hot" if hit else ""}></div>
            {(<div id="hitmark">✕</div>) if hit else None}
            {(<div id="vignette" key={f"v{vig}"}></div>) if vig > 0 else None}
            <div id="feed">
                {for item in feed {
                    <div className="feeditem" key={item}>{item}</div>
                }}
            </div>
            {(
                <div id="clock" className={"low" if tleft <= 10 else ""}>
                    {clock_txt}
                </div>
            )
                if mode == 1
                else None}
            {(<div id="prompt">{swap_txt}</div>) if prompt >= 0 else None}
            <div id="stat">
                {"score "}
                <b>{kills}</b>
                {" · K/D "}
                <b>{kills}</b>
                {" / "}
                <b>{deaths}</b>
                {" · "}
                <b>{fps}</b>
                {" fps"}
            </div>
            <div id="hud">
                <div id="hpbar">
                    <div id="hpfill" style={{"width": hpw}}></div>
                </div>
                <div id="gun">{gun_txt}</div>
                <div id="ammo" className={"low" if (low or reloading) else ""}>
                    {ammo_txt}
                </div>
            </div>
            {(
                <div id="death">
                    <div>You Died</div>
                </div>
            )
                if not alive
                else None}
        </div>;
}
