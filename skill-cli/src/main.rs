use anyhow::{bail, Context, Result};
use cc_switch_lib::{AppType, Database, SkillService};
use clap::{Parser, Subcommand};
use serde::Serialize;
use serde_json::json;
use std::process::ExitCode;
use std::str::FromStr;
use std::sync::Arc;

#[derive(Parser, Debug)]
#[command(
    name = "skill-cli",
    version,
    about = "Popskill sidecar for CC Switch skills"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// List all skills managed by CC Switch.
    List {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Find local skills that exist on disk but are not managed by CC Switch.
    ScanUnmanaged {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Enable or disable a skill for one target app.
    Toggle {
        skill_id: String,
        #[arg(long)]
        app: String,
        #[arg(long, action = clap::ArgAction::Set)]
        enabled: bool,
    },
}

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            let payload = ApiResponse::<()>::error("COMMAND_FAILED", format_error(&error));
            eprintln!(
                "{}",
                serde_json::to_string_pretty(&payload).unwrap_or_else(|_| {
                    "{\"ok\":false,\"error\":{\"code\":\"SERIALIZE_ERROR\"}}".to_string()
                })
            );
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<()> {
    let cli = Cli::parse();
    let db = Arc::new(Database::init().context("failed to open CC Switch database")?);

    match cli.command {
        Commands::List { json: _ } => {
            let skills =
                SkillService::get_all_installed(&db).context("failed to list installed skills")?;
            print_json(&ApiResponse::ok(skills))
        }
        Commands::ScanUnmanaged { json: _ } => {
            let skills =
                SkillService::scan_unmanaged(&db).context("failed to scan unmanaged skills")?;
            print_json(&ApiResponse::ok(skills))
        }
        Commands::Toggle {
            skill_id,
            app,
            enabled,
        } => {
            let app_type = parse_target_app(&app)?;
            SkillService::toggle_app(&db, &skill_id, &app_type, enabled)
                .with_context(|| format!("failed to toggle skill '{skill_id}' for {app}"))?;
            print_json(&ApiResponse::ok(json!({
                "id": skill_id,
                "app": app_type.as_str(),
                "enabled": enabled
            })))
        }
    }
}

fn print_json<T: Serialize>(payload: &ApiResponse<T>) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(payload)?);
    Ok(())
}

fn parse_target_app(app: &str) -> Result<AppType> {
    let app_type =
        AppType::from_str(app).with_context(|| format!("unsupported target app '{app}'"))?;
    if app_type == AppType::OpenClaw {
        bail!("OpenClaw does not support skills");
    }
    Ok(app_type)
}

fn format_error(error: &anyhow::Error) -> String {
    error
        .chain()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(": ")
}

#[derive(Serialize)]
struct ApiResponse<T: Serialize> {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<ApiError>,
}

impl<T: Serialize> ApiResponse<T> {
    fn ok(data: T) -> Self {
        Self {
            ok: true,
            data: Some(data),
            error: None,
        }
    }
}

impl ApiResponse<()> {
    fn error(code: &'static str, message: String) -> Self {
        Self {
            ok: false,
            data: None,
            error: Some(ApiError { code, message }),
        }
    }
}

#[derive(Serialize)]
struct ApiError {
    code: &'static str,
    message: String,
}
