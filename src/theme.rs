//! Visual theme: IBM Plex type, Proxyman-inspired macOS palette, widget styling.

use crate::model::Kind;
use eframe::egui::{self, Color32, FontFamily, FontId, Rounding, Stroke, TextStyle, Vec2};

/// A flat, Copy palette so UI code can read colors without lifetimes.
#[derive(Clone, Copy)]
pub struct Palette {
    pub dark: bool,
    pub window: Color32,    // editor / main content
    pub sidebar: Color32,   // workspace panel
    pub inspector: Color32, // bottom panel
    pub tree: Color32,      // tree panel
    pub field: Color32,     // text-edit background
    pub sep: Color32,       // hairline separators
    pub text: Color32,
    pub dim: Color32,
    pub accent: Color32,
    pub sel: Color32,  // selection fill (accent tint)
    pub hover: Color32,
}

pub fn palette(dark: bool) -> Palette {
    if dark {
        Palette {
            dark: true,
            window: Color32::from_rgb(0x1c, 0x1e, 0x24),
            sidebar: Color32::from_rgb(0x16, 0x18, 0x1d),
            inspector: Color32::from_rgb(0x15, 0x17, 0x1c),
            tree: Color32::from_rgb(0x1c, 0x1e, 0x24),
            field: Color32::from_rgb(0x11, 0x13, 0x18),
            sep: Color32::from_rgb(0x2c, 0x2f, 0x38),
            text: Color32::from_rgb(0xe6, 0xe8, 0xee),
            dim: Color32::from_rgb(0x7b, 0x81, 0x90),
            accent: Color32::from_rgb(0x4c, 0x8d, 0xff),
            sel: Color32::from_rgba_unmultiplied(0x4c, 0x8d, 0xff, 46),
            hover: Color32::from_rgba_unmultiplied(0xff, 0xff, 0xff, 14),
        }
    } else {
        Palette {
            dark: false,
            window: Color32::from_rgb(0xff, 0xff, 0xff),
            sidebar: Color32::from_rgb(0xf4, 0xf5, 0xf7),
            inspector: Color32::from_rgb(0xfa, 0xfb, 0xfc),
            tree: Color32::from_rgb(0xff, 0xff, 0xff),
            field: Color32::from_rgb(0xff, 0xff, 0xff),
            sep: Color32::from_rgb(0xe2, 0xe4, 0xe9),
            text: Color32::from_rgb(0x1b, 0x1f, 0x24),
            dim: Color32::from_rgb(0x8a, 0x90, 0xa0),
            accent: Color32::from_rgb(0x2d, 0x7f, 0xf9),
            sel: Color32::from_rgba_unmultiplied(0x2d, 0x7f, 0xf9, 38),
            hover: Color32::from_rgba_unmultiplied(0x00, 0x00, 0x00, 12),
        }
    }
}

impl Palette {
    /// Hue for a node-kind badge/label.
    pub fn kind_color(&self, kind: Kind) -> Color32 {
        if self.dark {
            match kind {
                Kind::Object => Color32::from_rgb(0x5b, 0x9b, 0xff),
                Kind::Array => Color32::from_rgb(0x2d, 0xd4, 0xa7),
                Kind::String => Color32::from_rgb(0xe8, 0xb9, 0x64),
                Kind::Number => Color32::from_rgb(0xb7, 0x94, 0xf6),
                Kind::Bool => Color32::from_rgb(0xff, 0x8f, 0xb3),
                Kind::Null => Color32::from_rgb(0x8a, 0x93, 0xa3),
            }
        } else {
            match kind {
                Kind::Object => Color32::from_rgb(0x1f, 0x6f, 0xeb),
                Kind::Array => Color32::from_rgb(0x0d, 0x96, 0x76),
                Kind::String => Color32::from_rgb(0xb5, 0x6a, 0x0a),
                Kind::Number => Color32::from_rgb(0x7c, 0x4d, 0xe0),
                Kind::Bool => Color32::from_rgb(0xd1, 0x3a, 0x73),
                Kind::Null => Color32::from_rgb(0x98, 0xa0, 0xae),
            }
        }
    }
}

const MONO_MED: &str = "mono_medium";
const MONO_SEMI: &str = "mono_semibold";

// ─── Type scale ────────────────────────────────────────────────────────────

#[allow(dead_code)]
/// Semantic font size constants — use these everywhere, not bare floats.
pub mod scale {
    pub const CAPTION: f32 = 10.0;   // section headers, badges
    pub const SMALL: f32 = 11.0;     // status bar, meta, hints
    pub const BODY: f32 = 13.0;      // default prose, labels
    pub const HEADING: f32 = 15.0;   // panel titles (unused — prefer section_label)
    pub const MONO_XS: f32 = 11.0;   // path pills, tiny mono labels
    pub const MONO: f32 = 12.5;      // editor, tree values
    pub const MONO_LG: f32 = 13.5;   // JSONPath input bar
}

#[allow(dead_code)]
/// Build a `FontId` by semantic role.
pub fn font_body() -> egui::FontId {
    egui::FontId::new(scale::BODY, egui::FontFamily::Proportional)
}
#[allow(dead_code)]
pub fn font_mono() -> egui::FontId {
    egui::FontId::new(scale::MONO, egui::FontFamily::Monospace)
}
#[allow(dead_code)]
pub fn font_mono_sm() -> egui::FontId {
    egui::FontId::new(scale::MONO_XS, egui::FontFamily::Name(MONO_SEMI.into()))
}
#[allow(dead_code)]
pub fn font_caption() -> egui::FontId {
    egui::FontId::new(scale::CAPTION, egui::FontFamily::Name(MONO_SEMI.into()))
}

/// Register IBM Plex fonts. Call once at startup.
pub fn install_fonts(ctx: &egui::Context) {
    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        "plex_sans".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexSans-Variable.ttf")),
    );
    fonts.font_data.insert(
        "plex_mono".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexMono-Regular.ttf")),
    );
    fonts.font_data.insert(
        "plex_mono_medium".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexMono-Medium.ttf")),
    );
    fonts.font_data.insert(
        "plex_mono_semibold".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexMono-SemiBold.ttf")),
    );

    fonts
        .families
        .entry(FontFamily::Proportional)
        .or_default()
        .insert(0, "plex_sans".to_owned());
    fonts
        .families
        .entry(FontFamily::Monospace)
        .or_default()
        .insert(0, "plex_mono".to_owned());
    fonts
        .families
        .insert(FontFamily::Name(MONO_MED.into()), vec!["plex_mono_medium".to_owned()]);
    fonts.families.insert(
        FontFamily::Name(MONO_SEMI.into()),
        vec!["plex_mono_semibold".to_owned()],
    );

    ctx.set_fonts(fonts);
}

/// Apply palette + spacing + rounding to the global style.
pub fn apply(ctx: &egui::Context, dark: bool) {
    let p = palette(dark);
    let mut style = (*ctx.style()).clone();

    style.text_styles = [
        (TextStyle::Heading, FontId::new(15.0, FontFamily::Proportional)),
        (TextStyle::Body, FontId::new(13.0, FontFamily::Proportional)),
        (TextStyle::Monospace, FontId::new(12.5, FontFamily::Monospace)),
        (TextStyle::Button, FontId::new(13.0, FontFamily::Proportional)),
        (TextStyle::Small, FontId::new(11.0, FontFamily::Proportional)),
    ]
    .into();

    let s = &mut style.spacing;
    s.item_spacing = Vec2::new(8.0, 6.0);
    s.button_padding = Vec2::new(10.0, 5.0);
    s.menu_margin = egui::Margin::same(6.0);
    s.indent = 16.0;
    s.interact_size.y = 24.0;
    s.scroll = egui::style::ScrollStyle::solid();

    let v = &mut style.visuals;
    v.dark_mode = dark;
    v.override_text_color = Some(p.text);
    v.panel_fill = p.window;
    v.window_fill = p.window;
    v.window_stroke = Stroke::new(1.0, p.sep);
    v.window_rounding = Rounding::same(10.0);
    v.extreme_bg_color = p.field;
    v.code_bg_color = p.field;
    v.faint_bg_color = p.hover;
    v.hyperlink_color = p.accent;
    v.selection.bg_fill = p.sel;
    v.selection.stroke = Stroke::new(1.0, p.accent);

    let r = Rounding::same(6.0);
    let w = &mut v.widgets;
    w.noninteractive.bg_stroke = Stroke::new(1.0, p.sep);
    w.noninteractive.fg_stroke = Stroke::new(1.0, p.text);
    w.noninteractive.rounding = r;

    w.inactive.bg_fill = Color32::TRANSPARENT;
    w.inactive.weak_bg_fill = if dark {
        Color32::from_rgba_unmultiplied(0xff, 0xff, 0xff, 12)
    } else {
        Color32::from_rgb(0xed, 0xee, 0xf2)
    };
    w.inactive.bg_stroke = Stroke::NONE;
    w.inactive.fg_stroke = Stroke::new(1.0, p.text);
    w.inactive.rounding = r;

    w.hovered.weak_bg_fill = p.hover;
    w.hovered.bg_fill = p.hover;
    w.hovered.bg_stroke = Stroke::new(1.0, p.sep);
    w.hovered.fg_stroke = Stroke::new(1.0, p.text);
    w.hovered.rounding = r;

    w.active.weak_bg_fill = p.sel;
    w.active.bg_fill = p.sel;
    w.active.bg_stroke = Stroke::new(1.0, p.accent);
    w.active.fg_stroke = Stroke::new(1.0, p.accent);
    w.active.rounding = r;

    w.open.weak_bg_fill = p.hover;
    w.open.rounding = r;

    ctx.set_style(style);
}

/// Small uppercase mono section header, Proxyman-style.
pub fn section_label(ui: &mut egui::Ui, text: &str) {
    let p = palette(ui.visuals().dark_mode);
    ui.add_space(2.0);
    ui.label(
        egui::RichText::new(text.to_uppercase())
            .family(FontFamily::Name(MONO_SEMI.into()))
            .size(10.0)
            .color(p.dim),
    );
    ui.add_space(2.0);
}

/// Render a rounded, tinted type pill with colored text.
pub fn badge(ui: &mut egui::Ui, text: &str, color: Color32) {
    let font = FontId::new(10.0, FontFamily::Name(MONO_SEMI.into()));
    let galley = ui.painter().layout_no_wrap(text.to_string(), font, color);
    let pad = Vec2::new(5.0, 2.0);
    let (rect, _) = ui.allocate_exact_size(galley.size() + pad * 2.0, egui::Sense::hover());
    let bg = Color32::from_rgba_unmultiplied(color.r(), color.g(), color.b(), 36);
    ui.painter().rect_filled(rect, Rounding::same(4.0), bg);
    ui.painter().galley(rect.min + pad, galley, color);
}

/// Clickable badge — same visual as `badge` but returns a Response.
pub fn badge_button(ui: &mut egui::Ui, text: &str, color: Color32) -> egui::Response {
    let font = FontId::new(10.0, FontFamily::Name(MONO_SEMI.into()));
    let galley = ui.painter().layout_no_wrap(text.to_string(), font, color);
    let pad = Vec2::new(5.0, 2.0);
    let (rect, response) =
        ui.allocate_exact_size(galley.size() + pad * 2.0, egui::Sense::click());
    let bg_alpha = if response.hovered() { 60u8 } else { 36u8 };
    let bg = Color32::from_rgba_unmultiplied(color.r(), color.g(), color.b(), bg_alpha);
    ui.painter().rect_filled(rect, Rounding::same(4.0), bg);
    ui.painter().galley(rect.min + pad, galley, color);
    response
}

/// A segmented-control style toggle button.
pub fn segment(ui: &mut egui::Ui, selected: bool, text: &str) -> egui::Response {
    let p = palette(ui.visuals().dark_mode);
    let mut rich = egui::RichText::new(text).size(12.0);
    if selected {
        rich = rich.color(p.accent);
    }
    ui.selectable_label(selected, rich)
}
