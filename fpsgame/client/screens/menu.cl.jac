"""Main menu screen: mode + loadout select, play, settings, high score."""

import from ..guns { GUN_NAMES, GUN_BLURBS }

# ── Main menu ──────────────────────────────────────────────────────────────
def:pub Menu(
    onPlay: any,
    onSettings: any,
    highScore: int,
    mode: int,
    onMode: any,
    loadout: int,
    onLoadout: any
) -> JsxElement {
    return
        <div className="screen menu">
            <div className="logo">
                {"JAC "}
                <span className="accent">FPS</span>
            </div>
            <div className="tag">{"Phase 3 - single player"}</div>
            <div className="row modes">
                <button
                    className={"chip on" if mode == 0 else "chip"}
                    onClick={lambda { onMode(0); }}
                >
                    Free-for-all
                </button>
                <button
                    className={"chip on" if mode == 1 else "chip"}
                    onClick={lambda { onMode(1); }}
                >
                    Time Attack
                </button>
            </div>
            <div className="note">
                {"Reach the score target. Time Attack gives you 60 seconds."
                    if mode == 1
                    else "Reach the score target. No clock."}
            </div>
            <div className="loadout">
                <div className="lolabel">Loadout</div>
                <div className="row guns">
                    <button
                        className={"chip on" if loadout == 0 else "chip"}
                        onClick={lambda { onLoadout(0); }}
                    >
                        {GUN_NAMES[0]}
                    </button>
                    <button
                        className={"chip on" if loadout == 1 else "chip"}
                        onClick={lambda { onLoadout(1); }}
                    >
                        {GUN_NAMES[1]}
                    </button>
                    <button
                        className={"chip on" if loadout == 2 else "chip"}
                        onClick={lambda { onLoadout(2); }}
                    >
                        {GUN_NAMES[2]}
                    </button>
                    <button
                        className={"chip on" if loadout == 3 else "chip"}
                        onClick={lambda { onLoadout(3); }}
                    >
                        {GUN_NAMES[3]}
                    </button>
                    <button
                        className={"chip on" if loadout == 4 else "chip"}
                        onClick={lambda { onLoadout(4); }}
                    >
                        {GUN_NAMES[4]}
                    </button>
                </div>
                <div className="note">{GUN_BLURBS[loadout]}</div>
            </div>
            <button className="btn primary big" onClick={onPlay}>Play</button>
            <button className="btn big" onClick={onSettings}>Settings</button>
            <div className="hs">
                {"High score "}
                <b>{highScore}</b>
            </div>
            <div className="ver">v0.2.0</div>
        </div>;
}
