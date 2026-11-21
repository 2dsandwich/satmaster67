import SwiftUI
import WebKit

/// The Desmos graphing calculator, as in Bluebook, loaded with the expressions that solve or check this question.
/// Needs the internet (Desmos runs from desmos.com).
struct DesmosView: NSViewRepresentable {
    let expressions: [String]
    var focus: String? = nil   // "(14,0)": drawn as a large labelled point, and the graph is centred on it

    // shortcut: Desmos's public demo key, meant for trying the API; a personal app key (free from desmos.com/api) should replace it.
    static let apiKey = "dcb31709b452b1cf9dc26972add0fda6"

    /// The two numbers of "(14,0)" or "(-2.5, 3)".
    static func point(_ s: String?) -> (Double, Double)? {
        guard let s, let m = s.firstMatch(of: #/\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)/#), let x = Double(m.1), let y = Double(m.2) else { return nil }
        return (x, y)
    }

    static func html(_ exprs: [String], focus: String? = nil) -> String {
        let list = (try? JSONSerialization.data(withJSONObject: exprs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var mark = ""
        if let f = focus, let (x, y) = point(f) {
            // Centre on the answer with room around it, in the panel's own proportions so nothing is squashed or cut.
            let span = max(6, abs(x) * 0.8, abs(y) * 0.8)
            mark = """
            calc.setExpression({id: 'answer', latex: '(\(x.formatted(.number.grouping(.never))),\(y.formatted(.number.grouping(.never))))', color: Desmos.Colors.ORANGE, pointSize: 18, label: 'Answer', showLabel: true, dragMode: Desmos.DragModes.NONE});
            const px = calc.graphpaperBounds.pixelCoordinates, r = px.height / Math.max(px.width, 1);   // the graph paper, not the list beside it: equal x and y units
            calc.setMathBounds({left: \(x) - \(span), right: \(x) + \(span), bottom: \(y) - \(span) * r, top: \(y) + \(span) * r});
            """
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body,#c{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#fff}</style>
        <script>
        // Any error before the graph is set up (offline, so no Desmos; a bad expression script) shows this instead of a white box.
        onerror = () => { if (!window.ready) document.body.innerHTML = '<p style="font:14px -apple-system;color:#666;text-align:center;margin-top:40%">Desmos needs the internet.</p>' };
        </script>
        <script src="https://www.desmos.com/api/v1.11/calculator.js?apiKey=\(apiKey)"></script></head>
        <body><div id="c"></div><script>
        const calc = Desmos.GraphingCalculator(document.getElementById('c'), {keypad: false, settingsMenu: false, expressionsCollapsed: false, border: false});
        // The panel is laid out (and zoomed open) after the page loads: follow its size, or Desmos draws into nothing.
        new ResizeObserver(() => calc.resize()).observe(document.getElementById('c'));
        \(list).forEach((latex, i) => calc.setExpression({id: 'e' + i, latex: latex}));
        \(mark)
        window.ready = true;
        </script></body></html>
        """
    }

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.setValue(false, forKey: "drawsBackground")
        w.loadHTMLString(Self.html(expressions, focus: focus), baseURL: URL(string: "https://www.desmos.com"))
        context.coordinator.loaded = expressions + [focus ?? ""]
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        guard context.coordinator.loaded != expressions + [focus ?? ""] else { return }   // new question: load its expressions
        context.coordinator.loaded = expressions + [focus ?? ""]
        w.loadHTMLString(Self.html(expressions, focus: focus), baseURL: URL(string: "https://www.desmos.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loaded: [String] = [] }
}
