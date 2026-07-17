"""Main menu screen: mode select, play, settings, high score."""

# ── Main menu ──────────────────────────────────────────────────────────────
def:pub Menu(
    onPlay: any, onSettings: any, highScore: int, mode: int, onMode: any
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
            <button className="btn primary big" onClick={onPlay}>Play</button>
            <button className="btn big" onClick={onSettings}>Settings</button>
            <div className="hs">
                {"High score "}
                <b>{highScore}</b>
            </div>
            <div className="ver">v0.2.0</div>
        </div>;
}
