"""Round summary screen: kills, deaths, time, play again / menu."""

# ── Round summary ──────────────────────────────────────────────────────────
def:pub GameOver(
    won: bool, kills: int, deaths: int, timeSec: int, onPlayAgain: any, onMenu: any
) -> JsxElement {
    return
        <div className="screen">
            <div className={"logo win" if won else "logo lose"}>
                {"Victory" if won else "You Died"}
            </div>
            <div className="stats">
                <div className="stat">
                    <b>{kills}</b>
                    <span>kills</span>
                </div>
                <div className="stat">
                    <b>{deaths}</b>
                    <span>deaths</span>
                </div>
                <div className="stat">
                    <b>{timeSec}</b>
                    <span>seconds</span>
                </div>
            </div>
            <div className="btnrow">
                <button className="btn primary big" onClick={onPlayAgain}>
                    Play Again
                </button>
                <button className="btn big" onClick={onMenu}>Menu</button>
            </div>
        </div>;
}
