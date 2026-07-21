"""Settings screen: sensitivity, FOV, bots, score-to-win, map select."""

# ── Settings (sensitivity carried as a 1..60 percentage) ───────────────────
def:pub Settings(
    sens: int, fov: int, bots: int, mapId: int, target: int, onSave: any, onBack: any
) -> JsxElement {
    has s: int = 12,
        f: int = 90,
        b: int = 5,
        m: int = 0,
        t: int = 5;

    can with entry {
        s = sens;
        f = fov;
        b = bots;
        m = mapId;
        t = target;
    }
    return
        <div className="screen">
            <div className="logo" style={{"fontSize": "28px"}}>Settings</div>
            <div className="row">
                <span>Mouse sensitivity</span>
                <input
                    type="range"
                    min="1"
                    max="60"
                    value={str(s)}
                    onChange={lambda (e: ChangeEvent) {
                        v: str = e.target.value;
                        s = int(v);
                    }}
                />
                <b>{s}</b>
            </div>
            <div className="row">
                <span>FOV</span>
                <input
                    type="range"
                    min="60"
                    max="110"
                    value={str(f)}
                    onChange={lambda (e: ChangeEvent) {
                        v: str = e.target.value;
                        f = int(v);
                    }}
                />
                <b>{f}</b>
            </div>
            <div className="row">
                <span>Bots</span>
                <input
                    type="range"
                    min="1"
                    max="10"
                    value={str(b)}
                    onChange={lambda (e: ChangeEvent) {
                        v: str = e.target.value;
                        b = int(v);
                    }}
                />
                <b>{b}</b>
            </div>
            <div className="row">
                <span>Score to win</span>
                <input
                    type="range"
                    min="1"
                    max="20"
                    value={str(t)}
                    onChange={lambda (e: ChangeEvent) {
                        v: str = e.target.value;
                        t = int(v);
                    }}
                />
                <b>{t}</b>
            </div>
            <div className="row">
                <span>Map</span>
                <button
                    className={"chip on" if m == 0 else "chip"}
                    onClick={lambda { m = 0; }}
                >
                    Open
                </button>
                <button
                    className={"chip on" if m == 1 else "chip"}
                    onClick={lambda { m = 1; }}
                >
                    Cover
                </button>
            </div>
            <div className="note">
                {"Map + score-to-win apply now; sensitivity / FOV / bots are saved and wired into the sim in the next step."}
            </div>
            <div className="btnrow">
                <button
                    className="btn primary big"
                    onClick={lambda { onSave(s, f, b, m, t); }}
                >
                    Save
                </button>
                <button className="btn big" onClick={onBack}>Back</button>
            </div>
        </div>;
}
