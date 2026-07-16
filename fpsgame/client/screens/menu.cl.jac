"""Main menu screen: play, settings, high score."""

# ── Main menu ──────────────────────────────────────────────────────────────
def:pub Menu(onPlay: any, onSettings: any, highScore: int) -> JsxElement {
    return
        <div className="screen menu">
            <div className="logo">
                {"JAC "}
                <span className="accent">FPS</span>
            </div>
            <div className="tag">{"Phase 2 - single player"}</div>
            <button className="btn primary big" onClick={onPlay}>Play</button>
            <button className="btn big" onClick={onSettings}>Settings</button>
            <div className="hs">
                {"High score "}
                <b>{highScore}</b>
            </div>
            <div className="ver">v0.2.0</div>
        </div>;
}
