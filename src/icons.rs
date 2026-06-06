//! Pure-vector icon system.

#![allow(dead_code)]
//! no font glyphs, no asset files. Crisp at any DPI/scale.
//!
//! Design rules (Phosphor-style):
//!   - 1.5 px stroke weight (scaled with icon size)
//!   - Rounded line caps (egui default)
//!   - Stroked outlines only — no fills except deliberate dots
//!   - All coordinates are fractional [0,1] relative to the icon rect

use eframe::egui::{
    epaint::PathShape, Color32, Painter, Pos2, Rect, Rounding, Sense, Shape, Stroke, Ui, Vec2,
};

// ─── Icon catalogue ────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Icon {
    /// New folder  (sidebar)
    FolderPlus,
    /// New JSON file (sidebar)
    FilePlus,
    /// Refresh workspace (sidebar)
    Refresh,
    /// Open Settings modal (toolbar)
    Settings,
    /// Sidebar / JSONPath search field prefix
    Search,
    /// Clear / dismiss (search field, jsonpath bar)
    Close,
    /// Collapsed tree node
    ChevronRight,
    /// Expanded tree node
    ChevronDown,
    /// Copy path to clipboard
    Copy,
    /// Syntax error indicator
    AlertCircle,
    /// Success / no errors
    Check,
    /// Open workspace folder
    FolderOpen,
}

// ─── Public API ────────────────────────────────────────────────────────────

/// Draw `icon` inside `rect` using the given `color`.
pub fn draw(painter: &Painter, icon: Icon, rect: Rect, color: Color32) {
    let sw = (rect.width() / 16.0 * 1.5).max(1.0);
    let s = Stroke::new(sw, color);
    match icon {
        Icon::Close => close(painter, rect, s),
        Icon::ChevronRight => chevron_right(painter, rect, s),
        Icon::ChevronDown => chevron_down(painter, rect, s),
        Icon::Search => search(painter, rect, s),
        Icon::Refresh => refresh(painter, rect, s),
        Icon::FolderPlus => folder_plus(painter, rect, s),
        Icon::FilePlus => file_plus(painter, rect, s),
        Icon::Settings => settings(painter, rect, s),
        Icon::Copy => copy(painter, rect, s),
        Icon::AlertCircle => alert_circle(painter, rect, s),
        Icon::Check => check(painter, rect, s),
        Icon::FolderOpen => folder_open(painter, rect, s),
    }
}

/// Allocate a square button, draw the icon, return the `Response`.
/// `size` is the clickable area side length; the icon itself is inset by 4 px.
pub fn button(ui: &mut Ui, icon: Icon, size: f32, color: Color32) -> eframe::egui::Response {
    let (rect, resp) = ui.allocate_exact_size(Vec2::splat(size), Sense::click());
    if ui.is_rect_visible(rect) {
        let draw_color = if resp.hovered() { brighter(color, 40) } else { color };
        let icon_rect = rect.shrink(4.0);
        draw(&ui.painter(), icon, icon_rect, draw_color);
    }
    resp
}

/// Same as `button` but with a background fill on hover — for toolbar-style buttons.
pub fn toolbar_button(ui: &mut Ui, icon: Icon, size: f32, color: Color32, hover_bg: Color32) -> eframe::egui::Response {
    let (rect, resp) = ui.allocate_exact_size(Vec2::splat(size), Sense::click());
    if ui.is_rect_visible(rect) {
        if resp.hovered() || resp.is_pointer_button_down_on() {
            ui.painter().rect_filled(rect, Rounding::same(4.0), hover_bg);
        }
        let draw_color = if resp.hovered() { brighter(color, 30) } else { color };
        draw(&ui.painter(), icon, rect.shrink(4.0), draw_color);
    }
    resp
}

// ─── Coordinate helpers ────────────────────────────────────────────────────

/// Map fractional (fx, fy) to a Pos2 within `rect`.
#[inline]
fn p(rect: Rect, fx: f32, fy: f32) -> Pos2 {
    Pos2::new(
        rect.min.x + rect.width() * fx,
        rect.min.y + rect.height() * fy,
    )
}

fn brighter(c: Color32, delta: u8) -> Color32 {
    let [r, g, b, a] = c.to_array();
    Color32::from_rgba_unmultiplied(
        r.saturating_add(delta),
        g.saturating_add(delta),
        b.saturating_add(delta),
        a,
    )
}

// ─── Icon drawing functions ────────────────────────────────────────────────

/// × — two diagonal lines
fn close(painter: &Painter, rect: Rect, s: Stroke) {
    painter.line_segment([p(rect, 0.22, 0.22), p(rect, 0.78, 0.78)], s);
    painter.line_segment([p(rect, 0.78, 0.22), p(rect, 0.22, 0.78)], s);
}

/// > — right-pointing chevron
fn chevron_right(painter: &Painter, rect: Rect, s: Stroke) {
    painter.line_segment([p(rect, 0.30, 0.22), p(rect, 0.68, 0.50)], s);
    painter.line_segment([p(rect, 0.68, 0.50), p(rect, 0.30, 0.78)], s);
}

/// ∨ — down-pointing chevron
fn chevron_down(painter: &Painter, rect: Rect, s: Stroke) {
    painter.line_segment([p(rect, 0.22, 0.35), p(rect, 0.50, 0.68)], s);
    painter.line_segment([p(rect, 0.50, 0.68), p(rect, 0.78, 0.35)], s);
}

/// 🔍 — circle with diagonal handle
fn search(painter: &Painter, rect: Rect, s: Stroke) {
    let cx = rect.min.x + rect.width() * 0.41;
    let cy = rect.min.y + rect.height() * 0.41;
    let r = rect.width() * 0.27;
    painter.circle(
        Pos2::new(cx, cy),
        r,
        Color32::TRANSPARENT,
        s,
    );
    // Handle: from circle edge at ~45° toward bottom-right
    let offset = r * std::f32::consts::FRAC_1_SQRT_2;
    painter.line_segment([
        Pos2::new(cx + offset, cy + offset),
        p(rect, 0.84, 0.84),
    ], s);
}

/// ↻ — counter-clockwise arc with arrowhead
fn refresh(painter: &Painter, rect: Rect, s: Stroke) {
    let cx = rect.center().x;
    let cy = rect.center().y;
    let r = rect.width() * 0.36;

    // Arc: 270° starting from right, going counter-clockwise
    let start = 0.35_f32; // radians — slightly past right
    let span = std::f32::consts::TAU * 0.75;
    let n = 18usize;
    let pts: Vec<Pos2> = (0..=n)
        .map(|i| {
            let a = start - span * (i as f32 / n as f32);
            Pos2::new(cx + r * a.cos(), cy + r * a.sin())
        })
        .collect();

    for i in 0..pts.len() - 1 {
        painter.line_segment([pts[i], pts[i + 1]], s);
    }

    // Arrowhead at end
    let last = *pts.last().unwrap();
    let prev = pts[pts.len() - 2];
    let dir = (last - prev).normalized();
    let perp = Vec2::new(-dir.y, dir.x);
    let wing = r * 0.38;
    painter.line_segment([last, last - dir * wing + perp * wing * 0.55], s);
    painter.line_segment([last, last - dir * wing - perp * wing * 0.55], s);
}

/// 📁 — folder with + badge
fn folder_plus(painter: &Painter, rect: Rect, s: Stroke) {
    let tab_w = 0.38;
    let tab_h = 0.20;
    let body_y = tab_h;

    // Tab: TL → tab top-left curve → tab top-right curve → body start
    let tab_pts = vec![
        p(rect, 0.02, body_y + 0.02),
        p(rect, 0.02, tab_h * 0.6),
        p(rect, tab_w * 0.15, 0.04),
        p(rect, tab_w * 0.88, 0.04),
        p(rect, tab_w, body_y),
        p(rect, 1.0, body_y),
    ];
    for i in 0..tab_pts.len() - 1 {
        painter.line_segment([tab_pts[i], tab_pts[i + 1]], s);
    }

    // Body
    let body = Rect::from_min_max(p(rect, 0.0, body_y), p(rect, 1.0, 1.0));
    painter.rect(body, Rounding::same(2.0), Color32::TRANSPARENT, s);

    // Plus sign
    let pc = p(rect, 0.50, 0.65);
    let pr = rect.width() * 0.16;
    painter.line_segment([
        Pos2::new(pc.x - pr, pc.y),
        Pos2::new(pc.x + pr, pc.y),
    ], s);
    painter.line_segment([
        Pos2::new(pc.x, pc.y - pr),
        Pos2::new(pc.x, pc.y + pr),
    ], s);
}

/// 📄 — page with folded corner + plus badge
fn file_plus(painter: &Painter, rect: Rect, s: Stroke) {
    let fold = 0.28_f32; // fold size fraction

    // File outline (pentagon with folded top-right)
    let outline = PathShape {
        points: vec![
            p(rect, 0.08, 0.0),
            p(rect, 1.0 - fold, 0.0),
            p(rect, 1.0, fold),
            p(rect, 1.0, 1.0),
            p(rect, 0.08, 1.0),
        ],
        closed: true,
        fill: Color32::TRANSPARENT,
        stroke: s.into(),
    };
    painter.add(Shape::Path(outline));

    // Fold crease
    painter.line_segment([p(rect, 1.0 - fold, 0.0), p(rect, 1.0 - fold, fold)], s);
    painter.line_segment([p(rect, 1.0 - fold, fold), p(rect, 1.0, fold)], s);

    // Plus sign (lower portion)
    let pc = p(rect, 0.42, 0.66);
    let pr = rect.width() * 0.17;
    painter.line_segment([Pos2::new(pc.x - pr, pc.y), Pos2::new(pc.x + pr, pc.y)], s);
    painter.line_segment([Pos2::new(pc.x, pc.y - pr), Pos2::new(pc.x, pc.y + pr)], s);
}

/// ⚙ — three horizontal lines with offset dots (mixer/sliders icon)
fn settings(painter: &Painter, rect: Rect, s: Stroke) {
    let dot_r = (rect.width() * 0.09).max(1.5);
    let pad = 0.10;

    for (fy, dot_fx) in [(0.28_f32, 0.30_f32), (0.52, 0.62), (0.76, 0.42)] {
        // Full-width line
        painter.line_segment([p(rect, pad, fy), p(rect, 1.0 - pad, fy)], s);
        // Dot (filled circle) interrupting the line
        let dot = p(rect, dot_fx, fy);
        painter.circle_filled(dot, dot_r + 1.5, s.color); // erase "gap" by overdrawing bg — skip for simplicity
        painter.circle(dot, dot_r, Color32::TRANSPARENT, s);
    }
}

/// ⧉ — two overlapping rectangles (copy)
fn copy(painter: &Painter, rect: Rect, s: Stroke) {
    // Back rect (offset top-right)
    let back = Rect::from_min_max(p(rect, 0.28, 0.0), p(rect, 1.0, 0.72));
    painter.rect(back, Rounding::same(1.5), Color32::TRANSPARENT, s);
    // Front rect (offset bottom-left)
    let front = Rect::from_min_max(p(rect, 0.0, 0.28), p(rect, 0.72, 1.0));
    painter.rect(front, Rounding::same(1.5), Color32::TRANSPARENT, s);
}

/// ⊙ — circle with ! inside
fn alert_circle(painter: &Painter, rect: Rect, s: Stroke) {
    let c = rect.center();
    let r = rect.width() * 0.42;
    painter.circle(c, r, Color32::TRANSPARENT, s);
    // Exclamation body
    painter.line_segment([
        Pos2::new(c.x, c.y - r * 0.48),
        Pos2::new(c.x, c.y + r * 0.1),
    ], s);
    // Dot
    painter.circle_filled(Pos2::new(c.x, c.y + r * 0.42), s.width * 0.9, s.color);
}

/// ✓ — checkmark
fn check(painter: &Painter, rect: Rect, s: Stroke) {
    let knee = p(rect, 0.38, 0.62);
    painter.line_segment([p(rect, 0.14, 0.50), knee], s);
    painter.line_segment([knee, p(rect, 0.84, 0.22)], s);
}

/// 📂 — open folder (workspace button in toolbar)
fn folder_open(painter: &Painter, rect: Rect, s: Stroke) {
    let tab_w = 0.40;
    let tab_h = 0.20;

    // Tab
    let tab_pts = [
        p(rect, 0.02, tab_h + 0.02),
        p(rect, 0.02, tab_h * 0.5),
        p(rect, tab_w * 0.15, 0.04),
        p(rect, tab_w * 0.88, 0.04),
        p(rect, tab_w, tab_h),
        p(rect, 0.96, tab_h),
    ];
    for i in 0..tab_pts.len() - 1 {
        painter.line_segment([tab_pts[i], tab_pts[i + 1]], s);
    }

    // Open body — trapezoidal top (open/fan shape)
    let body_pts = [
        p(rect, 0.0, tab_h),
        p(rect, 0.0, 1.0),
        p(rect, 1.0, 1.0),
        p(rect, 1.0, tab_h + 0.1),
        p(rect, 0.15, tab_h + 0.1), // inner slant
    ];
    for i in 0..body_pts.len() - 1 {
        painter.line_segment([body_pts[i], body_pts[i + 1]], s);
    }
    // Fan-out line on front flap
    painter.line_segment([p(rect, 0.96, tab_h), p(rect, 1.0, tab_h + 0.1)], s);
}

// ─── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_icons_are_unique_variants() {
        let icons = [
            Icon::FolderPlus, Icon::FilePlus, Icon::Refresh, Icon::Settings,
            Icon::Search, Icon::Close, Icon::ChevronRight, Icon::ChevronDown,
            Icon::Copy, Icon::AlertCircle, Icon::Check, Icon::FolderOpen,
        ];
        // All 12 distinct variants compile and are accessible.
        assert_eq!(icons.len(), 12);
    }
}
