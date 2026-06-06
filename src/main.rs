#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod config;
mod git;
mod highlight;
mod i18n;
mod icons;
mod model;
mod parser;
mod path;
mod smells;
mod telemetry;
mod theme;
mod workspace;

mod ui {
    pub mod editor;
    pub mod history;
    pub mod issues;
    pub mod settings;
    pub mod sidebar;
    pub mod status;
    pub mod toolbar;
    pub mod tree;
}

use eframe::egui;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1100.0, 720.0])
            .with_min_inner_size([700.0, 400.0])
            .with_title("Json Viewer"),
        ..Default::default()
    };
    eframe::run_native(
        "jsonview",
        options,
        Box::new(|cc| Ok(Box::new(app::JsonViewApp::new(cc)))),
    )
}
