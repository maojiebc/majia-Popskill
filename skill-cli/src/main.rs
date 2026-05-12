use anyhow::{Context, Result, bail};
use cc_switch_lib::{AppType, Database, ImportSkillSelection, SkillApps, SkillService};
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
    /// Return one installed skill by id.
    Detail {
        skill_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Check remote content hashes for installed skills with GitHub sources.
    CheckUpdates {
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Discover installable skills from enabled CC Switch skill repositories.
    Discover {
        #[arg(long)]
        query: Option<String>,
        #[arg(long, default_value_t = 80)]
        limit: usize,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Install one discoverable skill by key.
    Install {
        skill_key: String,
        #[arg(long, default_value = "claude")]
        app: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Update one installed skill from its GitHub source.
    Update {
        skill_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Uninstall one installed skill.
    Uninstall {
        skill_id: String,
        /// Kept for the Swift client contract; output is JSON either way.
        #[arg(long)]
        json: bool,
    },
    /// Import an unmanaged local skill directory into CC Switch.
    ImportUnmanaged {
        directory: String,
        /// Target apps to enable after import. Can be passed multiple times.
        #[arg(long = "app")]
        apps: Vec<String>,
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
        Commands::Detail { skill_id, json: _ } => {
            let skill = db
                .get_installed_skill(&skill_id)
                .context("failed to read installed skill")?
                .with_context(|| format!("skill not found: {skill_id}"))?;
            print_json(&ApiResponse::ok(skill))
        }
        Commands::CheckUpdates { json: _ } => {
            let service = SkillService::new();
            let updates = service
                .check_updates(&db)
                .await
                .context("failed to check skill updates")?;
            print_json(&ApiResponse::ok(updates))
        }
        Commands::Discover {
            query,
            limit,
            json: _,
        } => {
            let service = SkillService::new();
            db.init_default_skill_repos()
                .context("failed to initialize default skill repositories")?;
            let repos = db
                .get_skill_repos()
                .context("failed to load skill repositories")?;
            let skills = service
                .list_skills(repos, &db)
                .await
                .context("failed to discover skills")?;
            let normalized_query = query
                .as_deref()
                .map(str::trim)
                .filter(|query| !query.is_empty())
                .map(str::to_lowercase);
            let filtered: Vec<_> = skills
                .into_iter()
                .filter(|skill| {
                    let Some(query) = normalized_query.as_deref() else {
                        return true;
                    };
                    skill.name.to_lowercase().contains(query)
                        || skill.description.to_lowercase().contains(query)
                        || skill.directory.to_lowercase().contains(query)
                        || skill
                            .repo_owner
                            .as_deref()
                            .unwrap_or_default()
                            .to_lowercase()
                            .contains(query)
                        || skill
                            .repo_name
                            .as_deref()
                            .unwrap_or_default()
                            .to_lowercase()
                            .contains(query)
                })
                .take(limit)
                .collect();
            print_json(&ApiResponse::ok(filtered))
        }
        Commands::Install {
            skill_key,
            app,
            json: _,
        } => {
            let app_type = parse_target_app(&app)?;
            let service = SkillService::new();
            db.init_default_skill_repos()
                .context("failed to initialize default skill repositories")?;
            let repos = db
                .get_skill_repos()
                .context("failed to load skill repositories")?;
            let skills = service
                .discover_available(repos)
                .await
                .context("failed to discover skills before install")?;
            let skill = skills
                .into_iter()
                .find(|skill| skill.key == skill_key)
                .with_context(|| format!("discoverable skill not found: {skill_key}"))?;
            let installed = service
                .install(&db, &skill, &app_type)
                .await
                .with_context(|| format!("failed to install skill '{skill_key}'"))?;
            print_json(&ApiResponse::ok(installed))
        }
        Commands::Update { skill_id, json: _ } => {
            let service = SkillService::new();
            let skill = service
                .update_skill(&db, &skill_id)
                .await
                .with_context(|| format!("failed to update skill '{skill_id}'"))?;
            print_json(&ApiResponse::ok(skill))
        }
        Commands::Uninstall { skill_id, json: _ } => {
            let result = SkillService::uninstall(&db, &skill_id)
                .with_context(|| format!("failed to uninstall skill '{skill_id}'"))?;
            print_json(&ApiResponse::ok(result))
        }
        Commands::ImportUnmanaged {
            directory,
            apps,
            json: _,
        } => {
            let apps = parse_skill_apps(&apps)?;
            let imported = SkillService::import_from_apps(
                &db,
                vec![ImportSkillSelection { directory, apps }],
            )
            .context("failed to import unmanaged skill")?;
            print_json(&ApiResponse::ok(imported))
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

fn parse_skill_apps(apps: &[String]) -> Result<SkillApps> {
    let targets: Vec<&str> = if apps.is_empty() {
        vec!["claude"]
    } else {
        apps.iter().map(String::as_str).collect()
    };

    let mut skill_apps = SkillApps::default();
    for app in targets {
        let app_type = parse_target_app(app)?;
        skill_apps.set_enabled_for(&app_type, true);
    }
    Ok(skill_apps)
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
