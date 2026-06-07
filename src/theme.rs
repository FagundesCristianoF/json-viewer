//! Apple HIG–aligned visual theme: system palette, 4pt grid, semantic depth.

use crate::model::Kind;
use eframe::egui::{self, Color32, FontFamily, FontId, Rounding, Stroke, TextStyle, Vec2};

// ─── Palette ───────────────────────────────────────────────────────────────

#[derive(Clone, Copy)]
pub struct Palette {
    pub dark: bool,
    pub window:    Color32, // main content (editor / tree)
    pub sidebar:   Color32, // workspace panel
    pub elevated:  Color32, // toolbar / popovers — sits above window
    pub inspector: Color32, // bottom panel
    pub tree:      Color32, // tree panel
    pub field:     Color32, // text-edit / input background
    pub sep:       Color32, // hairline separators (Apple rgba spec)
    pub text:      Color32, // label (primary text)
    pub dim:       Color32, // secondaryLabel
    pub muted:     Color32, // tertiaryLabel (hints, placeholders)
    pub accent:    Color32, // systemBlue
    pub sel:       Color32, // selection fill (accent tint)
    pub hover:     Color32, // hover fill
}

pub fn palette(dark: bool) -> Palette {
    if dark {
        Palette {
            dark:      true,
            window:    Color32::from_rgb(0x1c, 0x1c, 0x1e), // secondarySystemBackground
            sidebar:   Color32::from_rgb(0x16, 0x16, 0x18),
            elevated:  Color32::from_rgb(0x2c, 0x2c, 0x2e), // tertiarySystemBackground
            inspector: Color32::from_rgb(0x14, 0x14, 0x16),
            tree:      Color32::from_rgb(0x22, 0x22, 0x24),
            field:     Color32::from_rgb(0x0a, 0x0a, 0x0c),
            sep:       Color32::from_rgba_unmultiplied(84, 84, 88, 90),  // rgba(84,84,88,~0.35)
            text:      Color32::from_rgb(0xff, 0xff, 0xff),
            dim:       Color32::from_rgba_unmultiplied(235, 235, 245, 140), // secondaryLabel
            muted:     Color32::from_rgba_unmultiplied(235, 235, 245, 76),  // tertiaryLabel
            accent:    Color32::from_rgb(0x0a, 0x84, 0xff), // systemBlue dark
            sel:       Color32::from_rgba_unmultiplied(0x0a, 0x84, 0xff, 48),
            hover:     Color32::from_rgba_unmultiplied(255, 255, 255, 10),
        }
    } else {
        Palette {
            dark:      false,
            window:    Color32::from_rgb(0xff, 0xff, 0xff),
            sidebar:   Color32::from_rgb(0xf2, 0xf2, 0xf7), // systemGray6
            elevated:  Color32::from_rgb(0xf9, 0xf9, 0xfb),
            inspector: Color32::from_rgb(0xf2, 0xf2, 0xf7),
            tree:      Color32::from_rgb(0xfa, 0xfa, 0xfd),
            field:     Color32::from_rgb(0xff, 0xff, 0xff),
            sep:       Color32::from_rgba_unmultiplied(60, 60, 67, 50),   // rgba(60,60,67,~0.20)
            text:      Color32::from_rgb(0x00, 0x00, 0x00),
            dim:       Color32::from_rgba_unmultiplied(60, 60, 67, 160),  // secondaryLabel
            muted:     Color32::from_rgba_unmultiplied(60, 60, 67, 76),   // tertiaryLabel
            accent:    Color32::from_rgb(0x00, 0x7a, 0xff), // systemBlue
            sel:       Color32::from_rgba_unmultiplied(0x00, 0x7a, 0xff, 38),
            hover:     Color32::from_rgba_unmultiplied(0, 0, 0, 7),
        }
    }
}

impl Palette {
    pub fn kind_color(&self, kind: Kind) -> Color32 {
        if self.dark {
            match kind {
                Kind::Object => Color32::from_rgb(0x40, 0x9c, 0xff), // systemBlue tint
                Kind::Array  => Color32::from_rgb(0x32, 0xd7, 0x4b), // systemGreen
                Kind::String => Color32::from_rgb(0xff, 0xa0, 0x0a), // systemOrange
                Kind::Number => Color32::from_rgb(0xbf, 0x5a, 0xf2), // systemPurple
                Kind::Bool   => Color32::from_rgb(0xff, 0x45, 0x6d), // systemPink
                Kind::Null   => Color32::from_rgb(0x63, 0x63, 0x66), // systemGray2
            }
        } else {
            match kind {
                Kind::Object => Color32::from_rgb(0x00, 0x6d, 0xe8),
                Kind::Array  => Color32::from_rgb(0x1c, 0x8f, 0x3e),
                Kind::String => Color32::from_rgb(0xb8, 0x62, 0x00),
                Kind::Number => Color32::from_rgb(0x6e, 0x40, 0xc9),
                Kind::Bool   => Color32::from_rgb(0xe3, 0x1a, 0x4c),
                Kind::Null   => Color32::from_rgb(0x8e, 0x8e, 0x93), // systemGray
            }
        }
    }
}

// ─── Type scale ────────────────────────────────────────────────────────────

const MONO_MED:  &str = "mono_medium";
const MONO_SEMI: &str = "mono_semibold";

#[allow(dead_code)]
pub mod scale {
    pub const CAPTION2: f32 = 10.0;
    pub const CAPTION:  f32 = 11.0;
    pub const FOOTNOTE: f32 = 12.0;
    pub const BODY:     f32 = 13.0;
    pub const CALLOUT:  f32 = 14.0;
    pub const HEADLINE: f32 = 15.0;
    pub const MONO_XS:  f32 = 10.5;
    pub const MONO_SM:  f32 = 12.0;
    pub const MONO:     f32 = 12.5;
    pub const MONO_LG:  f32 = 13.5;
}

#[allow(dead_code)]
pub fn font_body()    -> egui::FontId { egui::FontId::new(scale::BODY,    FontFamily::Proportional) }
#[allow(dead_code)]
pub fn font_caption() -> egui::FontId { egui::FontId::new(scale::CAPTION, FontFamily::Proportional) }
#[allow(dead_code)]
pub fn font_mono()    -> egui::FontId { egui::FontId::new(scale::MONO,    FontFamily::Monospace) }
#[allow(dead_code)]
pub fn font_mono_sm() -> egui::FontId { egui::FontId::new(scale::MONO_SM, FontFamily::Name(MONO_SEMI.into())) }

// ─── Font registration ─────────────────────────────────────────────────────

pub fn install_fonts(ctx: &egui::Context) {
    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert("plex_sans".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexSans-Variable.ttf")));
    fonts.font_data.insert("plex_mono".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexMono-Regular.ttf")));
    fonts.font_data.insert("plex_mono_medium".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexMono-Medium.ttf")));
    fonts.font_data.insert("plex_mono_semibold".to_owned(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/IBMPlexMono-SemiBold.ttf")));

    fonts.families.entry(FontFamily::Proportional).or_default().insert(0, "plex_sans".to_owned());
    fonts.families.entry(FontFamily::Monospace).or_default().insert(0, "plex_mono".to_owned());
    fonts.families.insert(FontFamily::Name(MONO_MED.into()),  vec!["plex_mono_medium".to_owned()]);
    fonts.families.insert(FontFamily::Name(MONO_SEMI.into()), vec!["plex_mono_semibold".to_owned()]);
    ctx.set_fonts(fonts);
}

// ─── Global style ──────────────────────────────────────────────────────────

pub fn apply(ctx: &egui::Context, dark: bool) {
    let p = palette(dark);
    let mut style = (*ctx.style()).clone();

    style.text_styles = [
        (TextStyle::Heading,   FontId::new(scale::HEADLINE, FontFamily::Proportional)),
        (TextStyle::Body,      FontId::new(scale::BODY,     FontFamily::Proportional)),
        (TextStyle::Monospace, FontId::new(scale::MONO,     FontFamily::Monospace)),
        (TextStyle::Button,    FontId::new(scale::BODY,     FontFamily::Proportional)),
        (TextStyle::Small,     FontId::new(scale::CAPTION,  FontFamily::Proportional)),
    ].into();

    let s = &mut style.spacing;
    s.item_spacing    = Vec2::new(6.0, 4.0);
    s.button_padding  = Vec2::new(12.0, 6.0);
    s.menu_margin     = egui::Margin::same(6.0);
    s.indent          = 16.0;
    s.interact_size.y = 28.0;
    s.scroll          = egui::style::ScrollStyle::solid();

    let v = &mut style.visuals;
    v.dark_mode           = dark;
    v.override_text_color = Some(p.text);
    v.panel_fill          = p.window;
    v.window_fill         = p.elevated;
    v.window_stroke       = Stroke::new(0.5, p.sep);
    v.window_rounding     = Rounding::same(12.0);
    v.window_shadow       = if dark {
        egui::Shadow { offset: egui::Vec2::new(0.0, 8.0), blur: 28.0, spread: 0.0, color: Color32::from_black_alpha(90) }
    } else {
        egui::Shadow { offset: egui::Vec2::new(0.0, 4.0), blur: 16.0, spread: 0.0, color: Color32::from_black_alpha(24) }
    };
    v.extreme_bg_color    = p.field;
    v.code_bg_color       = p.field;
    v.faint_bg_color      = p.hover;
    v.hyperlink_color     = p.accent;
    v.selection.bg_fill   = p.sel;
    v.selection.stroke    = Stroke::new(1.0, p.accent);
    v.popup_shadow        = v.window_shadow;

    let ctrl_r = Rounding::same(8.0);
    let w = &mut v.widgets;

    w.noninteractive.bg_stroke    = Stroke::new(0.5, p.sep);
    w.noninteractive.fg_stroke    = Stroke::new(1.0, p.dim);
    w.noninteractive.rounding     = ctrl_r;
    w.noninteractive.bg_fill      = Color32::TRANSPARENT;
    w.noninteractive.weak_bg_fill = Color32::TRANSPARENT;

    let btn_fill = if dark {
        Color32::from_rgba_unmultiplied(255, 255, 255, 16)
    } else {
        Color32::from_rgb(0xf5, 0xf5, 0xf7)
    };
    let btn_stroke = if dark {
        Stroke::new(0.5, Color32::from_rgba_unmultiplied(255, 255, 255, 28))
    } else {
        Stroke::new(0.5, Color32::from_rgba_unmultiplied(0, 0, 0, 20))
    };

    w.inactive.bg_fill       = btn_fill;
    w.inactive.weak_bg_fill  = btn_fill;
    w.inactive.bg_stroke     = btn_stroke;
    w.inactive.fg_stroke     = Stroke::new(1.0, p.text);
    w.inactive.rounding      = ctrl_r;

    let hover_fill = if dark {
        Color32::from_rgba_unmultiplied(255, 255, 255, 24)
    } else {
        Color32::from_rgb(0xeb, 0xeb, 0xed)
    };
    w.hovered.bg_fill       = hover_fill;
    w.hovered.weak_bg_fill  = hover_fill;
    w.hovered.bg_stroke     = btn_stroke;
    w.hovered.fg_stroke     = Stroke::new(1.0, p.text);
    w.hovered.rounding      = ctrl_r;

    w.active.bg_fill        = p.sel;
    w.active.weak_bg_fill   = p.sel;
    w.active.bg_stroke      = Stroke::new(1.0, p.accent);
    w.active.fg_stroke      = Stroke::new(1.5, p.accent);
    w.active.rounding       = ctrl_r;
    w.active.expansion      = 0.0;

    w.open.weak_bg_fill     = hover_fill;
    w.open.rounding         = ctrl_r;

    ctx.set_style(style);
}

// ─── Component helpers ─────────────────────────────────────────────────────

/// Compact section header: small muted all-caps proportional label.
pub fn section_label(ui: &mut egui::Ui, text: &str) {
    let p = palette(ui.visuals().dark_mode);
    ui.label(
        egui::RichText::new(text.to_uppercase())
            .size(scale::CAPTION2 + 0.5)
            .color(p.muted)
            .family(FontFamily::Proportional),
    );
}

/// Full-capsule type badge with tinted background.
pub fn badge(ui: &mut egui::Ui, text: &str, color: Color32) {
    let font = FontId::new(scale::CAPTION2, FontFamily::Name(MONO_SEMI.into()));
    let galley = ui.painter().layout_no_wrap(text.to_string(), font, color);
    let pad = Vec2::new(6.0, 2.0);
    let (rect, _) = ui.allocate_exact_size(galley.size() + pad * 2.0, egui::Sense::hover());
    let bg = Color32::from_rgba_unmultiplied(color.r(), color.g(), color.b(), 30);
    ui.painter().rect_filled(rect, Rounding::same(100.0), bg);
    ui.painter().galley(rect.min + pad, galley, color);
}

/// Clickable badge — capsule, interactive.
pub fn badge_button(ui: &mut egui::Ui, text: &str, color: Color32) -> egui::Response {
    let font = FontId::new(scale::CAPTION2, FontFamily::Name(MONO_SEMI.into()));
    let galley = ui.painter().layout_no_wrap(text.to_string(), font, color);
    let pad = Vec2::new(6.0, 2.0);
    let (rect, resp) = ui.allocate_exact_size(galley.size() + pad * 2.0, egui::Sense::click());
    let alpha = if resp.hovered() { 52u8 } else { 30u8 };
    let bg = Color32::from_rgba_unmultiplied(color.r(), color.g(), color.b(), alpha);
    ui.painter().rect_filled(rect, Rounding::same(100.0), bg);
    ui.painter().galley(rect.min + pad, galley, color);
    resp
}

/// Inline segmented-control toggle button.
pub fn segment(ui: &mut egui::Ui, selected: bool, text: &str) -> egui::Response {
    let p = palette(ui.visuals().dark_mode);
    let color = if selected { p.accent } else { p.text };
    ui.selectable_label(selected, egui::RichText::new(text).size(scale::BODY).color(color))
}
